import AppKit
import EntermCore
import SwiftTerm
import SwiftUI

/// The colours of the terminal itself. Everything around the terminal stays in the app's palette.
struct TerminalTheme: Identifiable, Equatable {
    let id: String
    let title: String
    let background: UInt32
    let foreground: UInt32
    let ansi: [UInt32]

    var isLight: Bool { TerminalTheme.luminance(background) > 0.5 }

    private static func luminance(_ value: UInt32) -> Double {
        let r = Double((value >> 16) & 0xff) / 255, g = Double((value >> 8) & 0xff) / 255, b = Double(value & 0xff) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    var backgroundColor: NSColor { .hex(background) }
    var foregroundColor: NSColor { .hex(foreground) }

    /// SwiftTerm's colours are 16 bit per channel.
    var swiftTermColors: [SwiftTerm.Color] {
        ansi.map { value in
            SwiftTerm.Color(red: UInt16((value >> 16) & 0xff) * 257, green: UInt16((value >> 8) & 0xff) * 257, blue: UInt16(value & 0xff) * 257)
        }
    }

    static let enterm = TerminalTheme(
        id: "enterm", title: "Enterm", background: 0x07090A, foreground: 0xE7EBE6,
        ansi: [0x14181A, 0xF47F78, 0x86D19A, 0xD8EE4E, 0x7FA6FF, 0xB79CFF, 0x6FD3C7, 0xE7EBE6,
               0x5B6663, 0xFF9C96, 0xA6E8B6, 0xE8FA74, 0xA3C0FF, 0xCDB9FF, 0x97E8DE, 0xFFFFFF])
    static let entermLight = TerminalTheme(
        id: "entermLight", title: "Enterm Açık", background: 0xECEBE4, foreground: 0x161C1A,
        ansi: [0x161C1A, 0xAE241C, 0x1B7038, 0x6E6A00, 0x2C57C4, 0x6A45C4, 0x0F6E6E, 0xC9C8C0,
               0x5C6662, 0xC8392F, 0x24884A, 0x857F00, 0x3C6BDB, 0x7F5AD8, 0x138585, 0xFFFFFF])

    static let all: [TerminalTheme] = [
        enterm,
        TerminalTheme(id: "dracula", title: "Dracula", background: 0x282A36, foreground: 0xF8F8F2,
                      ansi: [0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
                             0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5, 0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF]),
        TerminalTheme(id: "tokyo", title: "Tokyo Night", background: 0x1A1B26, foreground: 0xC0CAF5,
                      ansi: [0x15161E, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xA9B1D6,
                             0x414868, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xC0CAF5]),
        TerminalTheme(id: "catppuccin", title: "Catppuccin Mocha", background: 0x1E1E2E, foreground: 0xCDD6F4,
                      ansi: [0x45475A, 0xF38BA8, 0xA6E3A1, 0xF9E2AF, 0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xBAC2DE,
                             0x585B70, 0xF38BA8, 0xA6E3A1, 0xF9E2AF, 0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xA6ADC8]),
        TerminalTheme(id: "gruvbox", title: "Gruvbox", background: 0x282828, foreground: 0xEBDBB2,
                      ansi: [0x282828, 0xCC241D, 0x98971A, 0xD79921, 0x458588, 0xB16286, 0x689D6A, 0xA89984,
                             0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F, 0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2]),
        TerminalTheme(id: "nord", title: "Nord", background: 0x2E3440, foreground: 0xD8DEE9,
                      ansi: [0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
                             0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4]),
        TerminalTheme(id: "onedark", title: "One Dark", background: 0x282C34, foreground: 0xABB2BF,
                      ansi: [0x282C34, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF,
                             0x5C6370, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xFFFFFF]),
        TerminalTheme(id: "solarized", title: "Solarized Koyu", background: 0x002B36, foreground: 0x839496,
                      ansi: [0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
                             0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3]),
        TerminalTheme(id: "solarizedLight", title: "Solarized Açık", background: 0xFDF6E3, foreground: 0x657B83,
                      ansi: [0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
                             0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3]),
        entermLight,
    ]

    /// The chosen theme. The default follows the app's light or dark look.
    static var current: TerminalTheme {
        let id = SettingsStore.shared.settings.terminalTheme
        if id == "enterm" { return Theme.isLight ? entermLight : enterm }
        return all.first { $0.id == id } ?? enterm
    }
}

/// The colour that carries the app: the main button, the prompt, whatever waits for the person.
struct AccentChoice: Identifiable {
    let id: String
    let title: String
    let dark: UInt32
    let light: UInt32

    static let all = [
        AccentChoice(id: "lime", title: "Limon", dark: 0xD8EE4E, light: 0x556300),
        AccentChoice(id: "mint", title: "Nane", dark: 0x6FF0C2, light: 0x0F6E52),
        AccentChoice(id: "sky", title: "Gök", dark: 0x7FD0FF, light: 0x0B5F8A),
        AccentChoice(id: "violet", title: "Mor", dark: 0xC3A6FF, light: 0x5B35B0),
        AccentChoice(id: "rose", title: "Gül", dark: 0xFF8FC7, light: 0xA3195F),
    ]
}

/// What sits behind the boxes. Drawn once for the canvas size and only redrawn with it.
struct Wallpaper: Identifiable {
    let id: String
    let title: String
    let colors: [UInt32]

    static let all = [
        Wallpaper(id: "none", title: "Yok", colors: []),
        Wallpaper(id: "gece", title: "Gece", colors: [0x0B1020, 0x101A36, 0x1C1436]),
        Wallpaper(id: "orman", title: "Orman", colors: [0x07140F, 0x0E2A20, 0x13382A]),
        Wallpaper(id: "kor", title: "Kor", colors: [0x140A08, 0x2A120C, 0x3B1A0E]),
        Wallpaper(id: "derin", title: "Derin", colors: [0x04141C, 0x08303F, 0x0C4453]),
        Wallpaper(id: "erik", title: "Erik", colors: [0x12071C, 0x24103A, 0x3A1646]),
        Wallpaper(id: "limon", title: "Limon", colors: [0x0D1006, 0x1F2A0A, 0x34400C]),
    ]

    private static var cachedPath: String?
    private static var cachedImage: NSImage?

    /// Fills the rect. A chosen picture covers it, the way a desktop picture does.
    static func draw(in rect: NSRect, bounds: NSRect) -> Bool {
        let id = SettingsStore.shared.settings.wallpaper
        if id == "none" { return false }
        if id.hasPrefix("file:") {
            let path = String(id.dropFirst(5))
            if cachedPath != path {
                cachedPath = path
                cachedImage = NSImage(contentsOfFile: path)
            }
            guard let image = cachedImage, image.size.width > 0, image.size.height > 0 else { return false }
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let target = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        guard let wallpaper = all.first(where: { $0.id == id }), wallpaper.colors.count > 1 else { return false }
        NSGradient(colors: wallpaper.colors.map { NSColor.hex($0) })?.draw(in: bounds, angle: 60)
        return true
    }
}

/// A small pop-up list that looks like the rest of the controls.
struct ChoiceMenu<Value: Hashable>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let options: [(Value, String)]
    @Binding var value: Value
    var body: some View {
        let palette = Theme.palette
        Menu {
            ForEach(options, id: \.0) { option in
                Button(option.1) { value = option.0 }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.0 == value }?.1 ?? "").font(Theme.uiFont(.body)).foregroundColor(Color(palette.text1)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundColor(Color(palette.text3))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(palette.fill))
        .cornerRadius(Theme.cornerControl)
    }
}
