import AppKit

// Draws the app icon: the terminal prompt on the dark surface of the design.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func draw(_ px: Int, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    NSColor(srgbRed: 0x10 / 255, green: 0x15 / 255, blue: 0x14 / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18).fill()
    NSColor(srgbRed: 0x4A / 255, green: 0x57 / 255, blue: 0x53 / 255, alpha: 1).setStroke()
    let border = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    border.lineWidth = max(1, s * 0.006)
    border.stroke()
    let accent = NSColor(srgbRed: 0xD8 / 255, green: 0xEE / 255, blue: 0x4E / 255, alpha: 1)
    accent.setStroke()
    let chevron = NSBezierPath()
    chevron.lineWidth = s * 0.07
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.move(to: NSPoint(x: s * 0.29, y: s * 0.67))
    chevron.line(to: NSPoint(x: s * 0.47, y: s * 0.5))
    chevron.line(to: NSPoint(x: s * 0.29, y: s * 0.33))
    chevron.stroke()
    NSColor(srgbRed: 0xE7 / 255, green: 0xEB / 255, blue: 0xE6 / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.52, y: s * 0.29, width: s * 0.2, height: s * 0.07), xRadius: s * 0.02, yRadius: s * 0.02).fill()
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
for (px, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"),
                   (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
    draw(px, name)
}
