import AppKit
import CoreGraphics
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
        window.displayIfNeeded()
        let scale: CGFloat = 1
        let size = view.bounds.size
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        // Terminal views draw through draw(_:), so they are composed on top of the layer picture.
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -size.height)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphics
        for host in Self.terminals(in: view) where !host.isHiddenOrHasHiddenAncestor {
            let rect = host.convert(host.bounds, to: view)
            let y = view.isFlipped ? size.height - rect.maxY : rect.minY
            let target = NSRect(x: rect.minX, y: y, width: rect.width, height: rect.height)
            context.setFillColor(host.nativeBackgroundColor.cgColor)
            context.fill(target)
            context.saveGState()
            context.translateBy(x: target.minX, y: target.minY)
            context.clip(to: CGRect(origin: .zero, size: target.size))
            host.displayIgnoringOpacity(host.bounds, in: graphics)
            context.restoreGState()
        }
        NSGraphicsContext.current = nil
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func terminals(in view: NSView) -> [TerminalHost] {
        var found: [TerminalHost] = []
        for child in view.subviews {
            if let host = child as? TerminalHost { found.append(host) } else { found += terminals(in: child) }
        }
        return found
    }
}
