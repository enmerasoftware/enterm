import AppKit
import Combine
import EntermCore

enum ViewMode: String, Codable {
    case single, canvas, tabs
}

enum Page: Equatable {
    case settings(SettingsTab)
    case accounts
    case accountAdd
    case apiKey
    case inbox
    case board
    case history
    case team
    case manager
    case phone
    case remote
    case newView
    case sessionList
    case changes
    case browser
    case files
    case editor(String)
    case note
    case messages
    case cost
    case restore
    case scheduler
    case notYet(String)
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance, shortcuts, security, power, voice, sleep
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appearance: return "Görünüm"
        case .shortcuts: return "Kısayollar"
        case .security: return "Güvenlik"
        case .power: return "Güç Sınırı"
        case .voice: return "Ses"
        case .sleep: return "Uyku"
        }
    }
}

enum Overlay: Equatable {
    case palette
    case newSession
    case menu
    case newSessionOptions
    case linkPermission(from: UInt32, to: UInt32)
    case linkDetail(String)
    case approval(String)
    case limit(UInt32)
    case limitOpened
    case resumeFailed(UInt32)
    case codexLimit(UInt32)
}

/// What the app remembers between launches. Everything else lives in the session service.
struct WindowState: Codable {
    var mode: ViewMode = .single
    var positions: [String: CGPoint] = [:]
    var freeLayout = false
}

/// The whole app state. Views observe it; nothing polls.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let connection = ServiceConnection()
    @Published var sessions: [SessionInfo] = []
    @Published var focused: UInt32?
    @Published var mode: ViewMode = .single
    @Published var maximized: UInt32?
    @Published var page: Page?
    @Published var overlay: Overlay?
    @Published var detailsOpen = false
    @Published var detailTab = 0
    @Published var zoom: CGFloat = 1
    @Published var notFound: NotFoundCard?
    @Published var serviceLost = false
    @Published var hint: String? {
        didSet {
            hintTimer?.invalidate()
            hintTimer = nil
            guard hint != nil, hint?.hasPrefix("●") != true else { return }
            hintTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in self?.hint = nil }
        }
    }
    @Published var titles: [UInt32: String] = [:]

    var hosts: [UInt32: TerminalHost] = [:]
    var state = JSONStore.load(WindowState.self, from: EntermPaths.stateFile) ?? WindowState()
    var onLayoutChange: (() -> Void)?
    var onFocusChange: (() -> Void)?
    var pendingFeed: [UInt32: Data] = [:]
    var windowVisible = true
    var sparseTimer: Timer?
    var fitCanvas: (() -> Void)?
    var onReload: (() -> Void)?
    var restorable: [SessionInfo] = []
    var codexWarned = Set<UInt32>()
    private var hintTimer: Timer?

    var visibleSessions: [SessionInfo] { sessions }
    var focusedInfo: SessionInfo? { sessions.first { $0.number == focused } }
    var hasAgents: Bool { sessions.contains { $0.tool != .terminal } }
    var focusedHost: TerminalHost? { focused.flatMap { hosts[$0] } }

    // MARK: Start

    func start() {
        EntermPaths.ensureDirectories()
        connection.onOutput = { [weak self] number, data, replay in self?.output(number, data, replay) }
        connection.onMessage = { [weak self] message in self?.handle(message) }
        connection.onDisconnect = { [weak self] in self?.lostService() }
        connection.connect { [weak self] ok in
            guard let self else { return }
            if ok {
                self.connection.send(WireMessage(op: "hello"))
            } else {
                self.serviceLost = true
            }
        }
    }

    private func lostService() {
        serviceLost = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connection.connect { ok in
                guard let self, ok else {
                    self?.lostService()
                    return
                }
                self.serviceLost = false
                self.hosts.values.forEach { $0.removeFromSuperview() }
                self.hosts.removeAll()
                self.connection.send(WireMessage(op: "hello"))
            }
        }
    }

    func handle(_ message: WireMessage) {
        switch message.op {
        case "state":
            let list = (message.sessions ?? []).filter { $0.status != .exited }
            sessions = list
            list.forEach { ensureHost($0) }
            if list.isEmpty {
                let saved = JSONStore.load([SessionInfo].self, from: EntermPaths.sessionsFile)?.filter { $0.status != .exited } ?? []
                if saved.isEmpty {
                    newTerminal()
                } else {
                    restorable = saved
                    newTerminal()
                    page = .restore
                }
            } else {
                hint = "Enterm Yeniden Açıldı · Oturumlar Hiç Durmadı"
                mode = list.count > 1 ? (state.mode == .single ? .canvas : state.mode) : .single
                setFocus(list.first?.number)
                onLayoutChange?()
            }
            ExtensionsHub.shared.sessionsChanged()
        case "session":
            guard let info = message.session else { return }
            update(info)
        case "removed":
            if let number = message.number { forget(number) }
        case "notFound":
            guard let number = message.number, let name = message.text else { return }
            notFound = NotFoundCard.make(number: number, command: name)
        case "notice":
            hint = message.text
        case "reload":
            if let text = message.text { hint = text }
            BoardStore.shared.reload()
            TeamStore.shared.reload()
            onReload?()
        default:
            break
        }
    }

    func update(_ info: SessionInfo) {
        if info.status == .exited {
            closeLocally(info.number)
            var removal = WireMessage(op: "remove")
            removal.number = info.number
            connection.send(removal)
            return
        }
        if let index = sessions.firstIndex(where: { $0.number == info.number }) {
            let previous = sessions[index]
            sessions[index] = info
            if previous != info {
                ExtensionsHub.shared.sessionUpdated(previous: previous, current: info)
                onLayoutChange?()
            }
        } else {
            sessions.append(info)
            ensureHost(info)
            onLayoutChange?()
        }
    }

    private func forget(_ number: UInt32) {
        closeLocally(number)
    }

    private func closeLocally(_ number: UInt32) {
        guard let index = sessions.firstIndex(where: { $0.number == number }) else { return }
        sessions.remove(at: index)
        hosts[number]?.removeFromSuperview()
        hosts[number] = nil
        titles[number] = nil
        pendingFeed[number] = nil
        if maximized == number { maximized = nil }
        if notFound?.number == number { notFound = nil }
        if sessions.isEmpty {
            NSApp.terminate(nil)
            return
        }
        if sessions.count == 1 { mode = .single }
        if focused == number {
            setFocus(sessions[min(index, sessions.count - 1)].number)
        }
        onLayoutChange?()
        saveState()
        ExtensionsHub.shared.sessionsChanged()
    }

    func ensureHost(_ info: SessionInfo) {
        guard hosts[info.number] == nil else { return }
        let host = TerminalHost(number: info.number, connection: connection)
        host.onCwd = { [weak self] path in self?.cwdChanged(info.number, path) }
        host.onTitle = { [weak self] title in self?.titles[info.number] = title }
        hosts[info.number] = host
        var attach = WireMessage(op: "attach")
        attach.number = info.number
        connection.send(attach)
    }

    func cwdChanged(_ number: UInt32, _ path: String) {
        guard let index = sessions.firstIndex(where: { $0.number == number }), sessions[index].cwd != path else { return }
        sessions[index].cwd = path
        onLayoutChange?()
    }

    // MARK: Output

    func output(_ number: UInt32, _ data: Data, _ replay: Bool) {
        guard let host = hosts[number] else { return }
        if !replay, overlay == nil, !codexWarned.contains(number),
           sessions.first(where: { $0.number == number })?.tool == .codex,
           data.range(of: Data("usage limit".utf8)) != nil || data.range(of: Data("rate limit".utf8)) != nil {
            codexWarned.insert(number)
            overlay = .codexLimit(number)
        }
        if replay || shouldFeedNow(number) {
            host.feedOutput(data, replay: replay)
        } else {
            pendingFeed[number, default: Data()].append(data)
            scheduleSparseFlush()
        }
    }

    /// A covered window draws nothing by itself, but the terminal must keep reading: programs wait for its answers.
    /// In low power mode only the focused box is live.
    private func shouldFeedNow(_ number: UInt32) -> Bool {
        if PowerCenter.shared.settings.lowPower && number != focused { return false }
        return true
    }

    private func scheduleSparseFlush() {
        guard sparseTimer == nil else { return }
        sparseTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.sparseTimer = nil
            self?.flushPending()
        }
    }

    func flushPending() {
        for (number, data) in pendingFeed {
            hosts[number]?.feedOutput(data, replay: false)
        }
        pendingFeed.removeAll()
    }

    func setWindowVisible(_ visible: Bool) {
        windowVisible = visible
        if visible { flushPending() }
    }

    // MARK: Sessions

    func newTerminal(cwd: String? = nil) {
        var spec = SessionSpec(cwd: cwd ?? focusedInfo?.cwd, rows: 30, cols: 100)
        spec.tool = .terminal
        create(spec)
    }

    func create(_ spec: SessionSpec, then: ((SessionInfo) -> Void)? = nil) {
        var request = WireMessage(op: "create")
        request.spec = spec
        connection.request(request) { [weak self] reply in
            guard let self else { return }
            if let info = reply.session {
                if !self.sessions.contains(where: { $0.number == info.number }) {
                    self.sessions.append(info)
                }
                self.ensureHost(info)
                if self.sessions.count > 1, self.mode == .single {
                    self.mode = SettingsStore.shared.settings.newTerminalAsTab ? .tabs : .canvas
                    self.hint = "İki Terminal Yan Yana · ⌘⏎ Tam Ekran · ⌘W Kapat"
                }
                if self.sessions.count == 7 { self.hint = "Kutular Küçülmez, Sürükleyerek Gezin · ⌥⌘0 Sığdır" }
                self.maximized = nil
                self.setFocus(info.number)
                self.onLayoutChange?()
                self.saveState()
                ExtensionsHub.shared.sessionsChanged()
                then?(info)
            } else {
                self.hint = reply.error ?? "Oturum Başlamadı"
            }
        }
    }

    func closeFocused() {
        guard let focused else { return }
        close(focused)
    }

    func close(_ number: UInt32) {
        var message = WireMessage(op: "remove")
        message.number = number
        connection.send(message)
        closeLocally(number)
    }

    func setFocus(_ number: UInt32?) {
        let changed = focused != number
        focused = number
        if changed, PowerCenter.shared.settings.lowPower { flushPending() }
        onFocusChange?()
    }

    func focusNext(_ delta: Int) {
        guard !sessions.isEmpty else { return }
        let index = sessions.firstIndex { $0.number == focused } ?? 0
        let next = (index + delta + sessions.count) % sessions.count
        setFocus(sessions[next].number)
        if maximized != nil { maximized = sessions[next].number; onLayoutChange?() }
    }

    func selectIndex(_ index: Int) {
        guard index < sessions.count else { return }
        setFocus(sessions[index].number)
        if maximized != nil || mode == .tabs { maximized = sessions[index].number }
        onLayoutChange?()
    }

    /// ⌘⏎: the focused box grows to the whole window, again shows everything.
    func toggleMaximize() {
        guard sessions.count > 1 else { return }
        maximized = maximized == nil ? focused : nil
        onLayoutChange?()
        onFocusChange?()
    }

    func toggleCanvas() {
        if sessions.count < 2 {
            hint = "Tuval İkinci Oturumla Gelir"
            return
        }
        maximized = nil
        mode = mode == .canvas ? .tabs : .canvas
        onLayoutChange?()
        saveState()
    }

    func rename(_ number: UInt32, _ name: String) {
        var message = WireMessage(op: "rename")
        message.number = number
        message.text = name
        connection.send(message)
    }

    func interrupt() {
        guard let focused else { return }
        connection.sendInput(number: focused, bytes: Data([3]))
    }

    func saveState() {
        state.mode = mode
        JSONStore.save(state, to: EntermPaths.stateFile)
    }

    func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.3), 1.5)
        onLayoutChange?()
    }

    func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    func title(for info: SessionInfo) -> String {
        if !info.name.isEmpty { return info.name }
        return displayPath(info.cwd)
    }

    func toolLabel(for info: SessionInfo) -> String {
        if info.tool != .terminal { return info.tool.title }
        return titles[info.number].flatMap { Self.shellName(from: $0) } ?? Self.loginShellName
    }

    static let loginShellName: String = {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh").lastPathComponent
    }()

    private static func shellName(from title: String) -> String? { nil }
}
