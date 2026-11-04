import AppKit
import EntermCore
import SwiftUI

extension Color {
    init(_ color: NSColor) { self.init(nsColor: color) }
}

/// All text outside the terminal. Sizes come from the scale, never from a number here.
struct T: View {
    let text: String
    var color: NSColor?
    var bold = false
    var style = TextStyle.body
    var weight: Font.Weight?
    init(_ text: String, color: NSColor? = nil, bold: Bool = false, style: TextStyle = .body, weight: Font.Weight? = nil) {
        self.text = text
        self.color = color
        self.bold = bold
        self.style = style
        self.weight = weight
    }
    var body: some View {
        Text(text)
            .font(Theme.uiFont(style, weight: weight ?? (bold ? .semibold : .regular)))
            .monospacedDigit()
            .lineSpacing(style.line - NSFont.systemFont(ofSize: style.size).boundingRectForFont.height * 0.8)
            .foregroundColor(Color(color ?? Theme.palette.text1))
    }
}

struct Dim: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { T(text, color: Theme.palette.text2, style: .secondary) }
}

/// What a program wrote, or what will be typed into one.
struct Mono: View {
    let text: String
    var color: NSColor?
    init(_ text: String, color: NSColor? = nil) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text).font(Theme.swiftFont()).foregroundColor(Color(color ?? Theme.palette.text1))
    }
}

struct Key: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { T(text, color: Theme.palette.text3, style: .hint) }
}

enum BtnKind { case plain, outline, primary, danger, selected }

struct Btn: View {
    let title: String
    var kind: BtnKind = .outline
    var key: String?
    var icon: String?
    var action: () -> Void
    @State private var hovering = false
    init(_ title: String, kind: BtnKind = .outline, key: String? = nil, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.key = key
        self.icon = icon
        self.action = action
    }
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Symbol(icon, color: kind == .primary ? palette.btnfg : palette.text2) }
                Text(title)
                    .font(Theme.uiFont(.body, weight: weight))
                    .monospacedDigit()
                    .foregroundColor(Color(foreground))
                    .lineLimit(1)
                if let key {
                    Text(key)
                        .font(Theme.uiFont(.hint))
                        .foregroundColor(kind == .primary ? Color(palette.btnfg).opacity(0.7) : Color(palette.text3))
                }
            }
            .padding(.horizontal, kind == .plain ? 8 : 12)
            .frame(height: 28)
            .background(background)
            .cornerRadius(Theme.cornerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
    private var weight: Font.Weight {
        switch kind {
        case .primary: return .semibold
        case .danger, .selected: return .medium
        default: return .regular
        }
    }
    private var foreground: NSColor {
        switch kind {
        case .primary: return Theme.palette.btnfg
        case .danger: return Theme.palette.err
        default: return Theme.palette.text1
        }
    }
    private var background: Color {
        let palette = Theme.palette
        switch kind {
        case .primary: return Color(palette.btn)
        case .outline: return Color(palette.fill)
        case .plain: return hovering ? Color(palette.fill) : .clear
        case .danger: return Color(palette.err).opacity(0.16)
        case .selected: return Color(palette.fillSelected)
        }
    }
}

/// An SF Symbol at the two sizes the design uses.
struct Symbol: View {
    let name: String
    var color: NSColor
    var size: CGFloat
    init(_ name: String, color: NSColor = Theme.palette.text2, size: CGFloat = 16) {
        self.name = name
        self.color = color
        self.size = size
    }
    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.85, weight: .regular))
            .frame(width: size, height: size)
            .foregroundColor(Color(color))
    }
}

/// 28 square, no frame.
struct IconBtn: View {
    let icon: String
    let label: String
    var action: () -> Void
    @State private var hovering = false
    init(_ icon: String, label: String, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Symbol(icon, color: hovering ? Theme.palette.text1 : Theme.palette.text2)
                .frame(width: 28, height: 28)
                .background(hovering ? Color(Theme.palette.fill) : .clear)
                .cornerRadius(Theme.cornerControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

/// Segmented choice with the one selection style of the design.
struct Seg<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var value: Value
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option in
                let on = option.0 == value
                Button { value = option.0 } label: {
                    T(option.1, color: on ? palette.text1 : palette.text2, style: .secondary, weight: on ? .medium : .regular)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(on ? Color(palette.fillSelected) : .clear)
                        .cornerRadius(Theme.cornerControl)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(palette.fill))
        .cornerRadius(Theme.cornerCard)
    }
}

/// The look of one status, shared by the badge on a box and the one in lists.
struct StatusLook {
    let symbol: String
    let symbolColor: NSColor
    let textColor: NSColor
    let background: NSColor
    let strong: Bool

    init(_ status: SessionStatus) {
        let palette = Theme.palette
        switch status {
        case .starting, .idle:
            self.init(symbol: "circle", symbolColor: palette.text2, textColor: palette.text1, background: palette.fill, strong: false)
        case .running:
            self.init(symbol: "circle.fill", symbolColor: palette.add, textColor: palette.text1, background: palette.fill, strong: false)
        case .queued:
            self.init(symbol: "clock", symbolColor: palette.text2, textColor: palette.text1, background: palette.fill, strong: false)
        case .needsApproval:
            self.init(symbol: "diamond.fill", symbolColor: palette.need, textColor: palette.need, background: palette.need.withAlphaComponent(0.16), strong: true)
        case .limitReached:
            self.init(symbol: "square.fill", symbolColor: palette.limit, textColor: palette.limit, background: palette.limit.withAlphaComponent(0.16), strong: true)
        case .failed, .notFound:
            self.init(symbol: "xmark", symbolColor: palette.err, textColor: palette.err, background: palette.err.withAlphaComponent(0.16), strong: true)
        case .exited:
            self.init(symbol: "checkmark", symbolColor: palette.text2, textColor: palette.text2, background: palette.fill, strong: false)
        case .unknown:
            self.init(symbol: "circle", symbolColor: palette.text3, textColor: palette.text2, background: palette.fill, strong: false)
        }
    }

    private init(symbol: String, symbolColor: NSColor, textColor: NSColor, background: NSColor, strong: Bool) {
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.textColor = textColor
        self.background = background
        self.strong = strong
    }
}

struct StatusBadge: View {
    let status: SessionStatus
    var body: some View {
        let look = StatusLook(status)
        HStack(spacing: 6) {
            Symbol(look.symbol, color: look.symbolColor, size: 8)
            T(status.title, color: look.textColor, style: .secondary, weight: look.strong ? .semibold : .medium)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 20)
        .background(Color(look.background))
        .cornerRadius(Theme.cornerControl)
    }
}

private struct FloatingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Inside a dialog or a menu, panels float above the page.
    var floatingPanel: Bool {
        get { self[FloatingKey.self] }
        set { self[FloatingKey.self] = newValue }
    }
}

struct Panel<Content: View>: View {
    var border: NSColor?
    @ViewBuilder var content: () -> Content
    @Environment(\.floatingPanel) private var floating
    var body: some View {
        let palette = Theme.palette
        let radius = floating ? Theme.cornerFloat : Theme.cornerCard
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(Color(floating ? palette.surface2 : palette.surface1))
            .cornerRadius(radius)
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color(border ?? (floating ? palette.hair2 : palette.hair))))
            .shadow(color: floating ? Color(palette.shadowFloat) : .clear, radius: floating ? 12 : 0, y: floating ? 8 : 0)
    }
}

struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack {
            T(title, bold: true, style: .section)
            Spacer()
            trailing()
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(minHeight: 36)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        trailing = { EmptyView() }
    }
}

struct Row<Content: View>: View {
    var selected = false
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content
    var body: some View {
        let inner = HStack(spacing: 24, content: content)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? Color(Theme.palette.fillSelected) : .clear)
            .contentShape(Rectangle())
        if let action {
            Button(action: action) { inner }.buttonStyle(.plain)
        } else {
            inner
        }
    }
}

struct Line: View {
    var body: some View { Rectangle().fill(Color(Theme.palette.hair)).frame(height: 1) }
}

/// A full page with the same back bar everywhere.
struct PageFrame<Content: View>: View {
    var title: String?
    var wide = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        let palette = Theme.palette
        VStack(spacing: 0) {
            HStack {
                Btn("Geri", kind: .plain, key: "Esc", icon: "chevron.left") { AppModel.shared.page = nil }
                Spacer()
            }
            .padding(.leading, 80)
            .padding(.trailing, 16)
            .frame(height: 44)
            .background(Color(palette.surface1))
            Line()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let title { T(title, bold: true, style: .title) }
                    content()
                }
                .padding(.top, 32)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .frame(maxWidth: wide ? .infinity : 744, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(palette.surface0))
    }
}

struct Meter: View {
    let percent: Double
    var warn = false
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(Theme.palette.fill))
                Rectangle().fill(Color(warn ? Theme.palette.limit : Theme.palette.text1))
                    .frame(width: geometry.size.width * min(max(percent, 0), 100) / 100)
            }
        }
        .frame(height: 6)
        .cornerRadius(3)
    }
}

struct EntermField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        let palette = Theme.palette
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color(palette.text3)))
            .textFieldStyle(.plain)
            .font(Theme.uiFont(.body))
            .foregroundColor(Color(palette.text1))
            .focused($focused)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color(palette.terminal))
            .cornerRadius(Theme.cornerControl)
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerControl).stroke(Color(focused ? palette.focus : palette.hair2)))
    }
}

/// Features not built yet say so instead of pretending.
struct NotYet: View {
    let name: String
    var body: some View {
        PageFrame(title: name) {
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    T("Henüz Yok", bold: true)
                    Dim("Bu özellik bu sürümde çalışmıyor. Çalışıyormuş gibi göstermemek için burada duruyor.")
                }
                .padding(12)
            }
        }
    }
}
