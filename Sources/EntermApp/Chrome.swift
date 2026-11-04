import AppKit
import EntermCore
import SwiftUI

struct TopBar: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var inbox = Inbox.shared
    @ObservedObject var power = PowerCenter.shared
    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 16) {
            if model.maximized != nil {
                Btn("Tümünü Gör", kind: .plain, key: "⌘⏎") { model.toggleMaximize() }
            }
            if model.mode == .tabs && model.sessions.count > 1 {
                let labels = model.sessionLabels
                ForEach(model.sessions) { info in
                    Btn(labels[info.number] ?? model.title(for: info), kind: info.number == model.focused ? .selected : .plain) {
                        model.setFocus(info.number)
                        model.onLayoutChange?()
                    }
                }
            } else if let info = model.focusedInfo {
                HStack(spacing: 8) {
                    T(model.title(for: info), bold: true).lineLimit(1)
                    Dim(model.toolLabel(for: info))
                }
            }
            Spacer(minLength: 0)
            if let hint = model.hint {
                Btn(hint, kind: .plain) { model.hint = nil }.lineLimit(1)
            }
            if model.serviceLost {
                T("■ Koptu", color: palette.limit, bold: true)
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
            Btn("+", kind: .plain) { Commands.perform("newSession") }.accessibilityLabel("Yeni Oturum")
            Btn("⋯", kind: .plain) { Commands.perform("menu") }.accessibilityLabel("Menü")
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
                HStack(spacing: 4) {
                    Btn("Tam Ekran", kind: .plain, key: "⌘⏎") { model.toggleMaximize() }
                    Btn("Yeni Oturum", kind: .plain, key: "n") { Commands.perform("newSession") }
                    Btn("−", kind: .plain) { Commands.perform("zoomOut") }
                    T("%\(Int(model.zoom * 100))")
                    Btn("+", kind: .plain) { Commands.perform("zoomIn") }
                    Btn("Sığdır", kind: .plain, key: "0") { Commands.perform("fit") }
                    Btn("Komutlar", kind: .plain, key: "⌘K") { Commands.perform("palette") }
                }
                .padding(.horizontal, 8)
                .frame(height: 44)
                .background(Color(Theme.palette.raise))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(Theme.palette.line2)))
                .frame(maxHeight: .infinity)
                .padding(.trailing, model.detailsOpen ? 400 : 0)
            }
            if model.footVisible {
                HStack(spacing: 16) {
                    let labels = model.sessionLabels
                    ForEach(model.sessions) { info in
                        Button { model.setFocus(info.number) } label: {
                            T("\(info.status.symbol) \(labels[info.number] ?? model.title(for: info))", color: info.number == model.focused ? Theme.palette.fg : Theme.palette.dim)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    Dim(limitSummary)
                }
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(Color(Theme.palette.panel))
                .overlay(alignment: .top) { Line() }
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
                        HStack {
                            T(install).lineLimit(1).textSelection(.enabled)
                            Spacer()
                            Btn("Kopyala", kind: .plain) { NotFoundActions.copy(install) }
                        }
                        Dim("Komut bu terminalde görünür şekilde çalışır. Kendiniz de yazabilirsiniz.")
                        HStack {
                            Btn("Bu Terminalde Çalıştır", kind: .primary, key: "⏎") { NotFoundActions.primary() }
                            Btn("Vazgeç", kind: .plain, key: "Esc") { model.notFound = nil }
                        }
                    case .notInPath(let path):
                        T(path)
                        Dim("Kurulum bitmiş, ama bu klasör PATH'te değil. PATH değişmez, Enterm bu kopyayı tam yolla çalıştırır.")
                        HStack {
                            Btn("Buradan Çalıştır", kind: .primary, key: "⏎") { NotFoundActions.primary() }
                            Btn("Yeni Terminal", kind: .plain, key: "⌘T") { model.notFound = nil; model.newTerminal() }
                            Btn("Vazgeç", kind: .plain, key: "Esc") { model.notFound = nil }
                        }
                    case .inApp(let path):
                        T(path).lineLimit(1)
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
