import AppKit
import EntermCore
import SwiftUI

extension Color {
    init(_ color: NSColor) { self.init(nsColor: color) }
}

/// One family, one size. All SwiftUI text goes through this.
struct T: View {
    let text: String
    var color: NSColor?
    var bold = false
    init(_ text: String, color: NSColor? = nil, bold: Bool = false) {
        self.text = text
        self.color = color
        self.bold = bold
    }
    var body: some View {
        Text(text)
            .font(Theme.swiftFont(bold: bold))
            .foregroundColor(Color(color ?? Theme.palette.fg))
    }
}

struct Dim: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { T(text, color: Theme.palette.dim) }
}

struct Key: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        T(text, color: Theme.palette.dim)
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(Theme.palette.line2)))
    }
}

enum BtnKind { case plain, outline, primary, danger, selected }

struct Btn: View {
    let title: String
    var kind: BtnKind = .outline
    var key: String?
    var action: () -> Void
    init(_ title: String, kind: BtnKind = .outline, key: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.key = key
        self.action = action
    }
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            HStack(spacing: 8) {
                T(title, color: foreground, bold: kind == .primary || kind == .selected).lineLimit(1)
                if let key { T(key, color: kind == .primary ? palette.btnfg : palette.dim) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, kind == .plain ? 3 : 2)
            .background(background)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(stroke, lineWidth: kind == .plain ? 0 : 1))
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private var foreground: NSColor {
        switch kind {
        case .primary: return Theme.palette.btnfg
        case .danger: return Theme.palette.err
        case .selected: return Theme.palette.bg
        default: return Theme.palette.fg
        }
    }
    private var background: Color {
        switch kind {
        case .primary: return Color(Theme.palette.btn)
        case .selected: return Color(Theme.palette.fg)
        default: return .clear
        }
    }
    private var stroke: Color {
        switch kind {
        case .primary: return Color(Theme.palette.btnline)
        case .danger: return Color(Theme.palette.err)
        default: return Color(Theme.palette.line2)
        }
    }
}

/// Segmented choice with the one selection style of the design.
struct Seg<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var value: Value
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option in
                Btn(option.1, kind: option.0 == value ? .selected : .plain) { value = option.0 }
            }
        }
        .padding(1)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(Theme.palette.line2)))
    }
}

struct StatusBadge: View {
    let status: SessionStatus
    var body: some View {
        let palette = Theme.palette
        let color: NSColor = {
            switch status {
            case .needsApproval: return palette.need
            case .limitReached: return palette.limit
            case .failed: return palette.err
            case .running: return palette.fg
            default: return palette.dim
            }
        }()
        T("\(status.symbol) \(status.title)", color: color, bold: status == .needsApproval || status == .limitReached || status == .failed)
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(color)))
    }
}

struct Panel<Content: View>: View {
    var border: NSColor?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(Color(Theme.palette.panel))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(border ?? Theme.palette.line2)))
    }
}

struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack {
            T(title, bold: true)
            Spacer()
            trailing()
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(minHeight: 32)
        .background(Color(Theme.palette.raise))
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
        let inner = HStack(spacing: 16, content: content)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color(Theme.palette.raise) : .clear)
            .contentShape(Rectangle())
        if let action {
            Button(action: action) { inner }.buttonStyle(.plain)
        } else {
            inner
        }
    }
}

struct Line: View {
    var body: some View { Rectangle().fill(Color(Theme.palette.line)).frame(height: 1) }
}

/// A full page with the same back bar everywhere.
struct PageFrame<Content: View>: View {
    var title: String?
    var wide = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Btn("‹ Geri", kind: .plain, key: "Esc") { AppModel.shared.page = nil }
                Spacer()
            }
            .padding(.leading, 80)
            .padding(.trailing, 16)
            .frame(height: 44)
            .background(Color(Theme.palette.panel))
            Line()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let title { T(title, bold: true) }
                    content()
                }
                .padding(24)
                .frame(maxWidth: wide ? .infinity : 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(Theme.palette.bg))
    }
}

struct Meter: View {
    let percent: Double
    var warn = false
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(Theme.palette.line))
                Rectangle().fill(Color(warn ? Theme.palette.limit : Theme.palette.fg))
                    .frame(width: geometry.size.width * min(max(percent, 0), 100) / 100)
            }
        }
        .frame(height: 8)
        .cornerRadius(4)
    }
}

struct EntermField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color(Theme.palette.dim)))
            .textFieldStyle(.plain)
            .font(Theme.swiftFont())
            .foregroundColor(Color(Theme.palette.fg))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(Theme.palette.bg))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(Theme.palette.line2)))
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
