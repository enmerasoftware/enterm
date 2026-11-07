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
    case run
    case whiteboard
    case simulator
    case uninstall
    case welcome
    case recents
    case notYet(String)
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case programs, accounts, custom, gateway, usage, commits
    case terminal, shell, session, behavior, browser
    case appearance, notch, notifications, voice, shortcuts
    case phone, ssh
    case power, security, about
    var id: String { rawValue }

    static let groups: [(title: String, tabs: [SettingsTab])] = [
        ("Programlar", [.programs, .accounts, .custom, .gateway, .usage, .commits]),
        ("Çalışma Alanı", [.terminal, .shell, .session, .behavior, .browser]),
        ("Arayüz", [.appearance, .notch, .notifications, .voice, .shortcuts]),
        ("Uzak", [.phone, .ssh]),
        ("Uygulama", [.power, .security, .about]),
    ]

    var title: String {
        switch self {
        case .programs: return "Programlar"
        case .accounts: return "Hesaplar"
        case .custom: return "Özel Programlar"
        case .gateway: return "Model Ağ Geçidi"
        case .usage: return "Kullanım"
        case .commits: return "Commit İletileri"
        case .terminal: return "Terminal"
        case .shell: return "Kabuk"
        case .session: return "Oturum Koruma"
        case .behavior: return "Davranış"
        case .browser: return "Tarayıcı"
        case .appearance: return "Görünüm"
        case .notch: return "Çentik"
        case .notifications: return "Bildirimler"
        case .voice: return "Ses"
        case .shortcuts: return "Kısayollar"
        case .phone: return "Telefon"
        case .ssh: return "Uzak Sunucular"
        case .power: return "Güç Sınırı"
        case .security: return "Güvenlik"
        case .about: return "Hakkında"
        }
    }
    var icon: String {
        switch self {
        case .programs: return "sparkle"
        case .accounts: return "person"
        case .custom: return "plus.square"
        case .gateway: return "point.3.connected.trianglepath.dotted"
        case .usage: return "chart.bar"
        case .commits: return "text.badge.checkmark"
        case .terminal: return "terminal"
        case .shell: return "chevron.right"
        case .session: return "shield"
        case .behavior: return "slider.horizontal.3"
        case .browser: return "safari"
        case .appearance: return "circle.lefthalf.filled"
        case .notch: return "rectangle.topthird.inset.filled"
        case .notifications: return "bell"
        case .voice: return "waveform"
        case .shortcuts: return "command"
        case .phone: return "iphone"
        case .ssh: return "server.rack"
        case .power: return "gauge.with.needle"
        case .security: return "lock"
        case .about: return "info.circle"
        }
    }
    /// Pages that write their own title.
    var bringsOwnTitle: Bool { self == .accounts || self == .phone || self == .ssh }

    /// What a search in the settings looks through.
    var searchText: String {
        let words: String
        switch self {
        case .terminal: words = "tema renk yazı tipi font imleç kopyala geçmiş"
        case .appearance: words = "neon hareket vurgu duvar kağıdı tema ızgara"
        case .behavior: words = "uyku uyanık odak ızgara harita durak çıkış"
        case .browser: words = "safari webkit giriş hesap çerez site"
        case .notifications: words = "ses bildirim betik"
        case .programs: words = "claude codex gemini grok cursor copilot opencode antigravity varsayılan"
        case .gateway: words = "model sunucu anahtar api"
        case .usage: words = "limit yüzde maliyet"
        case .power: words = "işlemci bellek düşük güç"
        default: words = ""
        }
        return (title + " " + words).lowercased(with: Locale(identifier: "tr_TR"))
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
    case sshList(String)
    case remoteLost(UInt32)
    case resumeFailed(UInt32)
    case codexLimit(UInt32)
    case installTool(ToolKind)
    case input
    case confirm
    case memory
}

/// The whole app state. Views observe it; nothing polls.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let connection = ServiceConnection()
    @Published var sessions: [SessionInfo] = []
    @Published var focused: UInt32?
    @Published var mode: ViewMode = .single
    @Published var maximized: UInt32?
    @Published var page: Page? {
        didSet {
            if page == nil {
                pageTrail.removeAll()
            } else if let oldValue, oldValue != page, !leavingBack {
                if case .settings = oldValue, case .settings? = page { return }
                pageTrail.append(oldValue)
            }
        }
    }
    private var pageTrail: [Page] = []
    private var leavingBack = false

    /// Back goes where the person came from: a page opened from the settings returns to the settings.
    func goBack() {
        leavingBack = true
        page = pageTrail.popLast()
        leavingBack = false
    }
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
    @Published var heavyQueue: [HeavyEntry] = []
    @Published var remotes: [UInt32: RemoteProject] = [:]
    @Published var activeProject: String?
    @Published var showHome = false
    @Published var chatSessions = Set<UInt32>()
    /// One terminal and nothing around it.
    @Published var focusMode = false
    /// Finished while the person was looking elsewhere. Gone as soon as they look.
    @Published var unread: Set<UInt32> = []
    /// The running service is from another copy of the app.
    @Published var serviceOutdated = false
    /// Boxes stay where they are until this is off.
    @Published var canvasLocked = false
    var lastFocus: [String: UInt32] = [:]
    var startingFromHome = false
    var layoutUndo: [LayoutSnapshot] = []
    var layoutRedo: [LayoutSnapshot] = []
    var closedSessions: [SessionInfo] = []
    var inputRequest: InputRequest?
    var confirmRequest: ConfirmRequest?
    var onSnap: ((UInt32, SnapZone) -> Void)?
    var onMoveFocus: ((SnapZone) -> Void)?

    var hosts: [UInt32: TerminalHost] = [:]
    var state = JSONStore.load(WindowState.self, from: EntermPaths.stateFile) ?? WindowState()
    var onLayoutChange: (() -> Void)?
    var onFocusChange: (() -> Void)?
    var pendingFeed: [UInt32: Data] = [:]
    var windowVisible = true
    var sparseTimer: Timer?
    var fitCanvas: (() -> Void)?
    var arrangeCanvas: (() -> Void)?
    var onReload: (() -> Void)?
    var restorable: [SessionInfo] = []
    var codexWarned = Set<UInt32>()
    /// True once the service has told what is open, so the home screen never flashes before a session.
    var started = false
    private var hintTimer: Timer?

    /// The sessions of the project on screen. A session elsewhere keeps running, it just is not drawn.
    var visibleSessions: [SessionInfo] {
        guard let activeProject else { return sessions }
        return sessions.filter { project(of: $0) == activeProject }
    }
    var focusedInfo: SessionInfo? { sessions.first { $0.number == focused } }
    var hasAgents: Bool { sessions.contains { $0.tool != .terminal } }
    var focusedHost: TerminalHost? { focused.flatMap { hosts[$0] } }

    // MARK: Start

    func start() {
        EntermPaths.ensureDirectories()
        connection.onOutput = { [weak self] number, data, replay in self?.output(number, data, replay) }
        connection.onMessage = { [weak self] message in self?.handle(message) }
        connection.onDisconnect = { [weak self] in self?.lostService() }
        ToolCatalog.shared.refresh()
        connection.connect { [weak self] ok in
            guard let self else { return }
            if ok {
                self.connection.send(self.helloMessage())
            } else {
                self.serviceLost = true
            }
        }
    }

    /// Tells the service where this copy's companion is, in case the app has moved since it started.
    private func helloMessage() -> WireMessage {
        var hello = WireMessage(op: "hello")
        hello.text = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("enterm").path
        return hello
    }

    private func isServiceOutdated(_ stamp: String?) -> Bool {
        guard let path = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("entermd").path,
              let current = EntermVersion.stamp(ofExecutable: path) else { return false }
        return stamp != current
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
                self.connection.send(self.helloMessage())
            }
        }
    }

    func handle(_ message: WireMessage) {
        switch message.op {
        case "state":
            let list = (message.sessions ?? []).filter { $0.status != .exited }
            // A service from before an update has nothing to lose when no session is open.
            if list.isEmpty, isServiceOutdated(message.text) {
                connection.send(WireMessage(op: "shutdown"))
                return
            }
            serviceOutdated = isServiceOutdated(message.text)
            sessions = list
            started = true
            list.forEach { ensureHost($0) }
            if list.isEmpty {
                let saved = JSONStore.load([SessionInfo].self, from: EntermPaths.sessionsFile)?.filter { $0.status != .exited } ?? []
                if !saved.isEmpty {
                    restorable = saved
                    page = .restore
                }
#if ENTERM_TEST_DRIVER
                // Test runs start from a terminal, as most of them need one.
                if ProcessInfo.processInfo.environment["ENTERM_START_TERMINAL"] != nil { newTerminal() }
#endif
                onLayoutChange?()
            } else {
                hint = "Enterm Yeniden Açıldı · Oturumlar Hiç Durmadı"
                let names = projectNames
                activeProject = state.activeProject.flatMap { names.contains($0) ? $0 : nil } ?? names.first
                mode = tileCount > 1 ? (state.mode == .single ? .canvas : state.mode) : .single
                setFocus(visibleSessions.first?.number)
                onLayoutChange?()
            }
            ExtensionsHub.shared.sessionsChanged()
            showWelcomeOnce()
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
            Notifier.shared.post(title: "Enterm", body: message.text ?? "", onlyWhenInactive: false)
        case "heavy":
            if let data = message.text?.data(using: .utf8), let list = try? JSONDecoder().decode([HeavyEntry].self, from: data) {
                heavyQueue = list
            }
        case "appCallCmd":
            PhoneBridge.handle(message)
        case "pairState":
            PhoneStore.shared.pairingChanged(state: message.text ?? "", detail: message.error)
        case "devices":
            PhoneStore.shared.devicesChanged(message.text)
        case "browserCmd":
            BrowserCenter.shared.handle(message: message)
        case "reload":
            if let text = message.text { hint = text }
            BoardStore.shared.reload()
            TeamStore.shared.reload()
            onReload?()
        default:
            break
        }
    }

    /// The tour appears once. It never stands between a person and a session they already have.
    private func showWelcomeOnce() {
        guard !SettingsStore.shared.settings.seenWelcome else { return }
#if ENTERM_TEST_DRIVER
        if ProcessInfo.processInfo.environment["ENTERM_START_TERMINAL"] != nil { return }
#endif
        page = .welcome
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
            assignProject(info)
            ensureHost(info)
            if tileCount > 1, mode == .single { mode = .canvas }
            onLayoutChange?()
        }
    }

    private func forget(_ number: UInt32) {
        closeLocally(number)
    }

    private func closeLocally(_ number: UInt32) {
        guard let index = sessions.firstIndex(where: { $0.number == number }) else { return }
        closedSessions.append(sessions[index])
        unread.remove(number)
        if closedSessions.count > 20 { closedSessions.removeFirst() }
        chatSessions.remove(number)
        sessions.remove(at: index)
        hosts[number]?.removeFromSuperview()
        hosts[number] = nil
        titles[number] = nil
        pendingFeed[number] = nil
        if maximized == number { maximized = nil }
        if notFound?.number == number { notFound = nil }
        if sessions.isEmpty {
            // The home screen takes over, so the last terminal closing does not close the app.
            focused = nil
            mode = .single
            activeProject = nil
            state.activeProject = nil
            onLayoutChange?()
            saveState()
            ExtensionsHub.shared.sessionsChanged()
            return
        }
        // The last box of a project leaves: the next project comes forward.
        if visibleSessions.isEmpty, visibleItems.isEmpty, let next = projectNames.first {
            switchProject(next)
        }
        if tileCount <= 1 { mode = .single }
        if focused == number {
            let list = visibleSessions
            setFocus(list.isEmpty ? nil : list[min(index, list.count - 1)].number)
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
        if !replay, overlay == nil, remotes[number] != nil,
           data.range(of: Data("Connection to ".utf8)) != nil || data.range(of: Data("Broken pipe".utf8)) != nil || data.range(of: Data("Connection reset".utf8)) != nil {
            overlay = .remoteLost(number)
        }
        if !replay, overlay == nil, !codexWarned.contains(number),
           sessions.first(where: { $0.number == number })?.tool == .codex,
           data.range(of: Data("usage limit".utf8)) != nil || data.range(of: Data("rate limit".utf8)) != nil {
            codexWarned.insert(number)
            overlay = .codexLimit(number)
            LimitWatch.shared.codexWarnings.insert(number)
            PhoneBridge.tellPhones(saying: "■ Codex limiti dolmuş olabilir, kontrol edin.")
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

    func newTerminal(cwd: String? = nil, startup: String? = nil) {
        var spec = SessionSpec(cwd: cwd ?? focusedInfo?.cwd, rows: 30, cols: 100)
        spec.tool = .terminal
        if let startup { spec.env = ["ENTERM_STARTUP": startup] }
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
                let isNewProject = self.state.projects[info.id] == nil && self.startingFromHome
                self.assignProject(info)
                if isNewProject, SettingsStore.shared.settings.defaultBoardView { self.page = .board }
                if self.tileCount > 1, self.mode == .single {
                    self.mode = SettingsStore.shared.settings.newTerminalAsTab ? .tabs : .canvas
                    self.hint = "İki Terminal Yan Yana · ⌘⏎ Tam Ekran · ⌘W Kapat"
                }
                if self.tileCount == 7 { self.hint = "Kutular Küçülmez, Sürükleyerek Gezin · ⌥⌘0 Sığdır" }
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
        if let number, unread.contains(number) { unread.remove(number) }
        followFocus(number)
        let shown = FullScreenFocus.shown(current: maximized, focusing: number, visible: visibleSessions.map(\.number))
        if shown != maximized { maximized = shown; onLayoutChange?() }
        if changed, PowerCenter.shared.settings.lowPower { flushPending() }
        if changed, let info = focusedInfo, info.status == .notFound, let command = info.tool.command {
            notFound = NotFoundCard.make(number: info.number, command: command)
        }
        onFocusChange?()
    }

    func focusNext(_ delta: Int) {
        let list = visibleSessions
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.number == focused } ?? 0
        let next = (index + delta + list.count) % list.count
        setFocus(list[next].number)
        if maximized != nil { maximized = list[next].number; onLayoutChange?() }
    }

    func selectIndex(_ index: Int) {
        let list = visibleSessions
        guard index < list.count else { return }
        setFocus(list[index].number)
        if maximized != nil || mode == .tabs { maximized = list[index].number }
        onLayoutChange?()
    }

    /// ⌘⏎: the focused box grows to the whole window, again shows everything.
    func toggleMaximize() {
        guard tileCount > 1 else { return }
        maximized = maximized == nil ? focused : nil
        onLayoutChange?()
        onFocusChange?()
    }

    func toggleCanvas() {
        if tileCount < 2 {
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

    /// The session's name: what the user gave it, or the program with a number when there are several.
    func name(for info: SessionInfo) -> String {
        SessionLabel.names(sessions)[info.number] ?? info.tool.title
    }

    func title(for info: SessionInfo) -> String { name(for: info) }

    /// Labels for the bottom strip and the tabs: the name and the last folder.
    var sessionLabels: [UInt32: String] { SessionLabel.stripLabels(sessions) }
}
