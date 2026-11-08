import AppKit
import EntermCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var root: RootView!
    private var confirmedQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        EntermPaths.ensureDirectories()
        // Programs behave as in a plain terminal unless the person chooses a stricter template.
        if !SettingsStore.shared.settings.templateChosen {
            var book = PermissionBook.load()
            book.defaultTemplate = .free
            book.save()
            SettingsStore.shared.settings.defaultTemplate = .free
            SettingsStore.shared.settings.templateChosen = true
        }
        applyTheme()
        Theme.refreshPalette()
        Updates.shared.start()
        buildMenu()
        root = RootView()
        let frame = NSRect(x: 0, y: 0, width: 1200, height: 760)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.palette.surface0
        window.minSize = NSSize(width: 560, height: 360)
        window.contentView = root
        window.delegate = self
        placeWindowButtons()
        window.isRestorable = false
        window.setFrameAutosaveName("EntermMain")
        if !window.setFrameUsingName("EntermMain") { window.center() }
#if ENTERM_TEST_DRIVER
        // A test run must not take the screen from whoever is working.
        if ProcessInfo.processInfo.environment["ENTERM_DEBUG_DIR"] != nil {
            window.orderBack(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
#else
        window.makeKeyAndOrderFront(nil)
#endif
        AppModel.shared.start()
        Scheduler.shared.start()
#if ENTERM_TEST_DRIVER
        DebugDriver.shared.perform = { Commands.perform($0) }
        DebugDriver.shared.typeText = { AppModel.shared.focusedHost?.type($0) }
        DebugDriver.shared.start()
#endif
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            if SettingsStore.shared.settings.theme == "system" { self?.applyAppearance() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            let visible = self?.window.occlusionState.contains(.visible) ?? true
            AppModel.shared.setWindowVisible(visible)
            // A covered window skips its drawing. Whatever arrived meanwhile shows as soon as it is seen.
            if visible { AppModel.shared.hosts.values.forEach { $0.needsDisplay = true } }
        }
    }

    /// Everything that depends on the look, after a setting changed.
    /// The window buttons sit in the middle of the top bar, in line with what is beside them. AppKit puts them back on some
    /// window changes, so this runs after those too. Full screen has its own title bar and is left alone.
    func placeWindowButtons() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let minimize = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let bar = close.superview, let container = bar.superview else { return }
        let height: CGFloat = AppModel.shared.focusMode ? 28 : 44
        let frame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
        if container.frame != frame { container.frame = frame }
        if bar.frame.size != frame.size { bar.frame = NSRect(origin: .zero, size: frame.size) }
        for (index, button) in [close, minimize, zoom].enumerated() {
            let origin = NSPoint(x: 16 + CGFloat(index) * 20, y: ((height - button.frame.height) / 2).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }

    func windowDidResize(_ notification: Notification) { placeWindowButtons() }
    func windowDidBecomeKey(_ notification: Notification) { placeWindowButtons() }
    func windowDidResignKey(_ notification: Notification) { placeWindowButtons() }
    func windowDidExitFullScreen(_ notification: Notification) { placeWindowButtons() }

    func applyAppearance() {
        applyTheme()
        Theme.refreshPalette()
        window.backgroundColor = Theme.palette.surface0
        AppModel.shared.hosts.values.forEach { $0.applyTheme() }
        root.layer?.backgroundColor = Theme.palette.surface0.cgColor
        root.canvas.needsDisplay = true
        AppearanceTick.shared.fire()
        AppModel.shared.objectWillChange.send()
        SettingsStore.shared.objectWillChange.send()
        AppModel.shared.onLayoutChange?()
    }

    func applyTheme() {
        switch SettingsStore.shared.settings.theme {
        case "light": Theme.isLight = true
        // The app's own appearance is forced below, so the system's answer is read from its setting.
        case "system": Theme.isLight = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != "Dark"
        default: Theme.isLight = false
        }
        NSApp.appearance = NSAppearance(named: Theme.isLight ? .aqua : .darkAqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Sessions go on after the window closes. The question is only asked when something is running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard SettingsStore.shared.settings.confirmQuit, !confirmedQuit, model.sessions.contains(where: { $0.tool != .terminal && $0.status == .running }),
              ProcessInfo.processInfo.environment["ENTERM_DEBUG_DIR"] == nil else { return .terminateNow }
        model.confirm(title: "Enterm Kapatılsın mı?", detail: "Oturumlar arkada çalışmaya devam eder, yeniden açınca kaldığı yerde durur.", action: "Kapat", danger: false) { [weak self] in
            self?.confirmedQuit = true
            NSApp.terminate(nil)
        }
        return .terminateCancel
    }

    @objc func runCommand(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Commands.perform(id) }
    }

    @objc func selectSession(_ sender: NSMenuItem) {
        AppModel.shared.selectIndex(sender.tag)
    }

    func buildMenu() {
        let book = ShortcutBook.load()
        let main = NSMenu()
        func submenu(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            build(menu)
            item.submenu = menu
            main.addItem(item)
        }
        func add(_ menu: NSMenu, _ title: String, _ id: String) {
            let combo = book.combo(for: id)
            let item = NSMenuItem(title: title, action: #selector(runCommand(_:)), keyEquivalent: combo?.key ?? "")
            var flags: NSEvent.ModifierFlags = []
            if combo?.command == true { flags.insert(.command) }
            if combo?.shift == true { flags.insert(.shift) }
            if combo?.option == true { flags.insert(.option) }
            if combo?.control == true { flags.insert(.control) }
            item.keyEquivalentModifierMask = flags
            item.representedObject = id
            item.target = self
            menu.addItem(item)
        }
        submenu("Enterm") { menu in
            add(menu, "Ayarlar", "settings")
            if Updates.shared.available {
                let check = NSMenuItem(title: "Güncellemeleri Denetle…", action: #selector(Updates.check(_:)), keyEquivalent: "")
                check.target = Updates.shared
                menu.addItem(check)
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Enterm'i Gizle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            menu.addItem(withTitle: "Enterm'den Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }
        submenu("Oturum") { menu in
            add(menu, "Yeni Terminal", "newTerminal")
            add(menu, "Yeni Oturum", "newSession")
            add(menu, "Yeni Proje", "newProject")
            add(menu, "Kutuyu Kapat", "close")
            add(menu, "Son Kapatılanı Yeniden Aç", "reopen")
            menu.addItem(.separator())
            add(menu, "Tam Ekran", "maximize")
            add(menu, "Sohbet Görünümü", "chat")
            add(menu, "Ayrıntılar", "details")
            add(menu, "Durdur", "stop")
            add(menu, "Sonraki Oturum", "next")
            add(menu, "Önceki Oturum", "previous")
            for index in 0..<9 {
                let item = NSMenuItem(title: "Oturum \(index + 1)", action: #selector(selectSession(_:)), keyEquivalent: "\(index + 1)")
                item.tag = index
                item.target = self
                menu.addItem(item)
            }
        }
        submenu("Düzen") { edit in
            edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            edit.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            edit.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            edit.addItem(.separator())
            let find = NSMenuItem(title: "Terminalde Bul", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f")
            find.tag = NSTextFinder.Action.showFindInterface.rawValue
            edit.addItem(find)
            let next = NSMenuItem(title: "Sonrakini Bul", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "g")
            next.tag = NSTextFinder.Action.nextMatch.rawValue
            edit.addItem(next)
        }
        submenu("Görünüm") { menu in
            add(menu, "Komutlar", "palette")
            add(menu, "Odak Modu", "focusMode")
            add(menu, "Durak Hattı", "toggleRail")
            add(menu, "Dosyalar", "files")
            add(menu, "Değişiklikler", "changes")
            add(menu, "Onay Kutusu", "inbox")
            add(menu, "Pano", "board")
            add(menu, "Yönetici Görünümü", "manager")
            add(menu, "Tarayıcı", "browser")
            add(menu, "Yakınlaştır", "zoomIn")
            add(menu, "Uzaklaştır", "zoomOut")
            add(menu, "Sığdır", "fit")
            menu.addItem(.separator())
            add(menu, "Düzeni Geri Al", "undoLayout")
            add(menu, "Düzeni Yinele", "redoLayout")
            add(menu, "Sol Yarıya Yerleştir", "zoneLeft")
            add(menu, "Sağ Yarıya Yerleştir", "zoneRight")
            add(menu, "Üst Yarıya Yerleştir", "zoneTop")
            add(menu, "Alt Yarıya Yerleştir", "zoneBottom")
            add(menu, "Soldaki Kutuya Geç", "focusLeft")
            add(menu, "Sağdaki Kutuya Geç", "focusRight")
            add(menu, "Üstteki Kutuya Geç", "focusUp")
            add(menu, "Alttaki Kutuya Geç", "focusDown")
        }
        submenu("Pencere") { menu in
            menu.addItem(withTitle: "Küçült", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
            menu.addItem(withTitle: "Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "")
        }
        NSApp.mainMenu = main
    }
}
