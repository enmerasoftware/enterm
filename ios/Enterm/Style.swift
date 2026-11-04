import SwiftUI
import UIKit

/// The tokens of `tasarim/tum-ekranlar/enterm.css`, both palettes. One family, one size.
enum Palette {
    static let bg = pair(0x07090A, 0xECEBE4), panel = pair(0x101514, 0xFBFAF6), raise = pair(0x1A2221, 0xE4E3DA)
    static let line = pair(0x28312F, 0xCFCEC3), line2 = pair(0x4A5753, 0x8F9188), fg = pair(0xE7EBE6, 0x161C1A), dim = pair(0xA2ADA8, 0x505B57)
    static let need = pair(0xD8EE4E, 0x556300), limit = pair(0xF2A552, 0x9C4E08), err = pair(0xF47F78, 0xAE241C), add = pair(0x86D19A, 0x1B7038)
    static let btn = Color(hex: 0xD8EE4E), btnfg = Color(hex: 0x10140A)

    static func terminalBackground(dark: Bool) -> UIColor { uiColor(dark ? 0x07090A : 0xECEBE4) }
    static func terminalForeground(dark: Bool) -> UIColor { uiColor(dark ? 0xE7EBE6 : 0x161C1A) }

    private static func pair(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? uiColor(light) : uiColor(dark) })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

extension Font {
    static let mono = Font.system(size: 14, design: .monospaced)
    static let monoBold = Font.system(size: 14, weight: .semibold, design: .monospaced)
    static let monoLarge = Font.system(size: 36, weight: .semibold, design: .monospaced)
}

struct Txt: View {
    let text: String
    var color = Palette.fg
    var bold = false
    init(_ text: String, color: Color = Palette.fg, bold: Bool = false) {
        self.text = text
        self.color = color
        self.bold = bold
    }
    var body: some View { Text(text).font(bold ? .monoBold : .mono).foregroundColor(color) }
}

struct DimTxt: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Txt(text, color: Palette.dim) }
}

enum ActionStyle { case primary, outline, plain }

/// Every touch target is at least 44 points tall.
struct ActionButton: View {
    let title: String
    var style = ActionStyle.outline
    let action: () -> Void
    init(_ title: String, style: ActionStyle = .outline, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.monoBold)
                .foregroundColor(style == .primary ? Palette.btnfg : Palette.fg)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(style == .primary ? Palette.btn : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(style == .outline ? Palette.line2 : Color.clear))
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line2))
            .cornerRadius(6)
    }
}

struct ScreenTitle: View {
    let text: String
    var body: some View {
        Txt(text, bold: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 16)
    }
}

extension Date {
    /// Dates follow the app's language, not the phone's.
    func turkish(date: Date.FormatStyle.DateStyle = .abbreviated, time: Date.FormatStyle.TimeStyle = .shortened) -> String {
        formatted(Date.FormatStyle(date: date, time: time, locale: Locale(identifier: "tr_TR")))
    }
}
