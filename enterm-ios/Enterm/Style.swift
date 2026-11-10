import SwiftUI
import UIKit

/// The Mac's tokens (`tasarim/kabuk-olculeri.md`). The terminal has its own colours and stays dark in both themes.
enum Palette {
    static let surface0 = pair(0x0B0E0F, 0xE4E3DC), surface1 = pair(0x14181A, 0xF4F3EE), surface2 = pair(0x1C2123, 0xFFFFFF)
    static let text1 = pair(0xECEFEC, 0x161C1A), text2 = pair(0xAEB7B3, 0x4C5652), text3 = pair(0x858F8B, 0x5C6662)
    static let hair = alpha(0.08, 0.10), hair2 = alpha(0.16, 0.18), fill = alpha(0.07, 0.05), fillSelected = alpha(0.14, 0.10)
    static let need = pair(0xD8EE4E, 0x556300), limit = pair(0xF2A552, 0x9C4E08), err = pair(0xF47F78, 0xAE241C), add = pair(0x86D19A, 0x1B7038)
    static let btn = Color(hex: 0xD8EE4E), btnfg = Color(hex: 0x10140A)
    /// Fields follow the theme. Only what a program wrote stays on the terminal's own ground.
    static let field = pair(0x07090A, 0xECEBE4)
    static let terminal = Color(hex: 0x000000), terminalText = Color(hex: 0xE7EBE6)

    // The names the screens were written with.
    static var bg: Color { surface0 }
    static var panel: Color { surface1 }
    static var raise: Color { surface2 }
    static var line: Color { hair }
    static var line2: Color { hair2 }
    static var fg: Color { text1 }
    static var dim: Color { text2 }

    /// One colour around the terminal and under it: SwiftTerm's iOS renderer draws its cells on black.
    static func terminalBackground(dark: Bool) -> UIColor { uiColor(0x000000) }
    static func terminalForeground(dark: Bool) -> UIColor { uiColor(0xE7EBE6) }

    private static func pair(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? uiColor(light) : uiColor(dark) })
    }

    private static func alpha(_ dark: CGFloat, _ light: CGFloat) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(white: 0, alpha: light) : UIColor(white: 1, alpha: dark) })
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
    /// Only for what a program wrote or what will be typed into one.
    static let mono = Font.system(.footnote, design: .monospaced)
    static let monoBold = Font.system(.footnote, design: .monospaced).weight(.semibold)
    static let monoLarge = Font.system(.largeTitle, design: .monospaced).weight(.semibold)
}

/// All text outside the terminal. Sizes come from the iOS styles, so they follow the system setting.
struct Txt: View {
    let text: String
    var color = Palette.text1
    var bold = false
    var style: Font.TextStyle
    var weight: Font.Weight?
    init(_ text: String, color: Color = Palette.text1, bold: Bool = false, style: Font.TextStyle? = nil, weight: Font.Weight? = nil) {
        self.text = text
        self.color = color
        self.bold = bold
        self.style = style ?? (bold ? .headline : .body)
        self.weight = weight
    }
    var body: some View {
        Text(text)
            .font(.system(style).weight(weight ?? (bold ? .semibold : .regular)))
            .monospacedDigit()
            .foregroundColor(color)
    }
}

struct DimTxt: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Txt(text, color: Palette.text2, style: .subheadline) }
}

enum ActionStyle { case primary, outline, plain }

/// Every touch target is at least 44 points tall and grows with the text.
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
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(style == .primary ? Palette.btnfg : Palette.text1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(style == .primary ? Palette.btn : (style == .outline ? Palette.fill : Color.clear))
                .cornerRadius(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Two buttons side by side; under large text one above the other, the main one first.
struct ButtonPair<Secondary: View, Main: View>: View {
    @Environment(\.dynamicTypeSize) private var size
    @ViewBuilder let secondary: () -> Secondary
    @ViewBuilder let main: () -> Main
    var body: some View {
        if size.isAccessibilitySize {
            VStack(spacing: 8) {
                main()
                secondary()
            }
        } else {
            HStack(spacing: 8) {
                secondary()
                main()
            }
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface1)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hair))
            .cornerRadius(12)
    }
}

struct ScreenTitle: View {
    let text: String
    var body: some View {
        Txt(text, style: .title3, weight: .semibold)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 16)
    }
}

/// The back control used everywhere: a symbol and where it leads.
struct BackLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left").font(.body.weight(.semibold))
            Text(title).font(.body).lineLimit(1)
        }
        .foregroundColor(Palette.text1)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

extension Date {
    /// Dates follow the app's language, not the phone's.
    func turkish(date: Date.FormatStyle.DateStyle = .abbreviated, time: Date.FormatStyle.TimeStyle = .shortened) -> String {
        formatted(Date.FormatStyle(date: date, time: time, locale: Locale(identifier: "tr_TR")))
    }
}
