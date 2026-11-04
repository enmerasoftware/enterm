import SwiftUI
import UIKit

/// The tokens of `tasarim/tum-ekranlar/enterm.css`, dark palette. One family, one size.
enum Palette {
    static let bg = Color(hex: 0x07090A), panel = Color(hex: 0x101514), raise = Color(hex: 0x1A2221)
    static let line = Color(hex: 0x28312F), line2 = Color(hex: 0x4A5753), fg = Color(hex: 0xE7EBE6), dim = Color(hex: 0xA2ADA8)
    static let need = Color(hex: 0xD8EE4E), limit = Color(hex: 0xF2A552), err = Color(hex: 0xF47F78), add = Color(hex: 0x86D19A)
    static let btn = Color(hex: 0xD8EE4E), btnfg = Color(hex: 0x10140A)
    static let terminalBackground = UIColor(red: 0x07 / 255, green: 0x09 / 255, blue: 0x0A / 255, alpha: 1)
    static let terminalForeground = UIColor(red: 0xE7 / 255, green: 0xEB / 255, blue: 0xE6 / 255, alpha: 1)
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
