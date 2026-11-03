import AppKit
import EntermCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let connection = ServiceConnection()
    var window: NSWindow!
    var root: RootView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        root = RootView(connection: connection)
        let frame = NSRect(x: 0, y: 0, width: 960, height: 620)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = Theme.palette.bg
        window.minSize = NSSize(width: 480, height: 300)
        window.contentView = root
        window.delegate = self
        window.setFrameAutosaveName("EntermMain")
        if !window.setFrameUsingName("EntermMain") { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        root.start()
        DebugDriver.shared.typeText = { [weak self] text in self?.root.host?.type(text) }
        DebugDriver.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Enterm'den Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Düzen")
        edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}

/// Step one: a single terminal under a slim bar, ready to type into.
final class RootView: NSView {
    let connection: ServiceConnection
    var host: TerminalHost?
    let bar = NSView()
    let pathLabel = NSTextField(labelWithString: "~")
    let shellLabel = NSTextField(labelWithString: "zsh")
    var info: SessionInfo?

    init(connection: ServiceConnection) {
        self.connection = connection
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.palette.bg.cgColor
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.palette.panel.cgColor
        addSubview(bar)
        pathLabel.font = Theme.font(bold: true)
        pathLabel.textColor = Theme.palette.fg
        shellLabel.font = Theme.font()
        shellLabel.textColor = Theme.palette.dim
        bar.addSubview(pathLabel)
        bar.addSubview(shellLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func start() {
        connection.onOutput = { [weak self] number, data, replay in
            guard let host = self?.host, host.number == number else { return }
            host.feedOutput(data, replay: replay)
        }
        connection.onMessage = { [weak self] message in self?.handle(message) }
        connection.connect { [weak self] ok in
            guard ok else { return }
            self?.connection.send(WireMessage(op: "hello"))
        }
    }

    func handle(_ message: WireMessage) {
        switch message.op {
        case "state":
            if let first = message.sessions?.first(where: { $0.status != .exited }) {
                show(first)
            } else {
                var request = WireMessage(op: "create")
                request.spec = SessionSpec(rows: 30, cols: 100)
                connection.request(request) { [weak self] reply in
                    if let session = reply.session { self?.show(session) }
                }
            }
        case "session":
            guard let session = message.session, session.number == info?.number else { return }
            info = session
            if session.status == .exited { NSApp.terminate(nil) }
        default:
            break
        }
    }

    func show(_ session: SessionInfo) {
        info = session
        let host = TerminalHost(number: session.number, connection: connection)
        host.onCwd = { [weak self] path in self?.setPath(path) }
        self.host = host
        addSubview(host)
        layoutHost()
        var attach = WireMessage(op: "attach")
        attach.number = session.number
        connection.send(attach)
        setPath(session.cwd)
        window?.makeFirstResponder(host)
    }

    func setPath(_ path: String) {
        let home = NSHomeDirectory()
        pathLabel.stringValue = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        needsLayout = true
    }

    func layoutHost() {
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 44)
        pathLabel.sizeToFit()
        pathLabel.frame.origin = NSPoint(x: 84, y: (44 - pathLabel.frame.height) / 2)
        shellLabel.sizeToFit()
        shellLabel.frame.origin = NSPoint(x: pathLabel.frame.maxX + 8, y: (44 - shellLabel.frame.height) / 2)
        host?.frame = NSRect(x: 16, y: 56, width: bounds.width - 32, height: bounds.height - 68)
    }

    override func layout() {
        super.layout()
        layoutHost()
    }
}
