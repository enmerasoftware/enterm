import CPTY
import EntermCore
import Foundation
import IOKit.pwr_mgt

/// Paired phones. Each one reaches the service as an ordinary client through a socket pair,
/// so it sees what the window sees. Nothing runs here until a phone has been paired.
final class PhoneCenter {
    /// What a phone may ask. Local-only operations such as shutdown or hook events stay out.
    static let allowedOperations: Set<String> = ["hello", "create", "attach", "detach", "resize", "kill", "remove", "rename", "decide", "list", "tail", "stop", "setPriority", "chat"]

    private unowned let service: Service
    private var devices: [PairedPeer]
    private var links: [String: DeviceLink] = [:]
    private var pairing: PairingAgent?
    private var pairingExpiry: DispatchWorkItem?
    private var notifiedStatus: [UInt32: SessionStatus] = [:]
    private var powerPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private var powerRoot: io_connect_t = 0

    // IOMessage.h values, which do not reach Swift as constants.
    fileprivate static let systemWillSleep: UInt32 = 0xE000_0280
    fileprivate static let canSystemSleep: UInt32 = 0xE000_0270

    static var file: URL { EntermPaths.support.appendingPathComponent("devices.json") }

    init(service: Service) {
        self.service = service
        devices = JSONStore.load([PairedPeer].self, from: Self.file) ?? []
    }

    func start() {
        devices.forEach(open)
        watchSleepIfNeeded()
    }

    private func save() {
        JSONStore.save(devices, to: Self.file)
        chmod(Self.file.path, 0o600)
    }

    private func open(_ device: PairedPeer) {
        let link = DeviceLink(peer: device, service: service) { [weak self] id in
            guard let self, let index = self.devices.firstIndex(where: { $0.id == id }) else { return }
            self.devices[index].lastSeen = Date()
            self.save()
            self.announceDevices()
        } onToken: { [weak self] id, token in
            guard let self, let index = self.devices.firstIndex(where: { $0.id == id }) else { return }
            self.devices[index].pushToken = token
            self.save()
        }
        links[device.id] = link
        link.start()
    }

    // MARK: Requests from the window

    func handle(_ message: WireMessage, from client: Client) -> Bool {
        switch message.op {
        case "pairStart":
            guard let relay = message.text?.trimmingCharacters(in: .whitespacesAndNewlines), !relay.isEmpty else { return true }
            pairing?.cancel()
            let agent = PairingAgent(relay: relay, name: Host.current().localizedName ?? "Mac", queue: service.queue)
            agent.onStage = { [weak self, weak agent] stage in
                guard let self, let agent else { return }
                self.pairingChanged(stage, agent)
            }
            pairing = agent
            agent.start()
            pairingExpiry?.cancel()
            let expiry = DispatchWorkItem { [weak self, weak agent] in
                guard let self, let agent, self.pairing === agent else { return }
                agent.cancel()
                self.pairing = nil
                self.announcePairing("expired", detail: nil)
            }
            pairingExpiry = expiry
            service.queue.asyncAfter(deadline: .now() + 300, execute: expiry)
            var reply = WireMessage(op: "pairOffer")
            reply.id = message.id
            reply.text = agent.offer.url
            service.send(reply.frame(), to: client)
        case "pairConfirm":
            pairing?.confirm()
        case "pairCancel":
            pairing?.cancel()
            pairing = nil
            pairingExpiry?.cancel()
        case "devices":
            var reply = WireMessage(op: "devices")
            reply.id = message.id
            reply.text = devicesJSON()
            service.send(reply.frame(), to: client)
#if ENTERM_TEST_DRIVER
        case "testSleep":
            tellSleeping()
#endif
        case "appReply":
            finishCall(message)
        case "phoneAttention":
            let frame = message.frame()
            for phone in service.clients.values where phone.isPhone { service.send(frame, to: phone) }
            if let text = message.text { scriptSaid(text) }
        case "deviceRemove":
            guard let id = message.text else { return true }
            links[id]?.tell(WireMessage(op: "unpaired"))
            let link = links.removeValue(forKey: id)
            // The farewell needs a moment on the wire before the link goes.
            service.queue.asyncAfter(deadline: .now() + 0.5) { link?.stop() }
            devices.removeAll { $0.id == id }
            save()
            announceDevices()
        default:
            return false
        }
        return true
    }

    private func pairingChanged(_ stage: PairingAgent.Stage, _ agent: PairingAgent) {
        guard pairing === agent else { return }
        switch stage {
        case .waiting: break
        case .compare(let number): announcePairing("compare", detail: number)
        case .confirmed: announcePairing("confirmed", detail: nil)
        case .finished(let name):
            pairingExpiry?.cancel()
            pairing = nil
            if let peer = agent.result {
                devices.removeAll { $0.id == peer.id }
                devices.append(peer)
                save()
                open(peer)
                watchSleepIfNeeded()
            }
            announcePairing("finished", detail: name)
            announceDevices()
        case .failed:
            pairingExpiry?.cancel()
            pairing = nil
            announcePairing("failed", detail: nil)
        }
    }

    private func announcePairing(_ state: String, detail: String?) {
        var message = WireMessage(op: "pairState")
        message.text = state
        message.error = detail
        service.broadcast(message)
    }

    private func announceDevices() {
        var message = WireMessage(op: "devices")
        message.text = devicesJSON()
        service.broadcast(message)
    }

    private func devicesJSON() -> String {
        let list = devices.map { DeviceSummary(id: $0.id, name: $0.name, pairedAt: $0.pairedAt, lastSeen: $0.lastSeen, connected: links[$0.id]?.isConnected ?? false) }
        guard let data = try? JSONEncoder().encode(list) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Notifications

    /// Only what asks for a decision or stops work. The relay gets a sealed box and a device token.
    func sessionChanged(_ info: SessionInfo) {
        guard !devices.isEmpty else { return }
        let previous = notifiedStatus[info.number]
        notifiedStatus[info.number] = info.status
        guard previous != info.status else { return }
        let name = info.name.isEmpty ? URL(fileURLWithPath: info.cwd).lastPathComponent : info.name
        let notice: PhoneNotice
        switch info.status {
        case .needsApproval:
            notice = PhoneNotice(kind: "approval", title: "◆ \(name)", body: info.pendingApproval?.summary ?? "Onay İstiyor", number: info.number, approvalID: info.pendingApproval?.id)
        case .limitReached:
            notice = PhoneNotice(kind: "event", title: "■ \(name)", body: "Limit Doldu", number: info.number)
        case .failed:
            notice = PhoneNotice(kind: "event", title: "✕ \(name)", body: "Hata", number: info.number)
        default:
            return
        }
        send(notice)
    }

    // MARK: Calls to the window

    private var waitingCalls: [String: (client: Client, id: String?)] = [:]
    private var launchedWindowAt: Date?

    /// Accounts, links and Git live in the window. When it is closed, it is opened behind whatever is in front.
    func forward(_ message: WireMessage, from client: Client, attempt: Int = 0) {
        guard let window = service.clients.values.first(where: { $0.subscribed && !$0.isPhone }) else {
            guard attempt < 16 else {
                var reply = WireMessage(op: "appReply")
                reply.id = message.id
                reply.error = "Enterm Bilgisayarda Açılamadı"
                service.send(reply.frame(), to: client)
                return
            }
            openWindow()
            service.queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.forward(message, from: client, attempt: attempt + 1) }
            return
        }
        let key = UUID().uuidString
        waitingCalls[key] = (client, message.id)
        var command = WireMessage(op: "appCallCmd")
        command.id = key
        command.text = message.text
        service.send(command.frame(), to: window)
    }

    func finishCall(_ message: WireMessage) {
        guard let key = message.id, let waiting = waitingCalls.removeValue(forKey: key), service.clients[waiting.client.fd] === waiting.client else { return }
        var reply = WireMessage(op: "appReply")
        reply.id = waiting.id
        reply.text = message.text
        reply.error = message.error
        service.send(reply.frame(), to: waiting.client)
    }

    private func openWindow() {
        if let last = launchedWindowAt, Date().timeIntervalSince(last) < 10 { return }
        launchedWindowAt = Date()
        guard let executable = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("EntermApp") else { return }
        let process = Process()
        process.executableURL = executable
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// `enterm notify` reaches paired phones too.
    func scriptSaid(_ text: String) {
        send(PhoneNotice(kind: "event", title: "Enterm", body: text))
    }

    private func send(_ notice: PhoneNotice) {
        guard let plain = try? JSONEncoder().encode(notice) else { return }
        for device in devices {
            guard let token = device.pushToken, let sealed = TunnelCrypto.sealNotification(plain, pairKey: device.key) else { continue }
            links[device.id]?.push(token: token, sealed: sealed, kind: notice.kind)
        }
    }

    // MARK: Sleep

    /// A phone can then tell a Mac that sleeps from a Mac that cannot be reached.
    private func watchSleepIfNeeded() {
        guard !devices.isEmpty, powerPort == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerRoot = IORegisterForSystemPower(context, &powerPort, { context, _, type, argument in
            guard let context else { return }
            let center = Unmanaged<PhoneCenter>.fromOpaque(context).takeUnretainedValue()
            switch type {
            case PhoneCenter.systemWillSleep:
                center.tellSleeping()
                IOAllowPowerChange(center.powerRoot, Int(bitPattern: argument))
            case PhoneCenter.canSystemSleep:
                IOAllowPowerChange(center.powerRoot, Int(bitPattern: argument))
            default:
                break
            }
        }, &powerNotifier)
        if let powerPort { IONotificationPortSetDispatchQueue(powerPort, service.queue) }
    }

    func tellSleeping() {
        var message = WireMessage(op: "macSleeping")
        message.text = ISO8601DateFormatter().string(from: Date())
        links.values.forEach { $0.tell(message) }
    }
}

/// One phone's link and its place among the service's clients.
final class DeviceLink {
    private let link: TunnelLink
    private unowned let service: Service
    private let id: String
    private let onSeen: (String) -> Void
    private let onToken: (String, String) -> Void
    private var client: Client?
    private var bridge: Int32 = -1
    private var bridgeSource: DispatchSourceRead?
    private var decoder = WireDecoder()
    private(set) var isConnected = false

    init(peer: PairedPeer, service: Service, onSeen: @escaping (String) -> Void, onToken: @escaping (String, String) -> Void) {
        id = peer.id
        self.service = service
        self.onSeen = onSeen
        self.onToken = onToken
        link = TunnelLink(peer: peer, role: .mac, queue: service.queue)
        link.onState = { [weak self] state in self?.stateChanged(state) }
        link.onData = { [weak self] data in self?.received(data) }
    }

    func start() { link.start() }

    func stop() {
        link.stop()
        closeBridge()
    }

    func tell(_ message: WireMessage) {
        link.send(message.frame().encoded())
    }

    func push(token: String, sealed: String, kind: String) {
        link.requestPush(token: token, sealed: sealed, kind: kind)
    }

    private func stateChanged(_ state: TunnelLink.State) {
        if state == .ready {
            isConnected = true
            openBridge()
            onSeen(id)
        } else if isConnected {
            isConnected = false
            closeBridge()
            onSeen(id)
        }
    }

    private func openBridge() {
        closeBridge()
        var fds: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { return }
        bridge = fds[1]
        _ = fcntl(bridge, F_SETFL, fcntl(bridge, F_GETFL) | O_NONBLOCK)
        client = service.adopt(fds[0])
        client?.isPhone = true
        let source = DispatchSource.makeReadSource(fileDescriptor: bridge, queue: service.queue)
        source.setEventHandler { [weak self] in self?.pump() }
        source.resume()
        bridgeSource = source
    }

    private func closeBridge() {
        bridgeSource?.cancel()
        bridgeSource = nil
        if bridge >= 0 {
            close(bridge)
            bridge = -1
        }
        client = nil
        decoder = WireDecoder()
    }

    /// Service to phone: bytes as they are, sealed by the link.
    private func pump() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(bridge, &buffer, buffer.count)
        if count > 0 {
            link.send(Data(buffer[0..<count]))
        } else if count == 0 {
            closeBridge()
        }
    }

    /// Phone to service: each frame is checked, because this side of the socket is not local.
    private func received(_ data: Data) {
        guard let client else { return }
        for frame in decoder.feed(data) {
            switch frame.kind {
            case .input:
                service.handle(frame, from: client)
            case .json:
                guard let message = WireMessage.decode(frame.payload) else { continue }
                if message.op == "pushToken", let token = message.text {
                    onToken(id, token)
                } else if message.op == "appCall" {
                    service.phones.forward(message, from: client)
                } else if PhoneCenter.allowedOperations.contains(message.op) {
                    service.handleMessage(message, from: client)
                }
            default:
                break
            }
        }
    }
}
