import AppKit
import SwiftUI

/// The tokens of `tasarim/kabuk-olculeri.md`. The terminal keeps its own two colours.
struct Palette {
    let terminal, terminalText: NSColor
    let surface0, surface1, surface2, surface3: NSColor
    let text1, text2, text3: NSColor
    let hair, hair2, focus, fill, fillSelected, knob: NSColor
    var need: NSColor
    let limit, err, add: NSColor
    var btn: NSColor
    let btnfg, g1, g2: NSColor
    let scrim: NSColor
    let shadowBox, shadowFloat: NSColor

    static let dark = Palette(
        terminal: .hex(0x07090A), terminalText: .hex(0xE7EBE6),
        surface0: .hex(0x0B0E0F), surface1: .hex(0x14181A), surface2: .hex(0x1C2123), surface3: .hex(0x262C2E),
        text1: .hex(0xECEFEC), text2: .hex(0xAEB7B3), text3: .hex(0x858F8B),
        hair: .white(0.08), hair2: .white(0.16), focus: .white(0.40), fill: .white(0.07), fillSelected: .white(0.14), knob: .white(0.28),
        need: .hex(0xD8EE4E), limit: .hex(0xF2A552), err: .hex(0xF47F78), add: .hex(0x86D19A),
        btn: .hex(0xD8EE4E), btnfg: .hex(0x10140A), g1: .hex(0x7FA6FF), g2: .hex(0xB79CFF),
        scrim: NSColor(srgbRed: 3 / 255, green: 5 / 255, blue: 5 / 255, alpha: 0.60),
        shadowBox: NSColor.black.withAlphaComponent(0.35), shadowFloat: NSColor.black.withAlphaComponent(0.45))

    static let light = Palette(
        terminal: .hex(0xECEBE4), terminalText: .hex(0x161C1A),
        surface0: .hex(0xE4E3DC), surface1: .hex(0xF4F3EE), surface2: .hex(0xFFFFFF), surface3: .hex(0xE9E8E1),
        text1: .hex(0x161C1A), text2: .hex(0x4C5652), text3: .hex(0x5C6662),
        hair: .black(0.10), hair2: .black(0.18), focus: .black(0.45), fill: .black(0.05), fillSelected: .black(0.10), knob: .black(0.28),
        need: .hex(0x556300), limit: .hex(0x9C4E08), err: .hex(0xAE241C), add: .hex(0x1B7038),
        btn: .hex(0xD8EE4E), btnfg: .hex(0x10140A), g1: .hex(0x2C57C4), g2: .hex(0x6A45C4),
        scrim: NSColor(srgbRed: 60 / 255, green: 62 / 255, blue: 50 / 255, alpha: 0.35),
        shadowBox: NSColor(srgbRed: 40 / 255, green: 44 / 255, blue: 30 / 255, alpha: 0.12),
        shadowFloat: NSColor(srgbRed: 40 / 255, green: 44 / 255, blue: 30 / 255, alpha: 0.16))

    // The names most pages were written with.
    var fg: NSColor { text1 }
    var dim: NSColor { text2 }
    var line: NSColor { hair }
    var line2: NSColor { hair2 }
    var panel: NSColor { surface1 }
    var raise: NSColor { surface2 }
}

/// The only text sizes outside the terminal.
enum TextStyle {
    case title, section, body, secondary, hint

    var size: CGFloat {
        switch self {
        case .title: return 26
        case .section: return 15
        case .body: return 13
        case .secondary: return 12
        case .hint: return 11
        }
    }
    var line: CGFloat {
        switch self {
        case .title: return 32
        case .section: return 20
        case .body: return 18
        case .secondary: return 16
        case .hint: return 14
        }
    }
}

enum Theme {
    static var isLight = false { didSet { refreshPalette() } }
    /// Read many times a frame, so it is kept ready and rebuilt only when the look changes.
    private(set) static var palette: Palette = .dark

    static func refreshPalette() {
        var result: Palette = isLight ? .light : .dark
        if let accent = AccentChoice.all.first(where: { $0.id == SettingsStore.shared.settings.accent }), accent.id != "lime" {
            result.need = .hex(isLight ? accent.light : accent.dark)
            result.btn = .hex(accent.dark)
        }
        palette = result
    }
    static let fontSize: CGFloat = 13.333
    static let lineHeight: CGFloat = 20

    /// Terminal and commands only: what a program wrote or what will be typed into one.
    static func font(size: CGFloat = fontSize, bold: Bool = false) -> NSFont {
        let family = SettingsStore.shared.settings.fontName
        if !family.isEmpty, let font = NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size) { return font }
        let name = bold ? "JetBrainsMono-SemiBold" : "JetBrainsMono-Regular"
        if let font = NSFont(name: name, size: size) { return font }
        return NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }
    static func swiftFont(bold: Bool = false, size: CGFloat = fontSize) -> Font {
        Font(font(size: size, bold: bold))
    }
    /// Everything else.
    static func ui(_ style: TextStyle = .body, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: style.size, weight: weight)
    }
    static func uiFont(_ style: TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        Font.system(size: style.size, weight: weight)
    }
    static let cornerControl: CGFloat = 6
    static let cornerCard: CGFloat = 8
    static let cornerFloat: CGFloat = 12
}

extension NSColor {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }
    static func white(_ alpha: CGFloat) -> NSColor { NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }
    static func black(_ alpha: CGFloat) -> NSColor { NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha) }
}

extension NSAttributedString {
    static func enterm(_ text: String, color: NSColor? = nil, bold: Bool = false, size: CGFloat = Theme.fontSize) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Theme.font(size: size, bold: bold),
            .foregroundColor: color ?? Theme.palette.fg,
        ])
    }
}
