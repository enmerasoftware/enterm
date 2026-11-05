import CPTY
import EntermCore
import Foundation

// The session service. It owns every pseudo terminal, so sessions outlive the window.
// It does nothing unless a program writes or a client speaks, and exits when nothing is left.

signal(SIGPIPE, SIG_IGN)
setsid()
EntermPaths.ensureDirectories()
ShellIntegration.install()

final class Client {
    let fd: Int32
    var decoder = WireDecoder()
    var readSource: DispatchSourceRead?
    var writeSource: DispatchSourceWrite?
    var pending = Data()
    var attached = Set<UInt32>()
    var subscribed = false
    var waitingApproval: String?
    var isPhone = false
    init(fd: Int32) { self.fd = fd }
}

final class Session {
    var info: SessionInfo
    let master: Int32
    var readSource: DispatchSourceRead?
    var processSource: DispatchSourceProcess?
    var ring = Data()
    var dirty = false
    var replayedOldLog = false
    var rows = 24
    var cols = 80
    var wasResized = false
    var lastOutput = Date.distantPast
    var quietCheck = false
    init(info: SessionInfo, master: Int32) {
        self.info = info
        self.master = master
    }
}

final class Service {
    static let ringLimit = 1024 * 1024
    static let shellStartColumns = 20
    let queue = DispatchQueue(label: "enterm.service")
    var listener: DispatchSourceRead?
    var clients: [Int32: Client] = [:]
    var sessions: [UInt32: Session] = [:]
    var nextNumber: UInt32 = 1
    lazy var phones = PhoneCenter(service: self)
    var idleTimer: DispatchSourceTimer?
    var flushTimer: DispatchSourceTimer?
    var permissions = PermissionBook.load()
    var approvals: [String: ApprovalRequest] = [:]
    var lastNotFound: [String: String] = [:]
    let hostEnvironment = ProcessInfo.processInfo.environment
    let buildStamp = Bundle.main.executablePath.flatMap(EntermVersion.stamp(ofExecutable:))
    let cliPath: String = {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return exe.deletingLastPathComponent().appendingPathComponent("enterm").path
    }()
    var reportedCLI: String?

    func start() {
        let path = EntermPaths.socket.path
        let probe = WireSocket.connect(path: path)
        if let probe {
            close(probe)
            exit(0)
        }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { exit(1) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let previous = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previous)
        guard bound == 0, listen(fd, 16) == 0 else { exit(1) }
        chmod(path, 0o600)
        phones.start()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept(fd) }
        source.resume()
        listener = source
        scheduleIdleCheck()
    }

    // MARK: Clients

    func accept(_ listenFD: Int32) {
        let fd = Darwin.accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        _ = adopt(fd)
    }

    @discardableResult
    func adopt(_ fd: Int32) -> Client {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let client = Client(fd: fd)
        clients[fd] = client
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self, weak client] in
            guard let self, let client else { return }
            self.readClient(client)
        }
        source.resume()
        client.readSource = source
        cancelIdleCheck()
        return client
    }

    func readClient(_ client: Client) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(client.fd, &buffer, buffer.count)
        if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) {
            drop(client)
            return
        }
        guard count > 0 else { return }
        for frame in client.decoder.feed(Data(buffer[0..<count])) {
            handle(frame, from: client)
        }
    }

    func drop(_ client: Client) {
        client.readSource?.cancel()
        client.writeSource?.cancel()
        client.readSource = nil
        client.writeSource = nil
        clients[client.fd] = nil
        close(client.fd)
        // The hook stopped waiting: the program's own question is on screen now, the card has nothing left to answer.
        if let id = client.waitingApproval, let request = approvals.removeValue(forKey: id) {
            approvalHosts[id] = nil
            if let session = sessionByID(request.sessionID), session.info.pendingApproval?.id == id {
                session.info.pendingApproval = nil
                publish(session)
            }
        }
        if heavyQueue.contains(where: { !$0.running && $0.client == nil || $0.client === client && !$0.running }) { advanceHeavy() }
        scheduleIdleCheck()
    }

    func send(_ frame: WireFrame, to client: Client) {
        let data = frame.encoded()
        if client.pending.isEmpty {
            let written = data.withUnsafeBytes { write(client.fd, $0.baseAddress, $0.count) }
            if written == data.count { return }
            if written < 0 && errno != EAGAIN && errno != EINTR {
                drop(client)
                return
            }
            client.pending.append(data.dropFirst(max(written, 0)))
        } else {
            client.pending.append(data)
        }
        // A client that stops reading must not grow the service without limit.
        if client.pending.count > 32 * 1024 * 1024 {
            drop(client)
            return
        }
        if client.writeSource == nil {
            let source = DispatchSource.makeWriteSource(fileDescriptor: client.fd, queue: queue)
            source.setEventHandler { [weak self, weak client] in
                guard let self, let client else { return }
                self.flush(client)
            }
            source.resume()
            client.writeSource = source
        }
    }

    func flush(_ client: Client) {
        guard !client.pending.isEmpty else {
            client.writeSource?.cancel()
            client.writeSource = nil
            return
        }
        let written = client.pending.withUnsafeBytes { write(client.fd, $0.baseAddress, $0.count) }
        if written < 0 {
            if errno != EAGAIN && errno != EINTR { drop(client) }
            return
        }
        client.pending = Data(client.pending.dropFirst(written))
    }

    func broadcast(_ message: WireMessage) {
        let frame = message.frame()
        for client in clients.values where client.subscribed {
            send(frame, to: client)
        }
    }

    func publish(_ session: Session) {
        phones.sessionChanged(session.info)
        var message = WireMessage(op: "session")
        message.session = session.info
        broadcast(message)
        persistSoon()
    }

    // MARK: Requests

    func handle(_ frame: WireFrame, from client: Client) {
        switch frame.kind {
        case .input:
            guard let (number, bytes) = frame.splitSession(), let session = sessions[number] else { return }
            bytes.withUnsafeBytes { _ = write(session.master, $0.baseAddress, $0.count) }
            // Codex only reports the end of a turn. Enter starts the next one.
            if session.info.tool == .codex, session.info.status == .idle || session.info.status == .unknown, bytes.contains(13) {
                session.info.status = .running
                publish(session)
            }
        case .json:
            guard let message = WireMessage.decode(frame.payload) else { return }
            handleMessage(message, from: client)
        default:
            break
        }
    }

    func handleMessage(_ message: WireMessage, from client: Client) {
        if phones.handle(message, from: client) { return }
        switch message.op {
        case "hello":
            client.subscribed = true
            if !client.isPhone, let path = message.text { reportedCLI = path }
            var reply = WireMessage(op: "state")
            reply.version = WireMessage.protocolVersion
            reply.text = buildStamp
            reply.sessions = sessions.values.map(\.info).sorted { $0.number < $1.number }
            send(reply.frame(), to: client)
        case "create":
            guard let spec = message.spec else { return }
            var reply = WireMessage(op: "created")
            reply.id = message.id
            do {
                let session = try create(spec)
                reply.session = session.info
                send(reply.frame(), to: client)
                publish(session)
            } catch {
                reply.error = "\(error)"
                send(reply.frame(), to: client)
            }
        case "attach":
            guard let number = message.number, let session = sessions[number] else { return }
            client.attached.insert(number)
            if !session.ring.isEmpty {
                send(WireFrame.session(.replay, number: number, bytes: session.ring), to: client)
            }
        case "detach":
            if let number = message.number { client.attached.remove(number) }
        case "resize":
            guard let number = message.number, let session = sessions[number],
                  let rows = message.rows, let cols = message.cols else { return }
            _ = cpty_resize(session.master, UInt16(rows), UInt16(cols))
            session.wasResized = true
            if !client.isPhone {
                session.rows = rows
                session.cols = cols
            }
        case "kill":
            guard let number = message.number, let session = sessions[number] else { return }
            if session.info.status == .exited {
                remove(session)
            } else if let pid = session.info.pid {
                kill(pid, SIGHUP)
            }
        case "remove":
            guard let number = message.number, let session = sessions[number] else { return }
            remove(session)
        case "rename":
            guard let number = message.number, let session = sessions[number], let text = message.text else { return }
            session.info.name = text
            publish(session)
        case "setGroup":
            guard let number = message.number, let session = sessions[number] else { return }
            session.info.group = message.text
            publish(session)
        case "setStatus":
            guard let number = message.number, let session = sessions[number], let text = message.text,
                  let status = SessionStatus(rawValue: text) else { return }
            session.info.status = status
            publish(session)
        case "setPriority":
            guard let number = message.number, let session = sessions[number], let pid = session.info.pid,
                  let limit = message.limit else { return }
            setpriority(PRIO_PGRP, id_t(pid), Int32(limit))
        case "stop":
            guard let number = message.number, let session = sessions[number], let pid = session.info.pid else { return }
            killpg(pid, message.limit == 1 ? SIGCONT : SIGSTOP)
        case "event":
            if let event = message.event { apply(event) }
        case "approval":
            guard let event = message.event else { return }
            startApproval(event, client: client)
        case "decide":
            if let id = message.id, let decision = message.decision {
                finishApproval(id: id, decision: decision, remember: message.text == "remember")
            }
        case "reloadPermissions":
            permissions = PermissionBook.load()
        case "notify":
            var note = WireMessage(op: "notice")
            note.text = message.text
            broadcast(note)
            phones.scriptSaid(message.text ?? "")
            var reply = WireMessage(op: "ok")
            reply.id = message.id
            send(reply.frame(), to: client)
        case "list":
            var reply = WireMessage(op: "state")
            reply.sessions = sessions.values.map(\.info).sorted { $0.number < $1.number }
            send(reply.frame(), to: client)
        case "tail":
            guard let number = message.number, let session = sessions[number] else { return }
            var reply = WireMessage(op: "tail")
            reply.id = message.id
            reply.text = Service.plainText(session.ring.suffix(16 * 1024), lines: 40)
            send(reply.frame(), to: client)
        case "lock":
            guard let event = message.event, let path = event.text else { return }
            var reply = WireMessage(op: "decision")
            if let owner = fileLocks[path], owner != event.sessionID, sessionByID(owner) != nil {
                reply.decision = "deny"
            } else {
                fileLocks[path] = event.sessionID
                reply.decision = "allow"
            }
            send(reply.frame(), to: client)
        case "heavyStart":
            guard let event = message.event, let session = sessionByID(event.sessionID) else {
                var reply = WireMessage(op: "decision")
                reply.decision = "allow"
                send(reply.frame(), to: client)
                return
            }
            heavyQueue.append(HeavyWaiter(sessionID: session.info.id, name: session.info.name.isEmpty ? session.info.tool.title : session.info.name,
                                          command: event.text ?? "", client: client))
            advanceHeavy()
        case "heavyDone":
            if let id = message.event?.sessionID { finishHeavy(id) }
        case "heavyList":
            var reply = WireMessage(op: "heavy")
            reply.id = message.id
            reply.text = heavyJSON()
            send(reply.frame(), to: client)
        case "shutdown":
            // The user chose to remove Enterm: every session ends and the service exits.
            for session in sessions.values {
                if let pid = session.info.pid { kill(pid, SIGHUP) }
            }
            unlink(EntermPaths.socket.path)
            exit(0)
        case "browser":
            // From an agent's bridge to the window that owns the browser, and back.
            let id = UUID().uuidString
            browserWaiting[id] = client
            var forward = WireMessage(op: "browserCmd")
            forward.id = id
            forward.text = message.text
            forward.event = message.event
            guard clients.values.contains(where: { $0.subscribed }) else {
                browserWaiting[id] = nil
                var reply = WireMessage(op: "browserResult")
                reply.error = "Enterm penceresi açık değil."
                send(reply.frame(), to: client)
                return
            }
            broadcast(forward)
        case "browserReply":
            guard let id = message.id, let target = browserWaiting.removeValue(forKey: id), clients[target.fd] === target else { return }
            var reply = WireMessage(op: "browserResult")
            reply.text = message.text
            reply.error = message.error
            send(reply.frame(), to: target)
        case "reload":
            var note = WireMessage(op: "reload")
            note.text = message.text
            broadcast(note)
        case "input":
            guard let number = message.number, let session = sessions[number], let text = message.text else { return }
            let bytes = Array(text.utf8)
            _ = write(session.master, bytes, bytes.count)
        default:
            break
        }
    }

    // MARK: Sessions

    enum SpawnError: Error, CustomStringConvertible {
        case notFound(String)
        case failed(Int32)
        var description: String {
            switch self {
            case .notFound(let path): return "Klasör bulunamadı: \(path)"
            case .failed(let code): return "Süreç başlatılamadı (\(code))"
            }
        }
    }

    func create(_ spec: SessionSpec) throws -> Session {
        let home = hostEnvironment["HOME"] ?? NSHomeDirectory()
        var cwd = spec.cwd ?? home
        if cwd.hasPrefix("~") { cwd = home + cwd.dropFirst() }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SpawnError.notFound(cwd)
        }
        let id = UUID().uuidString.lowercased()
        var env = hostEnvironment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Enterm"
        env["TERM_PROGRAM_VERSION"] = EntermVersion.current
        env["ENTERM_SESSION_ID"] = id
        env["ENTERM_SOCKET"] = EntermPaths.socket.path
        env["ENTERM_HOME"] = EntermPaths.support.path
        env["ENTERM_CLI"] = CompanionPath.choose(own: cliPath, reported: reportedCLI)
        env["LANG"] = env["LANG"] ?? "tr_TR.UTF-8"
        env["LC_CTYPE"] = env["LC_CTYPE"] ?? "UTF-8"
        env["PWD"] = cwd
        // A session must not look like a child of another program's session.
        for key in env.keys where key == "CLAUDECODE" || key.hasPrefix("CLAUDE_CODE_") { env[key] = nil }
        for (key, value) in spec.env ?? [:] { env[key] = value }
        let shell = hostEnvironment["ENTERM_SHELL"] ?? loginShell()
        var path: String
        var argv: [String]
        if let custom = spec.argv, let first = custom.first {
            path = first
            argv = custom
        } else {
            let command = ShellIntegration.shellCommand(shell: shell, environment: env)
            path = command.path
            argv = command.argv
            env.merge(command.env) { _, new in new }
        }
        if path.isEmpty { path = shell }
        var master: Int32 = -1
        var pid: pid_t = -1
        let cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        let cEnv: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            cArgv.forEach { free($0) }
            cEnv.forEach { free($0) }
        }
        // zsh writes its end-of-line mark as wide as the terminal before the first prompt, before any hook runs.
        // The window's size arrives a moment after the start. If the terminal then is narrower, the mark wraps
        // and stays on screen. A shell starts narrower than any box, and the window's size or the asked one follows.
        let startColumns = spec.argv == nil ? min(spec.cols, Service.shellStartColumns) : spec.cols
        let status = cpty_spawn(path, cArgv, cEnv, cwd, UInt16(max(spec.rows, 2)), UInt16(max(startColumns, 2)), &master, &pid)
        guard status == 0 else { throw SpawnError.failed(errno) }
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
        let number = nextNumber
        nextNumber += 1
        var info = SessionInfo(id: id, number: number, name: spec.name ?? "", tool: spec.tool, cwd: cwd,
                               status: spec.tool == .terminal ? .running : .starting, startedAt: Date())
        info.pid = pid
        info.group = spec.group
        info.accountID = spec.accountID
        info.toolSessionID = spec.resumeID
        let session = Session(info: info, master: master)
        session.rows = spec.rows
        session.cols = spec.cols
        if startColumns != spec.cols {
            // Nobody may be looking yet, as for a queued start. The session still gets the size it asked for.
            queue.asyncAfter(deadline: .now() + 1) { [weak session] in
                guard let session, !session.wasResized else { return }
                _ = cpty_resize(session.master, UInt16(max(spec.rows, 2)), UInt16(max(spec.cols, 2)))
            }
        }
        sessions[number] = session
        let read = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        read.setEventHandler { [weak self, weak session] in
            guard let self, let session else { return }
            self.pump(session)
        }
        read.resume()
        session.readSource = read
        if spec.tool != .terminal {
            // A shell alias starts the program without the launch event: say so rather than stay on "starting".
            queue.asyncAfter(deadline: .now() + 30) { [weak self, weak session] in
                guard let self, let session, session.info.status == .starting else { return }
                session.info.status = .unknown
                self.publish(session)
            }
        }
        let process = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        process.setEventHandler { [weak self, weak session] in
            guard let self, let session else { return }
            self.finished(session, pid: pid)
        }
        process.resume()
        session.processSource = process
        cancelIdleCheck()
        return session
    }

    /// A program without hooks is read from its output: writing means working, a few quiet seconds mean waiting.
    func noteActivity(_ session: Session) {
        session.lastOutput = Date()
        if [.idle, .unknown, .starting].contains(session.info.status) {
            session.info.status = .running
            publish(session)
        }
        guard !session.quietCheck else { return }
        session.quietCheck = true
        scheduleQuietCheck(session, after: 3)
    }

    private func scheduleQuietCheck(_ session: Session, after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self, weak session] in
            guard let self, let session else { return }
            let quiet = Date().timeIntervalSince(session.lastOutput)
            if quiet < 3 {
                self.scheduleQuietCheck(session, after: 3 - quiet)
                return
            }
            session.quietCheck = false
            if session.info.status == .running {
                session.info.status = .idle
                self.publish(session)
            }
        }
    }

    func loginShell() -> String {
        if let chosen = JSONStore.load(AppSettings.self, from: EntermPaths.settingsFile)?.defaultShell, !chosen.isEmpty,
           FileManager.default.isExecutableFile(atPath: chosen) { return chosen }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let value = String(cString: shell)
            if !value.isEmpty { return value }
        }
        return hostEnvironment["SHELL"] ?? "/bin/zsh"
    }

    func pump(_ session: Session) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(session.master, &buffer, buffer.count)
        if count <= 0 {
            if count < 0 && (errno == EAGAIN || errno == EINTR) { return }
            session.readSource?.cancel()
            session.readSource = nil
            return
        }
        let bytes = Data(buffer[0..<count])
        session.ring.append(bytes)
        if session.ring.count > Service.ringLimit + Service.ringLimit / 4 {
            session.ring = Data(session.ring.suffix(Service.ringLimit))
        }
        session.dirty = true
        if !session.info.tool.reportsStatus, session.info.tool != .terminal { noteActivity(session) }
        persistSoon()
        let frame = WireFrame.session(.output, number: session.info.number, bytes: bytes)
        for client in clients.values where client.attached.contains(session.info.number) {
            send(frame, to: client)
        }
    }

    func finished(_ session: Session, pid: pid_t) {
        var status: Int32 = 0
        waitpid(pid, &status, WNOHANG)
        session.processSource?.cancel()
        session.processSource = nil
        // Reads whatever the program wrote before exiting.
        pump(session)
        session.readSource?.cancel()
        session.readSource = nil
        close(session.master)
        let exited = (status & 0x7f) == 0
        session.info.exitCode = exited ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        session.info.status = .exited
        session.info.pid = nil
        finishHeavy(session.info.id)
        releaseLocks(session.info.id)
        session.info.pendingApproval = nil
        for (id, approval) in approvals where approval.sessionID == session.info.id {
            finishApproval(id: id, decision: "none", remember: false)
        }
        publish(session)
        scheduleIdleCheck()
    }

    func remove(_ session: Session) {
        if let pid = session.info.pid { kill(pid, SIGHUP) }
        sessions[session.info.number] = nil
        try? FileManager.default.removeItem(at: EntermPaths.scrollbackDir.appendingPathComponent("\(session.info.id).log"))
        var message = WireMessage(op: "removed")
        message.number = session.info.number
        broadcast(message)
        persistSoon()
        scheduleIdleCheck()
    }

    // MARK: Events from hooks and the shell

    func sessionByID(_ id: String) -> Session? {
        sessions.values.first { $0.info.id == id }
    }

    func apply(_ event: AgentEvent) {
        guard let session = sessionByID(event.sessionID) else { return }
        var info = session.info
        info.lastEventAt = Date()
        if let value = event.toolSessionID { info.toolSessionID = value }
        if let value = event.transcriptPath { info.transcriptPath = value }
        if let value = event.model { info.model = value }
        if let value = event.effort { info.effort = value }
        if let value = event.limit { info.limit = value }
        if let value = event.inputTokens { info.inputTokens = value }
        if let value = event.outputTokens { info.outputTokens = value }
        if let value = event.contextTokens { info.contextTokens = value }
        if let value = event.contextPercent { info.contextPercent = value }
        if let value = event.costUSD { info.costUSD = value }
        if let value = event.text, event.kind == "activity" { info.lastActivity = value }
        if let toolName = event.tool, let tool = ToolKind(rawValue: toolName), tool != .terminal { info.tool = tool }
        switch event.kind {
        case "cnf":
            var note = WireMessage(op: "notFound")
            note.number = info.number
            note.text = event.text
            broadcast(note)
            // A box opened for this program must not keep saying it is starting.
            guard info.status == .starting, info.tool.command == event.text else { return }
            info.status = .notFound
        case "start":
            if info.status == .starting || info.status == .exited || info.status == .unknown { info.status = .idle }
            info.hooksTrusted = true
        case "launch":
            if let tool = ToolKind.fromCommand(event.text ?? "") { info.tool = tool }
            info.status = info.tool == .claude ? .starting : .unknown
        case "launchEnd":
            releaseLocks(info.id)
            info.tool = .terminal
            info.model = nil
            info.effort = nil
            info.status = .running
            info.pendingApproval = nil
            info.subagents = nil
        case "prompt", "working":
            info.status = .running
            if let text = event.text { info.lastActivity = String(text.prefix(300)) }
        case "stop":
            info.status = .idle
            info.pendingApproval = nil
            if let text = event.text, !text.isEmpty { info.lastActivity = String(text.prefix(300)) }
            releaseLocks(info.id)
            finishHeavy(info.id)
        case "wait":
            if info.status != .needsApproval { info.status = .idle }
        case "ask":
            info.status = .needsApproval
        case "limit":
            info.status = .limitReached
        case "error":
            info.status = .failed
        case "subStart":
            var list = info.subagents ?? []
            list.append(SubagentInfo(id: event.agentID ?? UUID().uuidString, type: event.agentType, running: true, startedAt: Date()))
            info.subagents = list
        case "subStop":
            if var list = info.subagents, let index = list.firstIndex(where: { $0.id == event.agentID }) {
                list[index].running = false
                info.subagents = list
            }
        default:
            break
        }
        if info != session.info {
            session.info = info
            publish(session)
        }
    }

    // MARK: Approvals

    func startApproval(_ event: AgentEvent, client: Client) {
        guard let session = sessionByID(event.sessionID) else {
            send(decisionReply(event: event.agentID, decision: "none"), to: client)
            return
        }
        let category = PermissionCategory(rawValue: event.errorKind ?? "") ?? .command
        let host = event.model
        // When the program decides, it asked because its own rules said so: the answer is the person's.
        let mode = permissions.card(for: session.info.id).passThrough ? .ask : permissions.decision(sessionID: session.info.id, category: category, host: host)
        switch mode {
        case .allow:
            send(decisionReply(event: event.agentID, decision: "allow"), to: client)
        case .deny:
            send(decisionReply(event: event.agentID, decision: "deny"), to: client)
        case .ask:
            // The same request can pass both the tool hook and the permission hook.
            let key = session.info.id + (event.text ?? "")
            if let when = recentAllowed[key], Date().timeIntervalSince(when) < 30 {
                send(decisionReply(event: event.agentID, decision: "allow"), to: client)
                return
            }
            let id = UUID().uuidString.lowercased()
            let request = ApprovalRequest(id: id, sessionID: session.info.id, tool: event.tool ?? "",
                                          summary: event.text ?? "", category: category, requestedAt: Date())
            approvals[id] = request
            approvalHosts[id] = host
            client.waitingApproval = id
            session.info.pendingApproval = request
            session.info.status = .needsApproval
            publish(session)
        }
    }

    var approvalHosts: [String: String] = [:]
    var fileLocks: [String: String] = [:]
    var browserWaiting: [String: Client] = [:]

    struct HeavyWaiter {
        let sessionID: String
        let name: String
        let command: String
        weak var client: Client?
        var running = false
    }
    var heavyQueue: [HeavyWaiter] = []

    /// One heavy command at a time. A waiting hook simply holds its answer until its turn.
    func advanceHeavy() {
        // A waiter whose hook gave up is no longer waiting.
        heavyQueue.removeAll { !$0.running && $0.client.map { clients[$0.fd] === $0 } != true }
        if !heavyQueue.contains(where: \.running), !heavyQueue.isEmpty {
            heavyQueue[0].running = true
            if let client = heavyQueue[0].client {
                var reply = WireMessage(op: "decision")
                reply.decision = "allow"
                send(reply.frame(), to: client)
            }
        }
        var note = WireMessage(op: "heavy")
        note.text = heavyJSON()
        broadcast(note)
    }

    func finishHeavy(_ sessionID: String) {
        guard heavyQueue.contains(where: { $0.sessionID == sessionID }) else { return }
        if let index = heavyQueue.firstIndex(where: { $0.sessionID == sessionID && $0.running }) {
            heavyQueue.remove(at: index)
        } else {
            heavyQueue.removeAll { $0.sessionID == sessionID }
        }
        advanceHeavy()
    }

    func heavyJSON() -> String {
        let entries = heavyQueue.map { HeavyEntry(sessionID: $0.sessionID, name: $0.name, command: $0.command, running: $0.running) }
        return (try? JSONEncoder().encode(entries)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }
    var recentAllowed: [String: Date] = [:]

    func releaseLocks(_ sessionID: String) {
        fileLocks = fileLocks.filter { $0.value != sessionID }
    }

    /// Output as plain text: escape sequences removed, last lines only.
    static func plainText(_ data: Data, lines: Int) -> String {
        let text = String(decoding: data, as: UTF8.self)
        let cleaned = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)|\u{1B}[@-Z\\\\-_]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "")
        return cleaned.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }

    func decisionReply(event: String?, decision: String) -> WireFrame {
        var reply = WireMessage(op: "decision")
        reply.decision = decision
        return reply.frame()
    }

    func finishApproval(id: String, decision: String, remember: Bool) {
        guard let request = approvals.removeValue(forKey: id) else { return }
        let host = approvalHosts.removeValue(forKey: id)
        if decision == "allow" { recentAllowed[request.sessionID + request.summary] = Date() }
        if remember, decision == "allow", let host {
            if !permissions.rememberedHosts.contains(host) { permissions.rememberedHosts.append(host) }
            permissions.save()
        }
        for client in clients.values where client.waitingApproval == id {
            client.waitingApproval = nil
            send(decisionReply(event: nil, decision: decision), to: client)
        }
        if let session = sessionByID(request.sessionID), session.info.pendingApproval?.id == id {
            session.info.pendingApproval = nil
            if session.info.status == .needsApproval { session.info.status = .running }
            publish(session)
        }
    }

    // MARK: Persistence

    /// Writes the session list and output tails at most once every 15 seconds, and only when something changed.
    func persistSoon() {
        guard flushTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15)
        timer.setEventHandler { [weak self] in
            self?.flushTimer?.cancel()
            self?.flushTimer = nil
            self?.persistNow()
        }
        timer.resume()
        flushTimer = timer
    }

    func persistNow() {
        let infos = sessions.values.map(\.info).sorted { $0.number < $1.number }
        JSONStore.save(infos, to: EntermPaths.sessionsFile)
        // The transcript setting is read here, at most once per flush.
        let keep = JSONStore.load(AppSettings.self, from: EntermPaths.settingsFile)?.keepTranscript ?? true
        guard keep else { return }
        let tailLimit = 256 * 1024
        for session in sessions.values where session.dirty {
            session.dirty = false
            let url = EntermPaths.scrollbackDir.appendingPathComponent("\(session.info.id).log")
            try? Data(session.ring.suffix(tailLimit)).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    // MARK: Lifetime

    func cancelIdleCheck() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    func scheduleIdleCheck() {
        guard clients.isEmpty, sessions.values.allSatisfy({ $0.info.status == .exited }) else { return }
        cancelIdleCheck()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.clients.isEmpty, self.sessions.values.allSatisfy({ $0.info.status == .exited }) else { return }
            self.persistNow()
            unlink(EntermPaths.socket.path)
            exit(0)
        }
        timer.resume()
        idleTimer = timer
    }
}

let service = Service()
service.queue.async { service.start() }
dispatchMain()
