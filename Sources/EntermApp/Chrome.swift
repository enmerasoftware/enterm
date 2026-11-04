import AppKit
import EntermCore
import SwiftUI

struct TopBar: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var inbox = Inbox.shared
    @ObservedObject var power = PowerCenter.shared
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 8) {
            if model.maximized != nil {
                Btn("Tümünü Gör", kind: .plain, key: "⌘⏎") { model.toggleMaximize() }
            }
            if model.mode == .tabs && model.sessions.count > 1 {
                let labels = model.sessionLabels
                ForEach(model.sessions) { info in
                    Btn(labels[info.number] ?? model.name(for: info), kind: info.number == model.focused ? .selected : .plain) {
                        model.setFocus(info.number)
                        model.onLayoutChange?()
                    }
                }
            } else if let info = model.focusedInfo {
                HStack(spacing: 8) {
                    T(model.name(for: info), bold: true).lineLimit(1)
                    Dim(model.displayPath(info.cwd)).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
            if let hint = model.hint {
                Btn(hint, kind: .plain) { model.hint = nil }.lineLimit(1)
            }
            if model.serviceLost {
                T("■ Koptu", color: palette.err, bold: true)
            }
            if power.settings.lowPower {
                Btn("Düşük Güçlü Açık", kind: .plain) { Commands.perform("power") }
            }
            if !power.queue.isEmpty {
                Btn("◷ Sırada \(power.queue.count)", kind: .outline) { Commands.perform("inbox") }
            }
            let waiting = model.sessions.filter { $0.pendingApproval != nil }.count
            if waiting > 0 {
                Btn("◆ Onaylar \(waiting)", kind: .outline) { Commands.perform("inbox") }
            }
            if model.focusedInfo?.tool != .terminal, model.focusedInfo != nil {
                Btn("Ayrıntılar", kind: .plain, key: "⌘I") { model.detailsOpen.toggle() }
            }
            IconBtn("plus", label: "Yeni Oturum") { Commands.perform("newSession") }
            IconBtn("ellipsis", label: "Menü") { Commands.perform("menu") }
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(palette.panel))
        .overlay(alignment: .bottom) { Line() }
    }
}

/// The floating tool bar of the canvas and the slim status line under it.
struct BottomBars: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var accounts = AccountStore.shared
    var body: some View {
        VStack(spacing: 0) {
            if model.toolbarVisible {
                HStack(spacing: 2) {
                    ToolItem("Tam Ekran", icon: "arrow.up.left.and.arrow.down.right", key: "⌘⏎") { model.toggleMaximize() }
                    ToolItem("Yeni Oturum", icon: "plus", key: "N") { Commands.perform("newSession") }
                    ToolSeparator()
                    IconBtn("minus", label: "Uzaklaştır") { Commands.perform("zoomOut") }
                    T("%\(Int(model.zoom * 100))", style: .secondary).frame(width: 36)
                    IconBtn("plus", label: "Yakınlaştır") { Commands.perform("zoomIn") }
                    ToolItem("Sığdır", icon: "viewfinder", key: "0") { Commands.perform("fit") }
                    ToolSeparator()
                    ToolItem("Komutlar", icon: "command", key: "⌘K") { Commands.perform("palette") }
                }
                .padding(.horizontal, 6)
                .frame(height: 40)
                .background(Color(Theme.palette.surface2))
                .cornerRadius(Theme.cornerFloat)
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerFloat).stroke(Color(Theme.palette.hair2)))
                .shadow(color: Color(Theme.palette.shadowFloat), radius: 12, y: 8)
                .frame(maxHeight: .infinity)
                .padding(.trailing, model.detailsOpen ? 400 : 0)
            }
            if model.footVisible {
                SessionStrip(summary: limitSummary)
            }
        }
    }

    private var limitSummary: String {
        accounts.accounts.compactMap { account -> String? in
            guard let window = account.lastLimit?.fiveHour ?? account.lastLimit?.sevenDay else { return nil }
            return "\(account.name) %\(Int(window.usedPercent))"
        }.joined(separator: " · ")
    }
}

struct ToolItem: View {
    let title: String
    let icon: String
    let key: String
    let action: () -> Void
    @State private var hovering = false
    init(_ title: String, icon: String, key: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.key = key
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Symbol(icon)
                T(title)
                Key(key)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(hovering ? Color(Theme.palette.fill) : .clear)
            .cornerRadius(Theme.cornerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ToolSeparator: View {
    var body: some View {
        Rectangle().fill(Color(Theme.palette.hair2)).frame(width: 1, height: 16).padding(.horizontal, 6)
    }
}

/// One line per session at the bottom. What does not fit becomes a count that opens the list.
struct SessionStrip: View {
    @ObservedObject var model = AppModel.shared
    let summary: String

    var body: some View {
        let palette = Theme.palette
        GeometryReader { geometry in
            let labels = model.sessionLabels
            let reserve = (summary as NSString).size(withAttributes: [.font: Theme.ui(.secondary)]).width + 24
            let visible = fitting(labels: labels, width: geometry.size.width - reserve - 16)
            HStack(spacing: 2) {
                ForEach(model.sessions.prefix(visible)) { info in
                    item(info, label: labels[info.number] ?? "")
                }
                if visible < model.sessions.count {
                    Btn("+\(model.sessions.count - visible)", kind: .plain) { Commands.perform("sessionList") }
                }
                Spacer(minLength: 0)
                T(summary, color: palette.text2, style: .secondary).padding(.trailing, 8)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 36)
        .background(Color(palette.surface1))
        .overlay(alignment: .top) { Line() }
    }

    private func width(_ label: String) -> CGFloat {
        min(200, (label as NSString).size(withAttributes: [.font: Theme.ui(.secondary, weight: .medium)]).width + 16 + 20)
    }

    private func fitting(labels: [UInt32: String], width available: CGFloat) -> Int {
        var used: CGFloat = 0
        for (index, info) in model.sessions.enumerated() {
            used += width(labels[info.number] ?? "") + 2
            // The last slot may have to hold the count instead.
            let room = index == model.sessions.count - 1 ? available : available - 44
            if used > room { return max(index, 1) }
        }
        return model.sessions.count
    }

    private func item(_ info: SessionInfo, label: String) -> some View {
        let palette = Theme.palette
        let look = StatusLook(info.status)
        let on = info.number == model.focused
        let color: NSColor = look.strong ? look.textColor : (on ? palette.text1 : palette.text2)
        return Button { model.setFocus(info.number) } label: {
            HStack(spacing: 6) {
                if info.tool == .terminal {
                    Symbol("terminal", color: palette.text3, size: 14)
                } else {
                    Symbol(look.symbol, color: look.symbolColor, size: 8)
                }
                T(label, color: color, style: .secondary, weight: look.strong ? .semibold : (on ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .frame(width: width(label), alignment: .leading)
            .background(on ? Color(palette.fillSelected) : .clear)
            .cornerRadius(Theme.cornerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The right pane behind ⌘I.
struct DetailPane: View {
    @ObservedObject var model = AppModel.shared
    var body: some View {
        if let info = model.focusedInfo {
            DetailTabs(info: info)
                .background(Color(Theme.palette.panel))
                .overlay(alignment: .leading) { Rectangle().fill(Color(Theme.palette.line)).frame(width: 1) }
        } else {
            Color(Theme.palette.panel)
        }
    }
}

/// The card that appears at the bottom of the terminal when a program is not found.
struct InlineCards: View {
    @ObservedObject var model = AppModel.shared
    var body: some View {
        if let card = model.notFound {
            Panel(border: Theme.palette.line2) {
                PanelHeader(title: card.title)
                VStack(alignment: .leading, spacing: 8) {
                    switch card.kind {
                    case .notInstalled(let install):
                        CommandBox(text: install)
                        Dim("Komut bu terminalde görünür şekilde çalışır. Kendiniz de yazabilirsiniz.")
                        HStack {
                            Btn("Bu Terminalde Çalıştır", kind: .primary, key: "⏎") { NotFoundActions.primary() }
                            Btn("Vazgeç", kind: .plain, key: "Esc") { model.notFound = nil }
                        }
                    case .notInPath(let path):
                        CommandBox(text: path)
                        Dim("Kurulum bitmiş, ama bu klasör PATH'te değil. PATH değişmez, Enterm bu kopyayı tam yolla çalıştırır.")
                        HStack {
                            Btn("Buradan Çalıştır", kind: .primary, key: "⏎") { NotFoundActions.primary() }
                            Btn("Yeni Terminal", kind: .plain, key: "⌘T") { model.notFound = nil; model.newTerminal() }
                            Btn("Vazgeç", kind: .plain, key: "Esc") { model.notFound = nil }
                        }
                    case .inApp(let path):
                        CommandBox(text: path)
                        Dim("PATH değişmez, Enterm bu kopyayı tam yolla çalıştırır.")
                        HStack {
                            Btn("Buradan Çalıştır", kind: .primary, key: "⏎") { NotFoundActions.primary() }
                            Btn("Vazgeç", kind: .plain, key: "Esc") { model.notFound = nil }
                        }
                    case .geminiRejected:
                        Dim("Kişisel hesaplar için resmi program Antigravity (agy). Kurumsal lisans ya da ücretli API anahtarıyla gemini çalışmaya devam eder.")
                        HStack {
                            Btn("agy Çalıştır", kind: .primary, key: "⏎") { NotFoundActions.primary() }
                            Btn("Vazgeç", kind: .plain, key: "Esc") { model.notFound = nil }
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

enum NotFoundActions {
    static func primary() {
        let model = AppModel.shared
        guard let card = model.notFound else { return }
        model.notFound = nil
        var text: String
        switch card.kind {
        case .notInstalled(let install): text = install
        case .notInPath(let path), .inApp(let path):
            // Only this one command sees the folder. The shell's PATH does not change.
            let folder = (path as NSString).deletingLastPathComponent
            text = "PATH=\(shellQuote(folder)):\"$PATH\" \(card.command)"
        case .geminiRejected: text = "agy"
        }
        text += "\r"
        model.connection.sendInput(number: card.number, bytes: Data(text.utf8))
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
