import AppKit
import EntermCore
import SwiftUI

extension Color {
    init(_ color: NSColor) { self.init(nsColor: color) }
}

/// Every clickable thing in the app: plain to look at, a hand under the pointer so it reads as clickable.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct PressBody<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            label
                .opacity(enabled ? (pressed ? 0.8 : 1) : 0.45)
                .handCursor(enabled)
        }
    }
}

extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
}

extension View {
    /// The pointing hand while the pointer is over this view.
    @ViewBuilder
    func handCursor(_ on: Bool = true) -> some View {
        if !on {
            self
        } else if #available(macOS 15, *) {
            pointerStyle(.link)
        } else {
            onContinuousHover { phase in
                switch phase {
                case .active: NSCursor.pointingHand.set()
                case .ended: NSCursor.arrow.set()
                }
            }
        }
    }
}

/// All text outside the terminal. Sizes come from the scale, never from a number here.
struct T: View {
    @ObservedObject private var appearance = AppearanceTick.shared
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
    @ObservedObject private var appearance = AppearanceTick.shared
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { T(text, color: Theme.palette.text2, style: .secondary) }
}

/// What a program wrote, or what will be typed into one.
struct Mono: View {
    @ObservedObject private var appearance = AppearanceTick.shared
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
    @ObservedObject private var appearance = AppearanceTick.shared
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { T(Self.label(text), color: Theme.palette.text3, style: .hint) }

    /// A letter key is written the way it is printed on the keyboard.
    static func label(_ text: String) -> String {
        text.count == 1 ? text.uppercased(with: Locale(identifier: "en_US_POSIX")) : text
    }
}

/// A command to read in full before it runs: it wraps, it never gets cut.
struct CommandBox: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let text: String
    var body: some View {
        // Centered, so the button stands as far from the top and the bottom as from the right.
        HStack(alignment: .center, spacing: 12) {
            Mono(text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Btn("Kopyala", kind: .plain) { NotFoundActions.copy(text) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Theme.palette.terminal))
        .cornerRadius(Theme.cornerControl)
    }
}

/// A long request stays short until asked. Nothing in it is hidden without saying so.
struct ApprovalCommand: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let text: String
    var lines = 6
    @State private var expanded = false
    private var isLong: Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).count > lines || text.count > lines * 60
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Mono(text)
                .textSelection(.enabled)
                .lineLimit(expanded ? nil : lines)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(Theme.palette.terminal))
                .cornerRadius(Theme.cornerControl)
            if isLong, !expanded {
                Btn("Tamamını Gör", kind: .plain) { expanded = true }
            }
        }
    }
}

/// The row at the foot of a dialog. The main action is the last one, on the right.
/// A short note may stand on the left, at the same 20 as the dialog's text.
struct DialogButtons<Content: View>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    var note: String?
    @ViewBuilder var content: () -> Content
    init(note: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.note = note
        self.content = content
    }
    var body: some View {
        HStack(spacing: 8) {
            if let note { Dim(note).lineLimit(1) }
            Spacer(minLength: 0)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(Theme.palette.surface1))
        .overlay(alignment: .top) { Line() }
    }
}

extension View {
    /// A row inside a settings group.
    func settingsRow() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .overlay(alignment: .top) { Line() }
    }
}

/// `lit`: a switch that is on, such as an open side panel. It wears the accent so the open state reads at a glance.
enum BtnKind { case plain, outline, primary, danger, selected, lit }

struct Btn: View {
    @ObservedObject private var appearance = AppearanceTick.shared
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
                if let icon { Symbol(icon, color: kind == .primary ? palette.btnfg : (kind == .lit ? palette.need : palette.text2)) }
                Text(title)
                    .font(Theme.uiFont(.body, weight: weight))
                    .monospacedDigit()
                    .foregroundColor(Color(foreground))
                    .lineLimit(1)
                if let key {
                    Text(Key.label(key))
                        .font(Theme.uiFont(.hint))
                        .foregroundColor(kind == .primary ? Color(palette.btnfg).opacity(0.7) : Color(palette.text3))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(background)
            .cornerRadius(Theme.cornerControl)
            .overlay {
                // A quiet edge, so a plain button still shows where it can be clicked.
                if kind == .plain {
                    RoundedRectangle(cornerRadius: Theme.cornerControl)
                        .strokeBorder(Color(hovering ? palette.focus.withAlphaComponent(0.35) : palette.hair2), lineWidth: 1)
                } else if kind == .lit {
                    RoundedRectangle(cornerRadius: Theme.cornerControl)
                        .strokeBorder(Color(palette.need).opacity(0.5), lineWidth: 1)
                }
            }
            .shadow(color: kind == .primary && Neon.on ? Color(palette.btn).opacity(hovering ? 0.45 : 0.28) : .clear, radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
        // A button's name is never cut: the space around it gives way first.
        .fixedSize()
    }
    private var weight: Font.Weight {
        switch kind {
        case .primary: return .semibold
        case .danger, .selected, .lit: return .medium
        default: return .regular
        }
    }
    private var foreground: NSColor {
        switch kind {
        case .primary: return Theme.palette.btnfg
        case .danger: return Theme.palette.err
        case .lit: return Theme.palette.need
        default: return Theme.palette.text1
        }
    }
    private var background: Color {
        let palette = Theme.palette
        switch kind {
        case .primary: return Color(palette.btn)
        case .outline: return hovering ? Color(palette.fillSelected) : Color(palette.fill)
        case .plain: return hovering ? Color(palette.fill) : .clear
        case .danger: return Color(palette.err).opacity(0.16)
        case .selected: return Color(palette.fillSelected)
        case .lit: return Color(palette.need).opacity(hovering ? 0.22 : 0.14)
        }
    }
}

/// An SF Symbol at the two sizes the design uses.
struct Symbol: View {
    @ObservedObject private var appearance = AppearanceTick.shared
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

/// 30 square, no frame: the height of every other control, so it can stand beside a Btn or a field.
struct IconBtn: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let icon: String
    let label: String
    /// What the button opens is open now: it wears the accent, like `BtnKind.lit`.
    var active: Bool
    var action: () -> Void
    @State private var hovering = false
    init(_ icon: String, label: String, active: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.active = active
        self.action = action
    }
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            Symbol(icon, color: active ? palette.need : (hovering ? palette.text1 : palette.text2))
                .frame(width: 30, height: 30)
                .background(active ? Color(palette.need).opacity(hovering ? 0.22 : 0.14) : (hovering ? Color(palette.fill) : .clear))
                .cornerRadius(Theme.cornerControl)
                .overlay {
                    if active { RoundedRectangle(cornerRadius: Theme.cornerControl).strokeBorder(Color(palette.need).opacity(0.5), lineWidth: 1) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

/// Segmented choice with the one selection style of the design.
struct Seg<Value: Hashable>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let options: [(Value, String)]
    @Binding var value: Value
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option in
                SegOption(title: option.1, on: option.0 == value) { value = option.0 }
            }
        }
        .padding(2)
        .background(Color(palette.fill))
        .cornerRadius(Theme.cornerCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).strokeBorder(Color(palette.hair2), lineWidth: 1))
    }
}

/// `Seg` for more choices than one line holds: the same look, in as many rows as the width needs. No name is cut.
struct WrapChoice<Value: Hashable>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let options: [(Value, String)]
    let selected: Value?
    let choose: (Value) -> Void
    var body: some View {
        let palette = Theme.palette
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 2)], alignment: .leading, spacing: 2) {
            ForEach(options, id: \.0) { option in
                SegOption(title: option.1, on: option.0 == selected, fill: true) { choose(option.0) }
            }
        }
        .padding(2)
        .background(Color(palette.fill))
        .cornerRadius(Theme.cornerCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).strokeBorder(Color(palette.hair2), lineWidth: 1))
    }
}

/// One choice of `Seg` or `WrapChoice`. 26 tall, so the group is 30 like a button beside it.
private struct SegOption: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let title: String
    let on: Bool
    var fill = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            T(title, color: on || hovering ? palette.text1 : palette.text2, style: .secondary, weight: on ? .medium : .regular)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(maxWidth: fill ? .infinity : nil)
                .frame(height: 26)
                .background(on ? Color(palette.fillSelected) : (hovering ? Color(palette.fill) : .clear))
                .cornerRadius(Theme.cornerControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

/// A number with − and + beside it, drawn like `Seg` so the two stand at the same height in one row.
struct NumberStepper: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let value: Int
    var minimum = Int.min
    var maximum = Int.max
    let change: (Int) -> Void
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 2) {
            StepKey(symbol: "minus", enabled: value > minimum) { change(value - 1) }
            T("\(value)", style: .secondary, weight: .medium)
                .monospacedDigit()
                .frame(minWidth: 28)
            StepKey(symbol: "plus", enabled: value < maximum) { change(value + 1) }
        }
        .padding(2)
        .background(Color(palette.fill))
        .cornerRadius(Theme.cornerCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).strokeBorder(Color(palette.hair2), lineWidth: 1))
    }
}

private struct StepKey: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            Symbol(symbol, color: enabled ? palette.text1 : palette.text3, size: 10)
                .frame(width: 26, height: 26)
                .background(hovering && enabled ? Color(palette.fillSelected) : .clear)
                .cornerRadius(Theme.cornerControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .disabled(!enabled)
        .onHover { hovering = $0 }
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
            self.init(symbol: "circle.fill", symbolColor: palette.g1, textColor: palette.text1, background: palette.fill, strong: false)
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
    @ObservedObject private var appearance = AppearanceTick.shared
    let status: SessionStatus
    var body: some View {
        let look = StatusLook(status)
        HStack(spacing: 6) {
            Symbol(look.symbol, color: look.symbolColor, size: 8)
            T(status.title, color: look.textColor, style: .secondary, weight: look.strong ? .semibold : .medium)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Color(look.background))
        .cornerRadius(Theme.cornerControl)
    }
}

private struct FloatingKey: EnvironmentKey {
    static let defaultValue = false
}

private struct EmbeddedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct BoxedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Inside the settings a page brings only its content: the settings have their own back bar and scroll.
    var embeddedPage: Bool {
        get { self[EmbeddedKey.self] }
        set { self[EmbeddedKey.self] = newValue }
    }
    /// Inside a box on the canvas, where a page has very little room.
    var boxedPage: Bool {
        get { self[BoxedKey.self] }
        set { self[BoxedKey.self] = newValue }
    }
    /// Inside a dialog or a menu, panels float above the page.
    var floatingPanel: Bool {
        get { self[FloatingKey.self] }
        set { self[FloatingKey.self] = newValue }
    }
}

struct Panel<Content: View>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    var border: NSColor?
    @ViewBuilder var content: () -> Content
    @Environment(\.floatingPanel) private var floating
    var body: some View {
        let palette = Theme.palette
        let radius = floating ? Theme.cornerFloat : Theme.cornerCard
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: floating ? nil : .infinity, alignment: .leading)
            .background(Color(floating ? palette.surface2 : palette.surface1))
            .cornerRadius(radius)
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color(border ?? (floating ? palette.hair2 : palette.hair))))
            .shadow(color: floating ? Color(palette.shadowFloat) : .clear, radius: floating ? 12 : 0, y: floating ? 8 : 0)
    }
}

struct PanelHeader<Trailing: View>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.floatingPanel) private var floating
    var body: some View {
        let palette = Theme.palette
        HStack {
            T(title, bold: true, style: .section)
            Spacer()
            trailing()
        }
        .padding(.leading, floating ? 20 : 12)
        .padding(.trailing, floating ? 20 : 12)
        .frame(minHeight: floating ? 48 : 36)
        // In a dialog or a menu the title is its own band: a hairline under it and the accent lit in its corner.
        .background {
            if floating {
                RadialGradient(colors: [Color(palette.need).opacity(Theme.isLight ? 0.12 : 0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 180)
                    .opacity(Neon.on ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) { if floating { Line() } }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        trailing = { EmptyView() }
    }
}

struct Row<Content: View>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    var selected = false
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        let inner = HStack(spacing: 24, content: content)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? Color(palette.fillSelected) : (action != nil && hovering ? Color(palette.fill) : .clear))
            .contentShape(Rectangle())
        if let action {
            Button(action: action) { inner }.buttonStyle(.press).onHover { hovering = $0 }
        } else {
            inner
        }
    }
}

struct Line: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    var body: some View { Rectangle().fill(Color(Theme.palette.hair)).frame(height: 1) }
}

/// The title of a page: a short lit line under it, the only ornament a page has.
struct PageTitle: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
                .foregroundColor(Color(Theme.palette.text1))
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Color(Theme.palette.need))
                .frame(width: 28, height: 2)
                .neon(Theme.palette.need, radius: 4)
        }
        .padding(.bottom, 8)
    }
}

/// A full page with the same back bar everywhere.
struct PageFrame<Content: View>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    var title: String?
    var wide = false
    /// A short page that asks one thing stands in the middle of the window, the way a dialog would.
    var centered = false
    @ViewBuilder var content: () -> Content
    @Environment(\.embeddedPage) private var embedded
    @Environment(\.boxedPage) private var boxed
    var body: some View {
        let palette = Theme.palette
        if embedded {
            VStack(alignment: .leading, spacing: boxed ? 8 : 16) {
                if let title {
                    if boxed {
                        T(title, color: Theme.palette.text2, style: .secondary).lineLimit(1).truncationMode(.head)
                    } else {
                        PageTitle(text: title)
                    }
                }
                content()
            }
        } else {
        VStack(spacing: 0) {
            HStack {
                Btn("Geri", kind: .plain, key: "Esc", icon: "chevron.left") { AppModel.shared.goBack() }
                Spacer()
            }
            .padding(.leading, 80)
            .padding(.trailing, 16)
            .frame(height: 44)
            .background(TitleBarArea())
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let title { PageTitle(text: title) }
                        content()
                    }
                    .padding(EdgeInsets(top: 24, leading: 32, bottom: centered ? 68 : 40, trailing: 32))
                    .frame(maxWidth: wide ? .infinity : 760, alignment: .leading)
                    .frame(maxWidth: .infinity, minHeight: centered ? geometry.size.height : nil)
                }
            }
        }
        .background(ZStack { Color(palette.surface0); CornerGlows() })
        }
    }
}

struct Meter: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let percent: Double
    var warn = false
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(Theme.palette.fill))
                Rectangle().fill(Color(warn ? Theme.palette.limit : Theme.palette.add))
                    .frame(width: geometry.size.width * min(max(percent, 0), 100) / 100)
            }
        }
        .frame(height: 4)
        .cornerRadius(2)
    }
}

struct EntermField: View {
    @ObservedObject private var appearance = AppearanceTick.shared
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
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(palette.terminal))
            .cornerRadius(Theme.cornerControl)
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerControl).stroke(focused ? Color(palette.need).opacity(0.7) : Color(palette.hair2)))
            .shadow(color: focused && Neon.on ? Color(palette.need).opacity(0.25) : .clear, radius: 6)
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
