import EntermCore
import SwiftUI

struct RootScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        switch model.pairing {
        case .scanning: ScanScreen()
        case .connecting: ConnectingScreen()
        case .compare(let number): CompareScreen(number: number, waiting: false)
        case .waitingOther(let number): CompareScreen(number: number, waiting: true)
        case .failed(let reason): PairingProblem(reason: reason)
        case .none:
            if model.peer == nil { WelcomeScreen() } else { MainTabs() }
        }
    }
}

/// The code is read: the camera is no longer needed, and a link from outside never asked for it.
struct ConnectingScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Txt("Bilgisayara Bağlanılıyor", bold: true)
            ActionButton("Vazgeç", style: .plain) { model.cancelPairing() }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.bg)
    }
}

struct MainTabs: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(spacing: 0) {
            if let route = model.route.last {
                RouteScreen(route: route)
            } else if let number = model.openSession, let info = model.sessions.first(where: { $0.number == number }) {
                SessionScreen(info: info)
            } else {
                Group {
                    switch model.tab {
                    case 0: SessionsScreen()
                    case 1: CanvasScreen()
                    case 2: ApprovalsScreen()
                    default: MoreScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                tabBar
            }
        }
        .background(Palette.bg)
    }

    private var tabBar: some View {
        let waiting = model.waitingApprovals.count
        return HStack(spacing: 0) {
            tabItem("Oturum", 0)
            tabItem("Tuval", 1)
            tabItem(waiting > 0 ? "◆ Onay \(waiting)" : "Onay", 2)
            tabItem("Daha", 3)
        }
        .frame(height: 50)
        .background(Palette.panel)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func tabItem(_ title: String, _ index: Int) -> some View {
        Button { model.tab = index } label: {
            Txt(title, color: model.tab == index ? Palette.fg : Palette.dim, bold: model.tab == index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The state of the link, in the same words as the drawing.
struct ConnectionBanner: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        switch model.connection {
        case .connected:
            EmptyView()
        case .connecting:
            bar("○ Bağlanıyor", color: Palette.dim)
        case .unreachable:
            bar("■ Bağlantı Yok", color: Palette.limit)
        case .sleeping:
            bar("○ Bilgisayar Uyuyor", color: Palette.dim)
        }
    }
    private func bar(_ text: String, color: Color) -> some View {
        Txt(text, color: color, bold: true)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 16)
            .background(Palette.panel)
    }
}

/// 12.3T and 12.4T take over the list: what was last known, and what can be done now.
struct OfflineCard: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        switch model.connection {
        case .unreachable(let attempt):
            Card {
                Txt("Bilgisayara Ulaşılamıyor", bold: true)
                DimTxt("Oturumlar bilgisayarda sürüyor olabilir. Telefon internete bağlanınca kendiliğinden döner.")
                DimTxt("Deneme \(attempt)")
                ActionButton("Şimdi Dene") { model.retryNow() }
                DimTxt("Bağlantı yokken onay verilemez. Onaylar bağlantı dönünce düşer.")
            }
            .padding(.horizontal, 16)
        case .sleeping(let since):
            Card {
                Txt("Bilgisayar Uyku Modunda", bold: true)
                DimTxt("Oturumlar duraklatıldı, işler kaybolmadı. Bilgisayar uyanınca kaldığı yerden sürer.")
                DimTxt("Son Görülme: \(since.formatted(date: .omitted, time: .shortened))")
                DimTxt("Bir dahaki sefer için bilgisayarda: Ayarlar › Uyku.")
            }
            .padding(.horizontal, 16)
        default:
            EmptyView()
        }
    }
}

struct StatusText: View {
    let info: SessionInfo
    var body: some View {
        Txt("\(info.status.symbol) \(info.status.title)", color: color, bold: info.status == .needsApproval)
    }
    private var color: Color {
        switch info.status {
        case .needsApproval: return Palette.need
        case .limitReached, .notFound: return Palette.limit
        case .failed: return Palette.err
        case .running: return Palette.fg
        default: return Palette.dim
        }
    }
}

/// 2.1T
struct SessionsScreen: View {
    @EnvironmentObject var model: PhoneModel

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner()
            if let problem = model.startProblem {
                Button { model.startProblem = nil } label: {
                    Txt(problem, color: Palette.limit)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
            HStack {
                ScreenTitle(text: model.connection == .connected ? "Oturumlar" : "Son Bilinen Durum")
                if model.connection == .connected {
                    Button { model.route.append(.newOptions) } label: {
                        Txt("+", bold: true).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Yeni Oturum")
                    .padding(.trailing, 8)
                }
            }
            ScrollView {
                VStack(spacing: 8) {
                    OfflineCard()
                    ForEach(model.sessions) { info in
                        Button { if model.connection == .connected { model.openSession = info.number } } label: { row(info) }
                            .buttonStyle(.plain)
                    }
                    if model.sessions.isEmpty {
                        DimTxt(model.connection == .connected ? "Açık Oturum Yok." : "Henüz Bilgi Yok.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func row(_ info: SessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Txt(model.title(info), bold: true).lineLimit(1)
                Spacer()
                StatusText(info: info)
            }
            DimTxt(model.folder(info))
            if let activity = info.lastActivity { DimTxt(activity).lineLimit(1) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(info.pendingApproval != nil ? Palette.need : Palette.line2))
        .cornerRadius(6)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

/// 0.1T and 4.1T: the session itself, with the keys a phone keyboard lacks.
struct SessionScreen: View {
    @EnvironmentObject var model: PhoneModel
    let info: SessionInfo
    @State private var controlOn = false

    var body: some View {
        let terminal = model.host(for: info.number)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { model.openSession = nil } label: { Txt("‹ Oturumlar").frame(minHeight: 44).contentShape(Rectangle()) }
                Spacer()
                Txt(model.title(info), bold: true).lineLimit(1)
                StatusText(info: info).lineLimit(1)
                Button { model.route.append(.details(info.number)) } label: {
                    Txt("Ayrıntılar").frame(minHeight: 44).contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12)
            .background(Palette.panel)
            if let other = model.waitingApprovals.first(where: { $0.number != info.number }) {
                Button { model.openSession = nil; model.tab = 2 } label: {
                    Txt("◆ \(model.title(other)) onay istiyor ›", color: Palette.need)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
            }
            if let approval = info.pendingApproval {
                ApprovalCard(info: info, approval: approval).padding(8)
            }
            if info.status == .limitReached {
                ActionButton("■ Limit Doldu: Seçenekleri Gör") { model.route.append(.limit(info.number)) }.padding(8)
            }
            FoundCardView(info: info).padding(.horizontal, 8)
            TerminalSurface(terminal: terminal)
                .onAppear {
                    model.attach(info.number)
                    _ = terminal.view.becomeFirstResponder()
                }
                .onDisappear { model.detach(info.number) }
            keyRow(terminal)
        }
        .background(Palette.bg)
    }

    private func keyRow(_ terminal: PhoneTerminal) -> some View {
        HStack(spacing: 4) {
            key("Esc") { terminal.press("\u{1b}") }
            key("Tab") { terminal.press("\t") }
            key("Ctrl", on: controlOn) {
                controlOn.toggle()
                terminal.view.controlModifier = controlOn
            }
            key("↑") { terminal.press("\u{1b}[A") }
            key("↓") { terminal.press("\u{1b}[B") }
            key("⏎") { terminal.press("\r") }
        }
        .padding(4)
        .background(Palette.panel)
        .onReceive(NotificationCenter.default.publisher(for: .terminalViewControlModifierReset)) { _ in controlOn = false }
    }

    private func key(_ title: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.monoBold)
                .foregroundColor(on ? Palette.btnfg : Palette.fg)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Palette.btn : Palette.raise)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct ApprovalCard: View {
    @EnvironmentObject var model: PhoneModel
    let info: SessionInfo
    let approval: ApprovalRequest

    var body: some View {
        Card {
            HStack {
                Txt(model.title(info), bold: true).lineLimit(1)
                Spacer()
                Txt("◆ Onay", color: Palette.need, bold: true)
            }
            Txt(approval.summary).lineLimit(4)
            DimTxt("Yetki: \(approval.category.title)")
            HStack {
                ActionButton("İzin Ver", style: .primary) { Approval.allow(id: approval.id) }
                ActionButton("Reddet") { model.decide(id: approval.id, decision: "deny") }
            }
            if model.connection != .connected {
                DimTxt("Bağlantı dönünce gider.")
            }
        }
    }
}

/// 11.1T
struct ApprovalsScreen: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner()
            ScreenTitle(text: "Onay Kutusu")
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.waitingApprovals) { info in
                        if let approval = info.pendingApproval { ApprovalCard(info: info, approval: approval) }
                    }
                    ForEach(model.sessions.filter { $0.status == .limitReached }) { info in
                        Card {
                            HStack {
                                Txt(model.title(info), bold: true)
                                Spacer()
                                Txt("■ Limit", color: Palette.limit, bold: true)
                            }
                            DimTxt("Limit doldu, iş korundu. Hesap seçenekleri bilgisayarda.")
                        }
                    }
                    if model.waitingApprovals.isEmpty && !model.sessions.contains(where: { $0.status == .limitReached }) {
                        DimTxt("Bekleyen Karar Yok.").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// 2.2T: every box at a glance, with the decision on the box.
struct CanvasScreen: View {
    @EnvironmentObject var model: PhoneModel
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner()
            ScreenTitle(text: "Tuval")
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.sessions) { info in
                        Button { if model.connection == .connected { model.tab = 0; model.openSession = info.number } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Txt(model.title(info), bold: true).lineLimit(1)
                                DimTxt(model.folder(info)).lineLimit(1)
                                StatusText(info: info).lineLimit(1)
                                Spacer(minLength: 0)
                                if let approval = info.pendingApproval {
                                    ActionButton("İzin Ver", style: .primary) { Approval.allow(id: approval.id) }
                                    ActionButton("Reddet") { model.decide(id: approval.id, decision: "deny") }
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                            .background(Palette.panel)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(info.pendingApproval != nil ? Palette.need : Palette.line2))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// 13.1T
struct MoreScreen: View {
    @EnvironmentObject var model: PhoneModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner()
            ScreenTitle(text: "Daha")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Card {
                        Txt(model.peer?.name ?? "Bilgisayar", bold: true)
                        DimTxt(model.connection == .connected ? "✓ Bilgisayar Bağlı" : "○ Bilgisayar Bağlı Değil")
                        if let peer = model.peer {
                            DimTxt("Eşleşme: \(peer.pairedAt.formatted(date: .long, time: .omitted))")
                        }
                        DimTxt("Telefon bu bilgisayara uçtan uca şifreli bağlanır. Oturumlar telefonda çalışmaz, yalnız görünür.")
                    }
                    NavRow("Ekibini Kur") { model.route.append(.teamStart) }
                    NavRow("Yönetici: Kararlar") { model.route.append(.teamDecisions) }
                    NavRow("Hesaplar") { model.route.append(.accounts) }
                    NavRow("Model Ve Maliyet") { model.route.append(.cost) }
                    NavRow("Güç Sınırı") { model.route.append(.power) }
                    Card {
                        DimTxt("Onayda Face ID")
                        Choice(options: [(true, "Açık"), (false, "Kapalı")], value: $model.faceIDForApprovals)
                    }
                    ActionButton("Bildirimlere İzin Ver") { model.askForNotifications() }
                    if confirming {
                        Card {
                            Txt("Bu Bilgisayar Kaldırılsın Mı?", bold: true)
                            DimTxt("Tekrar kullanmak için yeniden eşleştirirsiniz. Oturumlar bilgisayarda çalışmaya devam eder.")
                            HStack {
                                ActionButton("Vazgeç") { confirming = false }
                                ActionButton("Kaldır", style: .primary) { model.unpair() }
                            }
                        }
                    } else {
                        ActionButton("Bilgisayarı Kaldır") { confirming = true }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
