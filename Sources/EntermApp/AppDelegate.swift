import AppKit
import EntermCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var root: RootView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        EntermPaths.ensureDirectories()
        applyTheme()
        buildMenu()
        root = RootView()
        let frame = NSRect(x: 0, y: 0, width: 1200, height: 760)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.palette.bg
        window.minSize = NSSize(width: 560, height: 360)
        window.contentView = root
        window.delegate = self
        window.isRestorable = false
        window.setFrameAutosaveName("EntermMain")
        if !window.setFrameUsingName("EntermMain") { window.center() }
        window.makeKeyAndOrderFront(nil)
        AppModel.shared.start()
        Scheduler.shared.start()
#if ENTERM_TEST_DRIVER
        DebugDriver.shared.perform = { Commands.perform($0) }
        DebugDriver.shared.typeText = { AppModel.shared.focusedHost?.type($0) }
        DebugDriver.shared.start()
#endif
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            let visible = self?.window.occlusionState.contains(.visible) ?? true
            AppModel.shared.setWindowVisible(visible)
            // A covered window skips its drawing. Whatever arrived meanwhile shows as soon as it is seen.
            if visible { AppModel.shared.hosts.values.forEach { $0.needsDisplay = true } }
        }
    }

    func applyTheme() {
        switch SettingsStore.shared.settings.theme {
        case "light": Theme.isLight = true
        case "system": Theme.isLight = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
        default: Theme.isLight = false
        }
        NSApp.appearance = NSAppearance(named: Theme.isLight ? .aqua : .darkAqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
            menu.addItem(.separator())
            menu.addItem(withTitle: "Enterm'i Gizle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            menu.addItem(withTitle: "Enterm'den Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }
        submenu("Oturum") { menu in
            add(menu, "Yeni Terminal", "newTerminal")
            add(menu, "Yeni Oturum", "newSession")
            add(menu, "Kutuyu Kapat", "close")
            menu.addItem(.separator())
            add(menu, "Tam Ekran", "maximize")
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
        }
        submenu("Görünüm") { menu in
            add(menu, "Komutlar", "palette")
            add(menu, "Onay Kutusu", "inbox")
            add(menu, "Pano", "board")
            add(menu, "Yönetici Görünümü", "manager")
            add(menu, "Tarayıcı", "browser")
            add(menu, "Yakınlaştır", "zoomIn")
            add(menu, "Uzaklaştır", "zoomOut")
            add(menu, "Sığdır", "fit")
        }
        submenu("Pencere") { menu in
            menu.addItem(withTitle: "Küçült", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
            menu.addItem(withTitle: "Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "")
        }
        NSApp.mainMenu = main
    }
}
