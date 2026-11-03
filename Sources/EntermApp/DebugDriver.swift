import AppKit
import CoreGraphics
import EntermCore
import QuartzCore

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

    func capture(to path: String) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView, let layer = view.layer else { return }
        AppModel.shared.flushPending()
        let size = view.bounds.size
        let terminals = Self.terminals(in: view).filter { !$0.isHiddenOrHasHiddenAncestor }
        terminals.forEach { $0.isHidden = true }
        window.displayIfNeeded()
        guard let context = Self.context(size) else { return }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -size.height)
        terminals.forEach { $0.isHidden = false }
        window.displayIfNeeded()
        // Terminal views draw through draw(_:). Dialogs cover them, so they are only added without a cover.
        if AppModel.shared.overlay == nil, AppModel.shared.page == nil {
            for host in terminals {
                guard let picture = Self.picture(of: host) else { continue }
                let rect = host.convert(host.bounds, to: view)
                let y = view.isFlipped ? size.height - rect.maxY : rect.minY
                context.draw(picture, in: CGRect(x: rect.minX, y: y, width: rect.width, height: rect.height))
            }
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

    private static func terminals(in view: NSView) -> [TerminalHost] {
        var found: [TerminalHost] = []
        for child in view.subviews {
            if let host = child as? TerminalHost { found.append(host) } else { found += terminals(in: child) }
        }
        return found
    }
}
