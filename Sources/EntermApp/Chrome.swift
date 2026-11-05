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
            if model.showsProjectTabs {
                ForEach(model.projectNames, id: \.self) { name in
                    ProjectTab(name: name)
                }
                IconBtn("plus", label: "Yeni Proje") { Commands.perform("newProject") }
                    .help("Yeni Proje (⌘⇧N)")
            }
            if model.mode == .tabs && model.visibleSessions.count > 1 {
                if model.showsProjectTabs { Rectangle().fill(Color(palette.hair2)).frame(width: 1, height: 16).padding(.horizontal, 4) }
                let labels = model.sessionLabels
                ForEach(model.visibleSessions) { info in
                    Btn(labels[info.number] ?? model.name(for: info), kind: info.number == model.focused ? .selected : .plain) {
                        model.setFocus(info.number)
                        model.onLayoutChange?()
                    }
                }
            } else if !model.showsProjectTabs, let info = model.focusedInfo {
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
                Button { Commands.perform("inbox") } label: {
                    HStack(spacing: 6) {
                        Symbol("diamond.fill", color: palette.need, size: 8)
                        T("Onaylar \(waiting)", color: palette.need, style: .secondary, weight: .semibold)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .frame(height: 20)
                    .background(Color(palette.need).opacity(0.16))
                    .cornerRadius(Theme.cornerControl)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if model.focusedInfo?.tool != .terminal, model.focusedInfo != nil {
                Btn("Ayrıntılar", kind: .plain, key: "⌘I") { model.detailsOpen.toggle() }
            }
            if !model.toolbarVisible {
                IconBtn("plus", label: "Yeni Oturum") { Commands.perform("newSession") }
            }
            IconBtn("iphone", label: "Telefon") { Commands.perform("phone") }.help("Telefon")
            IconBtn("gearshape", label: "Ayarlar") { Commands.perform("settings") }.help("Ayarlar (⌘,)")
            IconBtn("ellipsis", label: "Menü") { Commands.perform("menu") }
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(palette.surface0))
    }
}

/// The command bar of the canvas and the slim line under it.
struct BottomBars: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var accounts = AccountStore.shared
    var body: some View {
        VStack(spacing: 0) {
            if model.toolbarVisible {
                CommandBar()
                    .frame(maxHeight: .infinity)
                    .padding(.leading, model.railVisible(width: 2000) ? 200 : 0)
                    .padding(.trailing, model.detailsOpen ? 400 : 0)
            }
            if model.footVisible {
                // Without the rail the strip is still the way between sessions.
                if model.visibleSessions.count > 1 && !model.toolbarVisible {
                    SessionStrip(summary: limitSummary)
                } else {
                    StatusLine(summary: limitSummary)
                }
            }
        }
    }
    private var limitSummary: String { accounts.limitSummary }
}

extension AppModel {
    /// A lone terminal stays plain: tabs appear once there is more than one thing to move between.
    var showsProjectTabs: Bool { projectNames.count > 1 || tileCount > 1 }
}

/// A project on the bar: its name, what it is doing, and a lit line under the one on screen.
struct ProjectTab: View {
    let name: String
    @ObservedObject var model = AppModel.shared
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        let on = model.activeProject == name && !model.showHome
        let members = model.sessions.filter { model.project(of: $0) == name }
        let attention = members.first { $0.status == .needsApproval || $0.status == .limitReached || $0.status == .failed }
        let running = members.contains { $0.status == .running && $0.tool != .terminal }
        let dot: NSColor? = attention.flatMap { Neon.color($0.status) } ?? (running ? palette.g1 : nil)
        Button { model.switchProject(name) } label: {
            HStack(spacing: 6) {
                if let dot { Circle().fill(Color(dot)).frame(width: 7, height: 7).neon(dot, radius: 3) }
                T(name, color: on ? palette.text1 : palette.text3, weight: on ? .semibold : .regular).lineLimit(1)
                if hovering {
                    Button {
                        model.confirm(title: "\(name) Kapatılsın mı?", detail: "Bu projedeki \(members.count) oturum ve içinde çalışan programlar kapanır.", action: "Projeyi Kapat") {
                            model.closeProject(name)
                        }
                    } label: {
                        Symbol("xmark", color: palette.text3, size: 10).frame(width: 14, height: 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Projeyi Kapat")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                if on {
                    Rectangle().fill(Color(palette.need)).frame(height: 2).neon(palette.need, radius: 3).padding(.horizontal, 10).padding(.bottom, 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
                ForEach(model.visibleSessions.prefix(visible)) { info in
                    item(info, label: labels[info.number] ?? "")
                }
                if visible < model.visibleSessions.count {
                    Btn("+\(model.visibleSessions.count - visible)", kind: .plain) { Commands.perform("sessionList") }
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
        let list = model.visibleSessions
        for (index, info) in list.enumerated() {
            used += width(labels[info.number] ?? "") + 2
            // The last slot may have to hold the count instead.
            let room = index == list.count - 1 ? available : available - 44
            if used > room { return max(index, 1) }
        }
        return list.count
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
        model.connection.sendInput(number: card.number, bytes: Data((command(for: card) + "\r").utf8))
    }

    static func command(for card: NotFoundCard) -> String {
        switch card.kind {
        case .notInstalled(let install): return install
        case .notInPath(let path), .inApp(let path):
            // Only this one command sees the folder. The shell's PATH does not change.
            let folder = (path as NSString).deletingLastPathComponent
            return "PATH=\(shellQuote(folder)):\"$PATH\" \(card.command)"
        case .geminiRejected: return "agy"
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
