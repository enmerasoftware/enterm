import EntermCore
import SwiftUI

/// Whoever holds an unlocked phone would otherwise have a shell on the Mac. The gate comes before everything.
struct LockGate: View {
    @EnvironmentObject var model: PhoneModel
    var body: some View {
        if model.locked, model.peer != nil {
            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                Image(systemName: "lock.fill").font(.system(size: 32)).foregroundColor(Palette.text2)
                Txt("Uygulama Kilitli", style: .title3, weight: .semibold)
                Txt("Bu telefon bilgisayarda komut çalıştırabilir. Açmak için doğrulayın.", color: Palette.text2)
                Spacer()
                ActionButton("Kilidi Aç", style: .primary) { Task { await model.unlock() } }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Palette.surface0)
            .task { await model.unlock() }
        } else {
            RootScreen()
        }
    }
}

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
    @ScaledMetric private var tabIcon: CGFloat = 22
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
        let waiting = model.waitingApprovals.count + model.attention.count
        return HStack(spacing: 0) {
            tabItem("Oturum", icon: "terminal", 0)
            tabItem("Tuval", icon: "square.grid.2x2", 1)
            tabItem("Onay", icon: "checkmark.shield", 2, count: waiting)
            tabItem("Daha", icon: "ellipsis.circle", 3)
        }
        .frame(minHeight: 50)
        .background(Palette.surface1)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: 1) }
    }

    private func tabItem(_ title: String, icon: String, _ index: Int, count: Int = 0) -> some View {
        let on = model.tab == index
        return Button { model.tab = index } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: tabIcon))
                    .foregroundColor(on ? Palette.text1 : Palette.text2)
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundColor(Palette.btnfg)
                                .padding(.horizontal, 4)
                                .background(Palette.btn)
                                .clipShape(Capsule())
                                .offset(x: 10, y: -6)
                        }
                    }
                Txt(title, color: on ? Palette.text1 : Palette.text2, style: .caption2, weight: on ? .semibold : .regular)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(title), \(count) Bekliyor" : title)
        .accessibilityShowsLargeContentViewer()
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
        Txt(text, color: color, style: .subheadline, weight: .medium)
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
                DimTxt("Son Görülme: \(since.turkish(date: .omitted))")
                DimTxt("Bir dahaki sefer için bilgisayarda: Ayarlar › Uyku.")
            }
            .padding(.horizontal, 16)
        default:
            EmptyView()
        }
    }
}

/// One badge everywhere: neutral, and in colour only when it asks for something.
struct StatusText: View {
    let info: SessionInfo
    @ScaledMetric private var symbol: CGFloat = 9
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: symbol, weight: .semibold)).foregroundColor(symbolColor)
            Txt(info.status.title, color: textColor, style: .footnote, weight: strong ? .semibold : .medium).lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(minHeight: 24)
        .background(ground)
        .cornerRadius(6)
    }
    private var icon: String {
        switch info.status {
        case .running: return "circle.fill"
        case .queued: return "clock"
        case .needsApproval: return "diamond.fill"
        case .limitReached: return "square.fill"
        case .failed, .notFound: return "xmark"
        case .exited: return "checkmark"
        default: return "circle"
        }
    }
    private var strong: Bool { [.needsApproval, .limitReached, .failed, .notFound].contains(info.status) }
    private var accent: Color {
        switch info.status {
        case .needsApproval: return Palette.need
        case .limitReached: return Palette.limit
        default: return Palette.err
        }
    }
    private var symbolColor: Color {
        if strong { return accent }
        return info.status == .running ? Palette.add : Palette.text2
    }
    private var textColor: Color { strong ? accent : Palette.text1 }
    private var ground: Color { strong ? accent.opacity(0.16) : Palette.fill }
}

/// 2.1T
struct SessionsScreen: View {
    @EnvironmentObject var model: PhoneModel
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner()
            if let problem = model.startProblem {
                Button { model.startProblem = nil } label: {
                    Txt(problem, color: Palette.err)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
            if model.showQueuedNote {
                DimTxt("◷ Sırada: Yer açılınca kendiliğinden başlar. Çalışan iş durmadı.")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            HStack {
                ScreenTitle(text: model.connection == .connected ? "Oturumlar" : "Son Bilinen Durum")
                if model.connection == .connected {
                    Button { model.route.append(.newOptions) } label: {
                        Image(systemName: "plus").font(.headline).foregroundColor(Palette.text1).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
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
                    ForEach(model.attention.queue) { item in
                        Button { model.route.append(.queued(item.id)) } label: {
                            HStack {
                                Txt(item.name, bold: true).lineLimit(1)
                                Spacer()
                                Txt("◷ Sırada", color: Palette.text2, style: .footnote, weight: .medium)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface1)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hair))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
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
        VStack(alignment: .leading, spacing: 4) {
            if size.isAccessibilitySize {
                Txt(model.title(info), bold: true).lineLimit(2)
                StatusText(info: info)
            } else {
                HStack {
                    Txt(model.title(info), bold: true).lineLimit(1)
                    Spacer()
                    StatusText(info: info)
                }
            }
            DimTxt(model.folder(info)).lineLimit(1)
            if let activity = info.lastActivity { DimTxt(activity).lineLimit(1) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface1)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(info.pendingApproval != nil ? Palette.need : Palette.hair))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

/// 0.1T and 4.1T: the session itself, with the keys a phone keyboard lacks.
struct SessionScreen: View {
    @EnvironmentObject var model: PhoneModel
    @Environment(\.dynamicTypeSize) private var size
    let info: SessionInfo
    @State private var controlOn = false

    var body: some View {
        let terminal = model.host(for: info.number)
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { model.openSession = nil } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).foregroundColor(Palette.text1).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Oturumlar")
                VStack(alignment: .leading, spacing: 0) {
                    if size.isAccessibilitySize {
                        Txt(model.title(info), bold: true).lineLimit(1)
                        StatusText(info: info)
                    } else {
                        HStack(spacing: 8) {
                            Txt(model.title(info), bold: true).lineLimit(1)
                            StatusText(info: info).fixedSize()
                        }
                    }
                    Txt(info.cwd, color: Palette.text2, style: .footnote).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button { model.route.append(.details(info.number)) } label: {
                    Image(systemName: "info.circle").font(.body).foregroundColor(Palette.text1).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ayrıntılar")
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 52)
            .background(Palette.surface1)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.hair).frame(height: 1) }
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
        let first = HStack(spacing: 4) {
            key("Esc") { terminal.press("\u{1b}") }
            key("Tab") { terminal.press("\t") }
            key("Ctrl", on: controlOn) {
                controlOn.toggle()
                terminal.view.controlModifier = controlOn
            }
        }
        let second = HStack(spacing: 4) {
            key(symbol: "arrow.up", label: "Yukarı") { terminal.press("\u{1b}[A") }
            key(symbol: "arrow.down", label: "Aşağı") { terminal.press("\u{1b}[B") }
            key(symbol: "return", label: "Enter") { terminal.press("\r") }
        }
        return Group {
            if size.isAccessibilitySize {
                VStack(spacing: 4) {
                    first
                    second
                }
            } else {
                HStack(spacing: 4) {
                    first
                    second
                }
            }
        }
        .padding(4)
        .background(Palette.surface1)
        .onReceive(NotificationCenter.default.publisher(for: .terminalViewControlModifierReset)) { _ in controlOn = false }
    }

    private func key(_ title: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(on ? Palette.text1 : Palette.text1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Palette.fillSelected : Palette.fill)
                .cornerRadius(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func key(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Palette.text1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Palette.fill)
                .cornerRadius(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
            Text(approval.summary).font(.mono).foregroundColor(Palette.text1).lineLimit(4)
            DimTxt("Yetki: \(approval.category.title)")
            ButtonPair {
                ActionButton("Reddet") { model.decide(id: approval.id, decision: "deny") }
            } main: {
                ActionButton("İzin Ver", style: .primary) { Approval.allow(id: approval.id) }
            }
            ActionButton("Ayrıntı", style: .plain) { model.route.append(.approval(approval.id)) }
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
                    if model.attention.limitReturnAccount != nil {
                        NavRow("✓ Limit Açıldı, Dönülsün Mü?") { model.route.append(.limitOpened) }
                    }
                    ForEach(model.attention.resumeFailed, id: \.self) { number in
                        NavRow("■ \(model.session(number).map { model.title($0) } ?? "Oturum"): Konuşma Sürdürülemedi") { model.route.append(.resumeFailed(number)) }
                    }
                    ForEach(model.attention.codexLimit, id: \.self) { number in
                        NavRow("■ \(model.session(number).map { model.title($0) } ?? "Oturum"): Kontrol Edin") { model.route.append(.codexLimit(number)) }
                    }
                    ForEach(model.sessions.filter { $0.status == .limitReached }) { info in
                        Card {
                            HStack {
                                Txt(model.title(info), bold: true)
                                Spacer()
                                Txt("■ Limit", color: Palette.limit, bold: true)
                            }
                            DimTxt("Limit doldu, iş korundu.")
                            ActionButton("Seçenekleri Gör") { model.route.append(.limit(info.number)) }
                        }
                    }
                    if model.waitingApprovals.isEmpty && model.attention.count == 0 && !model.sessions.contains(where: { $0.status == .limitReached }) {
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
                                    ActionButton("Reddet") { model.decide(id: approval.id, decision: "deny") }
                                    ActionButton("İzin Ver", style: .primary) { Approval.allow(id: approval.id) }
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                            .background(Palette.surface1)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(info.pendingApproval != nil ? Palette.need : Palette.hair))
                            .cornerRadius(12)
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
                            DimTxt("Eşleşme: \(peer.pairedAt.turkish(date: .long, time: .omitted))")
                        }
                        DimTxt("Telefon bu bilgisayara uçtan uca şifreli bağlanır. Oturumlar telefonda çalışmaz, yalnız görünür.")
                    }
                    NavGroup {
                        NavRow("Ekibini Kur", icon: "person.3") { model.route.append(.teamStart) }
                        NavRow("Yönetici: Kararlar", icon: "checklist") { model.route.append(.teamDecisions) }
                        NavRow("Hesaplar", icon: "person") { model.route.append(.accounts) }
                        NavRow("Model Ve Maliyet", icon: "chart.bar") { model.route.append(.cost) }
                        NavRow("Güç Sınırı", icon: "gauge.with.needle") { model.route.append(.power) }
                    }
                    Card {
                        DimTxt("Tema")
                        Choice(options: [("dark", "Koyu"), ("light", "Açık")], value: $model.theme)
                    }
                    Card {
                        DimTxt("Onayda Face ID")
                        Choice(options: [(true, "Açık"), (false, "Kapalı")], value: Binding(
                            get: { model.faceIDForApprovals },
                            set: { value in Task { await model.setFaceIDForApprovals(value) } }))
                    }
                    Card {
                        DimTxt("Uygulama Kilidi")
                        Choice(options: [(true, "Açık"), (false, "Kapalı")], value: Binding(
                            get: { model.appLockOn },
                            set: { value in Task { await model.setAppLock(value) } }))
                        DimTxt("Açılışta ve bir dakikadan uzun aradan sonra doğrulama ister. Terminal bilgisayarda komut çalıştırır.")
                    }
                    ActionButton("Bildirimlere İzin Ver") { model.askForNotifications() }
                    if confirming {
                        Card {
                            Txt("Bu Bilgisayar Kaldırılsın Mı?", bold: true)
                            DimTxt("Tekrar kullanmak için yeniden eşleştirirsiniz. Oturumlar bilgisayarda çalışmaya devam eder.")
                            ButtonPair {
                                ActionButton("Vazgeç") { confirming = false }
                            } main: {
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
