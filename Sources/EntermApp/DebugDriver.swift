#if ENTERM_TEST_DRIVER
import AppKit
import CoreGraphics
import EntermCore
import QuartzCore
import SwiftUI

/// A test hook, active only when `ENTERM_DEBUG_DIR` is set. On SIGUSR1 it runs the lines of `<dir>/cmd`.
/// It lets automated checks drive the running app and capture its own window without system permissions.
final class DebugDriver {
    static let shared = DebugDriver()
    var perform: ((String) -> Void)?
    var typeText: ((String) -> Void)?
    private var source: DispatchSourceSignal?
    private var directory: String?

    func start() {
        guard let dir = ProcessInfo.processInfo.environment["ENTERM_DEBUG_DIR"], !dir.isEmpty else { return }
        directory = dir
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.runCommands() }
        source.resume()
        self.source = source
    }

    private func runCommands() {
        guard let directory, let text = try? String(contentsOfFile: directory + "/cmd", encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard let verb = parts.first else { continue }
            let rest = parts.count > 1 ? parts[1] : ""
            switch verb {
            case "do": perform?(rest)
            case "front":
                NSApp.windows.first?.setFrame(NSRect(x: 40, y: 40, width: 760, height: 480), display: true)
                NSApp.windows.first?.orderFrontRegardless()
            case "ghost":
                // On screen for the window server, invisible to the eye and to the mouse. It takes no focus.
                if let window = NSApp.windows.first {
                    window.alphaValue = rest == "on" ? 0.01 : 1
                    window.ignoresMouseEvents = rest == "on"
                    window.level = rest == "on" ? .floating : .normal
                    if rest == "on" { window.orderFrontRegardless() } else { window.orderBack(nil) }
                }
            case "tail":
                var message = WireMessage(op: "tail")
                message.number = AppModel.shared.focused
                AppModel.shared.connection.request(message) { reply in
                    try? (reply.text ?? "").write(toFile: rest, atomically: true, encoding: .utf8)
                }
            case "key":
                sendKey(rest)
            case "click":
                let numbers = rest.split(separator: " ").compactMap { Double($0) }
                if numbers.count == 2 { mouse([(.leftMouseDown, numbers[0], numbers[1]), (.leftMouseUp, numbers[0], numbers[1])]) }
            case "drag":
                let n = rest.split(separator: " ").compactMap { Double($0) }
                if n.count == 4 {
                    mouse([(.leftMouseDown, n[0], n[1]), (.leftMouseDragged, (n[0] + n[2]) / 2, (n[1] + n[3]) / 2),
                           (.leftMouseDragged, n[2], n[3]), (.leftMouseUp, n[2], n[3])])
                }
            case "remote":
                let n = rest.split(separator: " ").map(String.init)
                if n.count == 2 { RemoteProject(host: n[0], folder: n[1]).open() }
            case "hit":
                let n = rest.split(separator: " ").compactMap { Double($0) }
                if n.count == 2, let view = NSApp.windows.first?.contentView {
                    let hit = view.hitTest(NSPoint(x: n[0], y: n[1]))
                    var chain = ""
                    var cursor = hit
                    while let current = cursor {
                        chain += "\(type(of: current)) \(current.frame) > "
                        cursor = current.superview
                    }
                    try? chain.write(toFile: "/tmp/et/hit.txt", atomically: true, encoding: .utf8)
                }
            case "state":
                let model = AppModel.shared
                let text = "overlay=\(String(describing: model.overlay)) page=\(String(describing: model.page)) focused=\(String(describing: model.focused)) maximized=\(String(describing: model.maximized)) mode=\(model.mode) sessions=\(model.sessions.count) details=\(model.detailsOpen) links=\(LinkStore.shared.links.count) pressure=\(PowerCenter.shared.pressure.title) visible=\(NSApp.windows.first?.occlusionState.contains(.visible) ?? false)\n"
                try? text.write(toFile: rest, atomically: true, encoding: .utf8)
            case "pair":
                PhoneStore.shared.start(relay: rest)
            case "pairoffer":
                if case .waiting(let offer, _) = PhoneStore.shared.pairing { try? offer.write(toFile: rest, atomically: true, encoding: .utf8) }
                if case .compare(let offer, _, _) = PhoneStore.shared.pairing { try? offer.write(toFile: rest, atomically: true, encoding: .utf8) }
            case "pairstate":
                try? "\(PhoneStore.shared.pairing)\n\(PhoneStore.shared.devices)\n".write(toFile: rest, atomically: true, encoding: .utf8)
            case "settingstab":
                if let tab = SettingsTab(rawValue: rest) { AppModel.shared.page = .settings(tab) }
            case "showapproval":
                if let id = AppModel.shared.sessions.compactMap(\.pendingApproval).first?.id { AppModel.shared.overlay = .approval(id) }
            case "pairremove":
                if let device = PhoneStore.shared.devices.first { PhoneStore.shared.remove(device.id) }
            case "sleepsim":
                AppModel.shared.connection.send(WireMessage(op: "testSleep"))
            case "pairconfirm":
                PhoneStore.shared.confirm()
            case "rawtool":
                // Starts a program without the launcher's check, as a queued or restored session does.
                if let tool = ToolKind.fromCommand(rest) {
                    var spec = SessionSpec(tool: tool, rows: 30, cols: 100)
                    spec.env = ["ENTERM_STARTUP": rest]
                    AppModel.shared.create(spec)
                }
            case "status":
                let model = AppModel.shared
                let labels = model.sessionLabels
                let text = model.sessions.map { "\($0.number) \($0.tool.rawValue) \($0.status.rawValue) [\(labels[$0.number] ?? "")]" }.joined(separator: "\n")
                    + "\ncard=\(String(describing: model.notFound?.title))\npresence=\(ToolCatalog.shared.presence)\n"
                try? text.write(toFile: rest, atomically: true, encoding: .utf8)
            case "scroller":
                var text = ""
                for (number, host) in AppModel.shared.hosts.sorted(by: { $0.key < $1.key }) {
                    let bars = host.subviews.compactMap { $0 as? NSScroller }
                    for bar in bars {
                        text += "\(number) canScroll=\(host.canScroll) position=\(host.scrollPosition) hidden=\(bar.isHidden) enabled=\(bar.isEnabled) value=\(bar.doubleValue) knob=\(bar.knobProportion) alpha=\(bar.alphaValue)\n"
                    }
                }
                try? text.write(toFile: rest, atomically: true, encoding: .utf8)
            case "wheel":
                let lines = Int32(rest) ?? 0
                if let host = AppModel.shared.hosts[AppModel.shared.focused ?? 0],
                   let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0),
                   let event = NSEvent(cgEvent: cg) { host.scrollWheel(with: event) }
            case "hover":
                for box in Self.boxes(in: NSApp.windows.first?.contentView) { rest == "on" ? box.mouseEntered(with: NSEvent()) : box.mouseExited(with: NSEvent()) }
            case "theme":
                SettingsStore.shared.settings.theme = rest
            case "flow":
                SettingsStore.shared.settings.flowStartsOpen = rest == "on"
            case "team":
                TeamBuilder.build(brief: "Test Ekibi", folder: rest, members: Team.template("software"))
            case "card":
                BoardStore.shared.change { board in
                    var card = BoardCard(title: rest)
                    card.members = ["Arda"]
                    card.comments = [CardComment(author: "Siz", isAgent: false, text: "Öncelikle bitirelim")]
                    board.cards.append(card)
                }
            case "type": typeText?(rest.replacingOccurrences(of: "\\r", with: "\r"))
            case "shot": capture(to: rest)
            default: break
            }
        }
        try? "done\n".write(toFile: directory + "/done", atomically: true, encoding: .utf8)
    }

    /// Synthetic input through the app's own event path. It reaches only this app, never another window.
    private func sendKey(_ spec: String) {
        var flags: NSEvent.ModifierFlags = []
        var key = spec
        for (prefix, flag) in [("cmd+", NSEvent.ModifierFlags.command), ("shift+", .shift), ("ctrl+", .control), ("opt+", .option)] {
            while key.hasPrefix(prefix) {
                flags.insert(flag)
                key.removeFirst(prefix.count)
            }
        }
        let codes: [String: UInt16] = ["esc": 53, "enter": 36, "down": 125, "up": 126]
        let characters = key == "enter" ? "\r" : key == "esc" ? "\u{1b}" : key
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: NSApp.windows.first?.windowNumber ?? 0, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: codes[key] ?? 0) else { return }
        if flags.contains(.command), NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return }
        NSApp.sendEvent(event)
    }

    /// Coordinates are from the window's top left corner.
    private func mouse(_ steps: [(NSEvent.EventType, Double, Double)]) {
        guard let window = NSApp.windows.first else { return }
        let height = window.contentView?.bounds.height ?? 0
        var events: [NSEvent] = []
        for (type, x, y) in steps {
            guard let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: height - y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            events.append(event)
        }
        // A drag handler pulls the following events from the queue, so they must be waiting first.
        events.dropFirst().forEach { NSApp.postEvent($0, atStart: false) }
        if let first = events.first { NSApp.sendEvent(first) }
    }

    func capture(to path: String) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView, let layer = view.layer else { return }
        AppModel.shared.flushPending()
        let size = view.bounds.size
        // Terminals draw through draw(_:), which a layer render misses. So the picture is built in order:
        // everything under the terminals, the terminals, and last whatever covers them.
        let cover = view.subviews.flatMap { $0.subviews }.first { $0 is NSHostingView<CoverContent> } ?? view.subviews.first { $0 is NSHostingView<CoverContent> }
        let terminals = Self.terminals(in: view).filter { !$0.isHiddenOrHasHiddenAncestor }
        terminals.forEach { $0.isHidden = true }
        cover?.isHidden = true
        window.displayIfNeeded()
        guard let context = Self.context(size) else { return }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -size.height)
        terminals.forEach { $0.isHidden = false }
        cover?.isHidden = false
        window.displayIfNeeded()
        for host in terminals {
            guard let picture = Self.picture(of: host) else { continue }
            let rect = host.convert(host.bounds, to: view)
            let y = view.isFlipped ? size.height - rect.maxY : rect.minY
            context.draw(picture, in: CGRect(x: rect.minX, y: y, width: rect.width, height: rect.height))
        }
        if let cover, let coverLayer = cover.layer {
            let rect = cover.convert(cover.bounds, to: view)
            let y = view.isFlipped ? size.height - rect.maxY : rect.minY
            context.saveGState()
            context.translateBy(x: rect.minX, y: y + rect.height)
            context.scaleBy(x: 1, y: -1)
            coverLayer.render(in: context)
            context.restoreGState()
        }
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func context(_ size: CGSize) -> CGContext? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// The cached picture has a white base where the real view shows its layer colour.
    private static func picture(of host: TerminalHost) -> CGImage? {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let source = rep.cgImage, let context = context(CGSize(width: source.width, height: source.height)),
              let data = context.data else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let color = host.nativeBackgroundColor.usingColorSpace(.sRGB) ?? .black
        let (r, g, b) = (UInt8(color.redComponent * 255), UInt8(color.greenComponent * 255), UInt8(color.blueComponent * 255))
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * source.height)
        for row in 0..<source.height {
            for col in 0..<source.width {
                let p = bytes + row * context.bytesPerRow + col * 4
                if p[0] >= 250, p[1] >= 250, p[2] >= 250 {
                    p[0] = r
                    p[1] = g
                    p[2] = b
                }
            }
        }
        return context.makeImage()
    }

    private static func boxes(in view: NSView?) -> [SessionBox] {
        guard let view else { return [] }
        return view.subviews.flatMap { ($0 as? SessionBox).map { [$0] } ?? boxes(in: $0) }
    }

    private static func terminals(in view: NSView) -> [TerminalHost] {
        var found: [TerminalHost] = []
        for child in view.subviews {
            if let host = child as? TerminalHost { found.append(host) } else { found += terminals(in: child) }
        }
        return found
    }
}
#endif
