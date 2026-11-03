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
        NSApp.activate(ignoringOtherApps: true)
        AppModel.shared.start()
        Scheduler.shared.start()
        DebugDriver.shared.perform = { Commands.perform($0) }
        DebugDriver.shared.typeText = { AppModel.shared.focusedHost?.type($0) }
        DebugDriver.shared.start()
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            AppModel.shared.setWindowVisible(self?.window.occlusionState.contains(.visible) ?? true)
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

    func applicationWillTerminate(_ notification: Notification) {
        if let dir = ProcessInfo.processInfo.environment["ENTERM_DEBUG_DIR"] {
            try? Thread.callStackSymbols.joined(separator: "\n").write(toFile: dir + "/term.log", atomically: true, encoding: .utf8)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func runCommand(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Commands.perform(id) }
    }

    @objc func selectSession(_ sender: NSMenuItem) {
        AppModel.shared.selectIndex(sender.tag)
    }

    func buildMenu() {
        let main = NSMenu()
        func submenu(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            build(menu)
            item.submenu = menu
            main.addItem(item)
        }
        func add(_ menu: NSMenu, _ title: String, _ id: String, _ key: String = "", _ flags: NSEvent.ModifierFlags = [.command]) {
            let item = NSMenuItem(title: title, action: #selector(runCommand(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = flags
            item.representedObject = id
            item.target = self
            menu.addItem(item)
        }
        submenu("Enterm") { menu in
            add(menu, "Ayarlar", "settings", ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Enterm'i Gizle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            menu.addItem(withTitle: "Enterm'den Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }
        submenu("Oturum") { menu in
            add(menu, "Yeni Terminal", "newTerminal", "t")
            add(menu, "Yeni Oturum", "newSession", "n")
            add(menu, "Kutuyu Kapat", "close", "w")
            menu.addItem(.separator())
            add(menu, "Tam Ekran", "maximize", "\r")
            add(menu, "Ayrıntılar", "details", "i")
            add(menu, "Durdur", "stop", ".")
            add(menu, "Sonraki Oturum", "next", "]")
            add(menu, "Önceki Oturum", "previous", "[")
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
            add(menu, "Komutlar", "palette", "k")
            add(menu, "Onay Kutusu", "inbox", "o", [.command, .shift])
            add(menu, "Pano", "board", "b", [.command, .shift])
            add(menu, "Yönetici Görünümü", "manager", "y", [.command, .shift])
            add(menu, "Tarayıcı", "browser", "d", [.command, .shift])
            add(menu, "Yakınlaştır", "zoomIn", "=")
            add(menu, "Uzaklaştır", "zoomOut", "-")
            add(menu, "Sığdır", "fit", "0", [.command, .option])
        }
        submenu("Pencere") { menu in
            menu.addItem(withTitle: "Küçült", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
            menu.addItem(withTitle: "Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "")
        }
        NSApp.mainMenu = main
    }
}
