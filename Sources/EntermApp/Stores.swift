import AppKit
import Combine
import EntermCore
import UserNotifications

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    @Published var settings: AppSettings {
        didSet { JSONStore.save(settings, to: EntermPaths.settingsFile) }
    }
    init() {
        settings = JSONStore.load(AppSettings.self, from: EntermPaths.settingsFile) ?? AppSettings()
    }
}

final class LinkStore: ObservableObject {
    static let shared = LinkStore()
    @Published var book = LinkBook.load()
    var links: [SessionLink] { book.links }

    func add(_ link: SessionLink) {
        book.links.append(link)
        book.save()
        AppModel.shared.onLayoutChange?()
    }
    func remove(_ id: String) {
        book.links.removeAll { $0.id == id }
        book.save()
        AppModel.shared.onLayoutChange?()
    }
    func update(_ link: SessionLink) {
        if let index = book.links.firstIndex(where: { $0.id == link.id }) { book.links[index] = link }
        book.save()
        AppModel.shared.onLayoutChange?()
    }
}

final class AccountStore: ObservableObject {
    static let shared = AccountStore()
    @Published var accounts: [Account] = []

    init() {
        accounts = JSONStore.load([Account].self, from: EntermPaths.accountsFile) ?? [
            Account(id: "system-claude", tool: .claude, name: "Bu Bilgisayar", kind: .system),
            Account(id: "system-codex", tool: .codex, name: "Bu Bilgisayar", kind: .system),
            Account(id: "system-antigravity", tool: .antigravity, name: "Bu Bilgisayar", kind: .system),
        ]
    }
    func account(id: String) -> Account? { accounts.first { $0.id == id } }

    /// Codex limits are asked for when they are looked at, never on a timer.
    func refreshCodex() {
        for account in accounts where account.tool == .codex && account.kind != .apiKey {
            CodexLimits.read(account: account) { [weak self] snapshot in
                guard let self, let snapshot else { return }
                self.recordLimit(snapshot, accountID: account.id, tool: .codex)
            }
        }
    }
    func save() { JSONStore.save(accounts, to: EntermPaths.accountsFile) }

    func recordLimit(_ limit: LimitSnapshot, accountID: String?, tool: ToolKind) {
        let id = accountID ?? "system-\(tool.rawValue)"
        guard let index = accounts.firstIndex(where: { $0.id == id }), accounts[index].lastLimit != limit else { return }
        accounts[index].lastLimit = limit
        save()
    }

    func add(tool: ToolKind, name: String) -> Account {
        let id = UUID().uuidString.lowercased()
        let dir = EntermPaths.accountsDir.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let account = Account(id: id, tool: tool, name: name, kind: .subscription, configDir: dir.path)
        accounts.append(account)
        save()
        return account
    }

    /// Adds the account and opens a terminal where the official program shows its own sign-in.
    @discardableResult
    func beginLogin(tool: ToolKind, name: String) -> Account {
        let account = add(tool: tool, name: name.isEmpty ? tool.title : name)
        var spec = SessionSpec(name: "giriş: \(account.name)", tool: .terminal, rows: 30, cols: 100, accountID: account.id)
        var env = environment(for: account.id)
        env["ENTERM_STARTUP"] = tool == .codex ? "codex login" : "claude"
        spec.env = env
        AppModel.shared.create(spec)
        return account
    }

    func addKey(tool: ToolKind, name: String, cap: Double?) -> Account {
        let id = UUID().uuidString.lowercased()
        var account = Account(id: id, tool: tool, name: name, kind: .apiKey)
        account.monthlyCap = cap
        accounts.append(account)
        save()
        return account
    }

    func remove(_ id: String) {
        accounts.removeAll { $0.id == id }
        Keychain.delete(account: id)
        save()
    }

    /// Environment for a session that uses this account. Tokens never pass through Enterm:
    /// a subscription is only a directory the official program manages itself.
    func environment(for accountID: String?) -> [String: String] {
        guard let accountID, let account = account(id: accountID) else { return [:] }
        switch account.kind {
        case .system:
            return [:]
        case .subscription:
            guard let dir = account.configDir else { return [:] }
            return account.tool == .codex ? ["CODEX_HOME": dir] : ["CLAUDE_CONFIG_DIR": dir]
        case .apiKey:
            guard let key = Keychain.read(account: account.id) else { return [:] }
            return account.tool == .codex ? ["OPENAI_API_KEY": key] : ["ANTHROPIC_API_KEY": key]
        }
    }
}

enum Keychain {
    static let service = "tr.com.enmera.enterm.apikey"

    static func save(_ value: String, account: String) -> Bool {
        delete(account: account)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecValueData as String: Data(value.utf8)]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    static func read(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

/// The power limit: queue instead of slowing. Samples only while agents are running.
final class PowerCenter: ObservableObject {
    static let shared = PowerCenter()
    private static let file = EntermPaths.support.appendingPathComponent("power.json")
    @Published var settings: PowerSettings {
        didSet {
            JSONStore.save(settings, to: Self.file)
            AppModel.shared.flushPending()
            AppModel.shared.onLayoutChange?()
        }
    }
    @Published var cpuUsed: Double = 0
    @Published var pressure = MemoryPressureLevel.current()
    @Published var queue: [QueuedSession] = []
    @Published var enterm: (cpu: Double, memoryMB: Double) = (0, 0)
    @Published var agents: (cpu: Double, memoryMB: Double) = (0, 0)
    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var lastTicks: (user: UInt64, system: UInt64, idle: UInt64)?

    struct QueuedSession: Identifiable {
        let id = UUID()
        let spec: SessionSpec
        let reason: String
        let then: ((SessionInfo) -> Void)?
    }

    init() {
        settings = JSONStore.load(PowerSettings.self, from: Self.file) ?? PowerSettings()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical, .normal], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pressure = MemoryPressureLevel.current()
            self.startQueued()
        }
        source.resume()
        pressureSource = source
    }

    var effectiveMaxSessions: Int {
        settings.sessionsAutomatic ? max(2, Int(ProcessInfo.processInfo.physicalMemory / (1 << 30)) / 2) : settings.maxSessions
    }

    var runningAgents: Int {
        AppModel.shared.sessions.filter { $0.tool != .terminal && $0.status != .exited }.count
    }

    /// True when a new agent must wait. Plain terminals are never queued.
    func blockReason() -> String? {
        pressure = MemoryPressureLevel.current()
        return PowerRules.blockReason(running: runningAgents, maxSessions: effectiveMaxSessions, cpuLimit: settings.cpuLimit, cpuUsed: cpuUsed, pressure: pressure)
    }

    func enqueue(_ spec: SessionSpec, reason: String, then: ((SessionInfo) -> Void)? = nil) {
        queue.append(QueuedSession(spec: spec, reason: reason, then: then))
        updateSampling()
        PhoneBridge.tellPhones()
    }

    func startQueued(force: QueuedSession? = nil) {
        if let force {
            queue.removeAll { $0.id == force.id }
            AppModel.shared.create(force.spec, then: force.then)
            PhoneBridge.tellPhones()
            return
        }
        while let first = queue.first, blockReason() == nil {
            queue.removeFirst()
            AppModel.shared.create(first.spec, then: first.then)
            PhoneBridge.tellPhones()
        }
    }

    /// Idle means idle: no timer runs unless an agent or a queued session exists.
    func updateSampling() {
        let needed = runningAgents > 0 || !queue.isEmpty
        if needed, timer == nil {
            sample()
            let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sample() }
            timer.tolerance = 1.5
            self.timer = timer
        } else if !needed, let timer {
            timer.invalidate()
            self.timer = nil
            lastTicks = nil
        }
    }

    func sample() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let user = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.3)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        if let last = lastTicks {
            let busy = Double(user - last.user + system - last.system)
            let total = busy + Double(idle - last.idle)
            if total > 0 { cpuUsed = busy / total * 100 }
        }
        lastTicks = (user, system, idle)
        pressure = MemoryPressureLevel.current()
        applyPriorities()
        startQueued()
    }

    /// Near the limit, background agents get a lower priority. The focused session keeps its own.
    private func applyPriorities() {
        let tight = settings.cpuLimit < 100 && cpuUsed >= Double(settings.cpuLimit) * 0.9
        for info in AppModel.shared.sessions where info.tool != .terminal {
            var message = WireMessage(op: "setPriority")
            message.number = info.number
            message.limit = tight && info.number != AppModel.shared.focused ? 10 : 0
            AppModel.shared.connection.send(message)
        }
    }

    /// Reads the app's and agents' load for the settings screen, only when that screen asks.
    func measureUsage() {
        pressure = MemoryPressureLevel.current()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,%cpu=,rss=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            var own = (cpu: 0.0, memoryMB: 0.0)
            var agent = (cpu: 0.0, memoryMB: 0.0)
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                guard parts.count == 4, let cpu = Double(parts[1]), let rss = Double(parts[2]) else { continue }
                let name = URL(fileURLWithPath: String(parts[3])).lastPathComponent
                if name == "EntermApp" || name == "entermd" {
                    own.cpu += cpu
                    own.memoryMB += rss / 1024
                } else if ["claude", "codex", "agy", "node"].contains(name) {
                    agent.cpu += cpu
                    agent.memoryMB += rss / 1024
                }
            }
            DispatchQueue.main.async {
                self?.enterm = own
                self?.agents = agent
            }
        }
    }
}

/// Reacts to session changes outside the view layer.
final class ExtensionsHub {
    static let shared = ExtensionsHub()
    private var awake: NSObjectProtocol?

    func sessionsChanged() {
        Scheduler.shared.scan(folders: AppModel.shared.sessions.map(\.cwd))
        PowerCenter.shared.updateSampling()
        PowerCenter.shared.startQueued()
        updateAwake()
    }

    func sessionUpdated(previous: SessionInfo, current: SessionInfo) {
        if let limit = current.limit { AccountStore.shared.recordLimit(limit, accountID: current.accountID, tool: current.tool) }
        if previous.tool != .terminal, current.tool == .terminal, LimitWatch.shared.resumeFailed(current.number) {
            AppModel.shared.overlay = .resumeFailed(current.number)
            LimitWatch.shared.failedResumes.insert(current.number)
            PhoneBridge.tellPhones(saying: "■ Konuşma bu hesapta açılmadı. İş kaybolmadı.")
        }
        if previous.status != current.status {
            Inbox.shared.statusChanged(previous: previous, current: current)
            updateAwake()
            PowerCenter.shared.updateSampling()
        }
        if current.pendingApproval != nil, previous.pendingApproval == nil, let id = current.pendingApproval?.id {
            let model = AppModel.shared
            if model.overlay == nil { model.overlay = .approval(id) }
            Notifier.shared.post(title: "\(model.title(for: current)) İzin İstiyor", body: current.pendingApproval?.summary ?? "", onlyWhenInactive: true)
        }
    }

    /// While an agent works the Mac does not idle sleep; the hold ends when it finishes.
    private func updateAwake() {
        let working = AppModel.shared.sessions.contains { $0.tool != .terminal && $0.status == .running }
        let wanted = working && SettingsStore.shared.settings.keepAwakeWhileAgents
        if wanted, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Enterm ajanı çalışıyor")
        } else if !wanted, let token = awake {
            ProcessInfo.processInfo.endActivity(token)
            awake = nil
        }
    }

    var isHoldingAwake: Bool { awake != nil }
}

struct InboxItem: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
    let at: Date
    let sessionNumber: UInt32?
}

final class Inbox: ObservableObject {
    static let shared = Inbox()
    @Published var finished: [InboxItem] = []
    @Published var limits: [InboxItem] = []

    func statusChanged(previous: SessionInfo, current: SessionInfo) {
        let name = AppModel.shared.title(for: current)
        switch current.status {
        case .idle where previous.status == .running:
            Notifier.shared.post(title: "\(name): İş Bitti", body: current.lastActivity ?? "", onlyWhenInactive: true)
            finished.insert(InboxItem(symbol: "✓", title: name, detail: current.lastActivity ?? "İş Bitti", at: Date(), sessionNumber: current.number), at: 0)
        case .failed:
            finished.insert(InboxItem(symbol: "✕", title: name, detail: "Hata", at: Date(), sessionNumber: current.number), at: 0)
        case .limitReached:
            limits.removeAll { $0.sessionNumber == current.number }
            limits.insert(InboxItem(symbol: "■", title: name, detail: "Limit Doldu, İş Korundu", at: Date(), sessionNumber: current.number), at: 0)
            AppModel.shared.overlay = .limit(current.number)
            Notifier.shared.post(title: "\(name): Limit Doldu", body: "İş Korundu, Seçenekler Enterm'de", onlyWhenInactive: true)
        default:
            if previous.status == .limitReached { limits.removeAll { $0.sessionNumber == current.number } }
        }
        if finished.count > 50 { finished.removeLast(finished.count - 50) }
    }
}

/// The card shown inside the terminal when a program is not found.
struct NotFoundCard: Equatable {
    enum Kind: Equatable {
        case notInstalled(install: String)
        case notInPath(path: String)
        case inApp(path: String)
        case geminiRejected
    }
    let number: UInt32
    let command: String
    let kind: Kind

    var title: String {
        let tool = ToolKind.fromCommand(command)?.title ?? command
        switch kind {
        case .notInstalled: return "\(tool) Bu Bilgisayarda Kurulu Değil"
        case .notInPath: return "\(tool) Kurulu, Ama PATH'te Yok"
        case .inApp: return "\(tool), ChatGPT Uygulamasının İçinde Bulundu"
        case .geminiRejected: return "Kişisel Google Hesabında agy Çalışır"
        }
    }

    static func make(number: UInt32, command: String) -> NotFoundCard? {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        switch command {
        case "gemini":
            return NotFoundCard(number: number, command: command, kind: .geminiRejected)
        case "claude":
            let local = home + "/.local/bin/claude"
            if fm.isExecutableFile(atPath: local) { return NotFoundCard(number: number, command: command, kind: .notInPath(path: local)) }
            return NotFoundCard(number: number, command: command, kind: .notInstalled(install: ToolPresence.installCommand(.claude) ?? ""))
        case "codex":
            let local = home + "/.local/bin/codex"
            if fm.isExecutableFile(atPath: local) { return NotFoundCard(number: number, command: command, kind: .notInPath(path: local)) }
            let app = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
            if fm.isExecutableFile(atPath: app) { return NotFoundCard(number: number, command: command, kind: .inApp(path: app)) }
            return NotFoundCard(number: number, command: command, kind: .notInstalled(install: ToolPresence.installCommand(.codex) ?? ""))
        case "agy":
            let local = home + "/.local/bin/agy"
            if fm.isExecutableFile(atPath: local) { return NotFoundCard(number: number, command: command, kind: .notInPath(path: local)) }
            return NotFoundCard(number: number, command: command, kind: .notInstalled(install: ToolPresence.installCommand(.antigravity) ?? ""))
        default:
            return nil
        }
    }
}

/// System notifications: only for events, by default only when the window is in the background.
/// A permission is asked the first time there is something to say.
final class Notifier {
    static let shared = Notifier()
    private var asked = false

    func post(title: String, body: String, onlyWhenInactive: Bool) {
        guard SettingsStore.shared.settings.systemNotifications else { return }
        if onlyWhenInactive, NSApp.isActive { return }
        let center = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = String(body.prefix(160))
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if asked {
            send()
        } else {
            asked = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted { send() }
            }
        }
    }
}
