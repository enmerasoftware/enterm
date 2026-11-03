import AppKit
import SwiftUI

/// The design tokens from `tasarim/tum-ekranlar/enterm.css`. One family, one size, one badge style.
struct Palette {
    let bg, panel, raise, line, line2, fg, dim, need, limit, err, add, btn, btnfg, btnline, g1, g2: NSColor
    let scrim: NSColor

    static let dark = Palette(
        bg: .hex(0x07090A), panel: .hex(0x101514), raise: .hex(0x1A2221), line: .hex(0x28312F), line2: .hex(0x4A5753),
        fg: .hex(0xE7EBE6), dim: .hex(0xA2ADA8), need: .hex(0xD8EE4E), limit: .hex(0xF2A552), err: .hex(0xF47F78),
        add: .hex(0x86D19A), btn: .hex(0xD8EE4E), btnfg: .hex(0x10140A), btnline: .hex(0xD8EE4E), g1: .hex(0x7FA6FF),
        g2: .hex(0xB79CFF), scrim: NSColor(srgbRed: 3 / 255, green: 5 / 255, blue: 5 / 255, alpha: 0.72))

    static let light = Palette(
        bg: .hex(0xECEBE4), panel: .hex(0xFBFAF6), raise: .hex(0xE4E3DA), line: .hex(0xCFCEC3), line2: .hex(0x8F9188),
        fg: .hex(0x161C1A), dim: .hex(0x505B57), need: .hex(0x556300), limit: .hex(0x9C4E08), err: .hex(0xAE241C),
        add: .hex(0x1B7038), btn: .hex(0xD8EE4E), btnfg: .hex(0x10140A), btnline: .hex(0x6F7D12), g1: .hex(0x2C57C4),
        g2: .hex(0x6A45C4), scrim: NSColor(srgbRed: 60 / 255, green: 62 / 255, blue: 50 / 255, alpha: 0.45))
}

enum Theme {
    static var isLight = false
    static var palette: Palette { isLight ? .light : .dark }
    static let fontSize: CGFloat = 13.333
    static let lineHeight: CGFloat = 20

    static func font(size: CGFloat = fontSize, bold: Bool = false) -> NSFont {
        let name = bold ? "JetBrainsMono-SemiBold" : "JetBrainsMono-Regular"
        if let font = NSFont(name: name, size: size) { return font }
        return NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }
    static func swiftFont(bold: Bool = false, size: CGFloat = fontSize) -> Font {
        Font(font(size: size, bold: bold))
    }
}

extension NSColor {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }
}

extension NSAttributedString {
    static func enterm(_ text: String, color: NSColor? = nil, bold: Bool = false, size: CGFloat = Theme.fontSize) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Theme.font(size: size, bold: bold),
            .foregroundColor: color ?? Theme.palette.fg,
        ])
    }
}
