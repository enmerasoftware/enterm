import AppKit
import EntermCore
import SwiftUI

struct PageRouter: View {
    let page: Page
    var body: some View {
        switch page {
        case .settings(let tab): SettingsPage(tab: tab).id(tab)
        case .welcome: WelcomeFlow()
        case .recents: RecentsPage()
        case .accounts: AccountsPage()
        case .accountAdd: AccountAddPage()
        case .apiKey: ApiKeyPage()
        case .inbox: InboxPage()
        case .board: BoardPage()
        case .team: TeamSetupPage()
        case .manager: ManagerPage()
        case .history: HistoryPage()
        case .newView: NewViewPage()
        case .sessionList: SessionListPage()
        case .changes: ChangesPage()
        case .browser: BrowserPage()
        case .files: FilesPage()
        case .editor(let path): EditorPage(path: path)
        case .note: NotePage()
        case .remote: RemotePage()
        case .messages: MessagesPage()
        case .cost: CostPage()
        case .restore: RestorePage()
        case .scheduler: SchedulerPage()
        case .run: RunPage()
        case .whiteboard: WhiteboardPage()
        case .simulator: SimulatorPage()
        case .uninstall: UninstallPage()
        case .phone: PhonePage()
        case .notYet(let name): NotYet(name: name)
        }
    }
}

// MARK: Stores

final class BoardStore: ObservableObject {
    static let shared = BoardStore()
    @Published var board = Board.load()
    func reload() { board = Board.load() }
    func change(_ edit: (inout Board) -> Void) {
        edit(&board)
        board.save()
    }
}

final class TeamStore: ObservableObject {
    static let shared = TeamStore()
    @Published var team = Team.load()
    func reload() { team = Team.load() }
}

// MARK: Approvals

enum Approvals {
    static func decide(id: String, decision: String, remember: Bool = false) {
        let model = AppModel.shared
        var message = WireMessage(op: "decide")
        message.id = id
        message.decision = decision
        message.text = remember ? "remember" : nil
        model.connection.send(message)
        if model.overlay == .approval(id) { model.overlay = nil }
        // The next waiting request opens by itself, one at a time.
        if let next = model.sessions.compactMap(\.pendingApproval).first(where: { $0.id != id }) {
            model.overlay = .approval(next.id)
        }
    }

    static func allowForSession(_ request: ApprovalRequest) {
        var book = PermissionBook.load()
        var card = book.card(for: request.sessionID)
        card.modes[request.category] = .allow
        book.cards[request.sessionID] = card
        book.save()
        AppModel.shared.connection.send(WireMessage(op: "reloadPermissions"))
        decide(id: request.id, decision: "allow")
    }
}

struct ApprovalDialog: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let id: String
    @ObservedObject var model = AppModel.shared
    var body: some View {
        let request = model.sessions.compactMap(\.pendingApproval).first { $0.id == id }
        let info = model.sessions.first { $0.id == request?.sessionID }
        Panel(border: Theme.palette.need) {
            PanelHeader(title: "\(info.map { model.title(for: $0) } ?? "Oturum") İzin İstiyor") { StatusBadge(status: .needsApproval) }
            if let request {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Dim("Hangi Komut")
                        ApprovalCommand(text: request.summary)
                    }
                    let mode = PermissionBook.load().card(for: request.sessionID).mode(request.category)
                    Dim("Yetki: \(request.category.title), \(mode.title)")
                    if request.category == .internet {
                        Dim("Aynı adres bir kez sorulur, sonra hatırlanır. Hatırlananları Yetkiler'den silebilirsiniz.")
                    }
                    Dim("Yalnız Bu Komut İçin · Kayda Geçer")
                }
                .padding(20)
                DialogButtons {
                    Btn("Bu Oturumda Hep İzin Ver", kind: .plain) { Approvals.allowForSession(request) }
                    Btn("Reddet", key: "n") { Approvals.decide(id: id, decision: "deny") }
                    Btn("İzin Ver", kind: .primary, key: "y") { Approvals.decide(id: id, decision: "allow", remember: request.category == .internet) }
                }
            } else {
                Dim("Bu istek artık bekliyor değil.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .frame(width: 620)
    }
}

// MARK: Links

struct LinkPermissionDialog: View {
    let from: UInt32
    let to: UInt32
    @ObservedObject var model = AppModel.shared
    @State private var permission = LinkPermission.delegate
    @State private var bothWays = false
    var body: some View {
        let source = model.sessions.first { $0.number == from }
        let target = model.sessions.first { $0.number == to }
        Panel {
            PanelHeader(title: "\(source.map { model.title(for: $0) } ?? "") → \(target.map { model.title(for: $0) } ?? "")")
            T("Ne Yapabilsin?", bold: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 20, leading: 20, bottom: 0, trailing: 20))
            // The choices are lit rows: MenuList keeps their text at 20, under the title.
            MenuList {
                ForEach(LinkPermission.allCases) { option in
                    MenuRow(title: option.title, note: option.note, selected: permission == option) { permission = option }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    T("Yön")
                    Seg(options: [(false, "Tek Yön"), (true, "Çift Yön")], value: $bothWays)
                }
                Dim("Bağlantı yetki vermez, ajan mesajı onay sayılmaz.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
            DialogButtons {
                Btn("Vazgeç", kind: .plain, key: "Esc") { model.overlay = nil }
                Btn("Bağla", kind: .primary) {
                        if let source, let target {
                            LinkStore.shared.add(SessionLink(from: source.id, to: target.id, permission: permission, bothWays: bothWays))
                        }
                        model.overlay = nil
                }
            }
        }
        .frame(width: 520)
    }
}

struct LinkDetailDialog: View {
    let id: String
    @ObservedObject var links = LinkStore.shared
    @ObservedObject var model = AppModel.shared
    var body: some View {
        if let link = links.links.first(where: { $0.id == id }) {
            let source = model.sessions.first { $0.id == link.from }
            let target = model.sessions.first { $0.id == link.to }
            Panel {
                PanelHeader(title: "Bağlantı: \(source.map { model.title(for: $0) } ?? "Kapalı") → \(target.map { model.title(for: $0) } ?? "Kapalı")")
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        T("İzin")
                        Seg(options: LinkPermission.allCases.map { ($0, $0.title) }, value: Binding(
                            get: { link.permission },
                            set: { var edited = link; edited.permission = $0; links.update(edited) }))
                    }
                    HStack {
                        T("Yön")
                        Seg(options: [(false, "Tek Yön"), (true, "Çift Yön")], value: Binding(
                            get: { link.bothWays },
                            set: { var edited = link; edited.bothWays = $0; links.update(edited) }))
                    }
                    Dim("Silince mesaj geçmişi kalır, yeni mesaj gitmez.")
                }
                .padding(20)
                DialogButtons {
                        Btn("Bağlantıyı Sil", kind: .danger) {
                            links.remove(id)
                            model.overlay = nil
                        }
                        Btn("Mesaj Geçmişi", kind: .plain) {
                            model.overlay = nil
                            model.page = .messages
                        }
                        Btn("Kapat", kind: .plain, key: "Esc") { model.overlay = nil }
                }
            }
            .frame(width: 520)
        }
    }
}

struct MessagesPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    private let mails = MailBox.all().reversed()
    var body: some View {
        PageFrame(title: "Ajanlar Arası Mesaj Geçmişi") {
            Dim("Ajan mesajı onay değildir. Bilgi taşır, izin vermez. Sonraki komut yine yetki kartına bakar.")
            if mails.isEmpty { Dim("Henüz mesaj yok.") }
            ForEach(Array(mails)) { mail in
                Panel(border: mail.claimedApproval ? Theme.palette.err : Theme.palette.line2) {
                    VStack(alignment: .leading, spacing: 4) {
                        Dim("\(mail.fromName) → \(mail.toName) · \(mail.at.formatted(date: .omitted, time: .shortened)) · Ajan Mesajı")
                        T(mail.text)
                        if mail.claimedApproval {
                            T("✕ Onay Sayılmadı. Bu mesaj başka ajandan geldi, kayıtlı bir onayınız yok.", color: Theme.palette.err)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: Detail pane

struct DetailTabs: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let info: SessionInfo
    @ObservedObject var model = AppModel.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tabs are a choice, so they use the shared selector; the actions below stay buttons.
            // Both rows sit 16 in, like the content under the line.
            HStack(spacing: 8) {
                Seg(options: [(0, "Model"), (1, "Bağlantılar"), (2, "Yetkiler")], value: $model.detailTab)
                Spacer(minLength: 0)
            }
            .padding(16)
            HStack(spacing: 8) {
                Btn("Değişiklikler", kind: .plain) { Commands.perform("changes") }
                Btn("Tarayıcı", kind: .plain, key: "⌘⇧D") { Commands.perform("browser") }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            Line().padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.detailTab {
                    case 1: LinksTab(info: info)
                    case 2: PermissionsTab(info: info)
                    default: ModelTab(info: info)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct LimitBars: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let snapshot: LimitSnapshot?
    var body: some View {
        if let snapshot {
            if let window = snapshot.fiveHour { bar("5 Saatlik", window) }
            if let window = snapshot.sevenDay { bar("7 Günlük", window) }
            Dim("Görüldü: \(snapshot.seenAt.formatted(date: .omitted, time: .shortened))")
        } else {
            Dim("Henüz Bilinmiyor. İlk Yanıttan Sonra Görünür.")
        }
    }
    private func bar(_ title: String, _ window: LimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                T(title, color: Theme.palette.text2, style: .secondary)
                T("%\(Int(window.usedPercent))", style: .secondary)
                Spacer()
                if let resets = window.resetsAt { Dim(TimeText.reset(resets)) }
            }
            Meter(percent: window.usedPercent, warn: window.usedPercent >= 90)
        }
    }
}

enum TimeText {
    static func reset(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EEEE HH:mm"
        return formatter.string(from: date) + " Sıfırlanır"
    }
}

struct ModelTab: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let info: SessionInfo
    @ObservedObject var settings = SettingsStore.shared
    @State private var flowOpen = SettingsStore.shared.settings.flowStartsOpen
    var body: some View {
        if info.tool == .terminal {
            Dim("Bu oturum düz terminal. Model bilgisi yok.")
        }
        if info.tool == .antigravity {
            // Rows of one group sit closer than the 16 between groups.
            VStack(alignment: .leading, spacing: 8) {
                T("Bu Programdan Ne Gelir", bold: true)
                ForEach(Array(Self.antigravityRows.enumerated()), id: \.offset) { _, row in
                    HStack { T(row.0); Spacer(); Dim(row.1) }
                }
            }
            Dim("Limit için programın kendi ekranı: /usage. Enterm bu değeri okuyamıyor, çubuk çizmez.")
            AntigravityHookCard(cwd: info.cwd)
        }
        if info.tool == .claude || info.tool == .codex {
            VStack(alignment: .leading, spacing: 8) {
                T("Bu Oturum", bold: true)
                row("Model", info.model ?? "Henüz Bilinmiyor")
                if let effort = info.effort { row("Efor", SessionText.effortTitle(effort)) }
                if let tokens = info.contextTokens { row("Bağlam", SessionText.shortTokens(tokens) + " Token") }
                if let cost = info.costUSD { row("Liste Fiyatıyla", String(format: "$%.2f", cost)) }
            }
            if info.tool == .codex, info.hooksTrusted != true {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        T("Codex Durumu İçin Onayınız Gerekiyor", bold: true)
                        Dim("Bu onay olmadan \"onay istiyor\" durumu görünmez, \"bitti\" yalnız tur sonunda gelir. Codex yine çalışır. Bu terminalde /hooks yazıp Enterm kancalarına güvenin. Tanım değişirse yeniden sorulur.")
                        Btn("/hooks Yaz", kind: .primary) {
                            AppModel.shared.connection.sendInput(number: info.number, bytes: Data("/hooks\r".utf8))
                        }
                    }
                    .padding(12)
                }
            }
        }
        if info.tool == .claude {
            HStack {
                T("Akış", bold: true)
                Spacer()
                Btn(flowOpen ? "Akışı Kapat" : "Akışı Aç", kind: .plain) { flowOpen.toggle() }
            }
            if flowOpen { FlowView(info: info) }
        }
        if info.tool == .claude {
            Line()
            T("Hesap Kullanımı", bold: true)
            LimitBars(snapshot: info.limit)
            Line()
            ModelPlanEditor(info: info)
        }
        if info.tool == .codex {
            Line()
            T("Hesap Kullanımı", bold: true)
            LimitBars(snapshot: AccountStore.shared.account(id: info.accountID ?? "system-codex")?.lastLimit)
            Dim("Codex'in deneysel app-server arayüzünden okunur, model çalıştırmaz.")
        }
        Btn("Maliyet Görünümü", kind: .plain) { AppModel.shared.page = .cost }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { T(title); Spacer(); Dim(value) }
    }

    static let antigravityRows = [("Model", "Program Bildirir"), ("Çalışıyor, Bitti", "Kısmen · Kanca Onayıyla"), ("Sürdürme", "Var"),
                                  ("5 Saatlik, Haftalık Limit", "Limit Bilinmiyor"), ("Limit Doldu Olayı", "Gelmez"), ("Token", "Bilinmiyor"),
                                  ("Alt Ajan Ağacı", "Gelmez"), ("Birden Çok Hesap", "Şimdilik Yok")]
}

/// Antigravity reads hooks only from files. Enterm writes one small file, in this folder, after asking.
struct AntigravityHookCard: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let cwd: String
    @State private var written = false
    var body: some View {
        let path = cwd + "/.agents/hooks.json"
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                T("Antigravity Durumu İçin Onayınız Gerekiyor", bold: true)
                Dim("\"Çalışıyor\" ve \"Bitti\" durumları için Enterm bu klasöre küçük bir dosya yazar. Onaylamazsanız program yine çalışır.")
                T(".agents/hooks.json")
                if written || FileManager.default.fileExists(atPath: path) {
                    T("✓ Yazıldı. Dosya Sizindir, Silebilirsiniz.", color: Theme.palette.add)
                } else {
                    Btn("Bu Klasöre Yaz", kind: .primary) {
                        written = AntigravityHooks.write(to: path)
                    }
                }
            }
            .padding(12)
        }
    }
}

enum AntigravityHooks {
    static func write(to path: String) -> Bool {
        guard !FileManager.default.fileExists(atPath: path), let exe = Bundle.main.executableURL else { return false }
        let cli = exe.deletingLastPathComponent().appendingPathComponent("enterm").path
        let entry: [String: Any] = ["hooks": [["type": "command", "command": "'\(cli)' hook agy"]]]
        let object: [String: Any] = ["hooks": ["Stop": [entry], "PreInvocation": [entry]]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else { return false }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: path, contents: data) else { return false }
        Uninstaller.remember(hookFile: path)
        return true
    }
}

struct ModelPlanEditor: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let info: SessionInfo
    @ObservedObject var settings = SettingsStore.shared
    @State private var manual = false
    @State private var plan = ModelPlan()
    /// The first choice, empty, leaves it to Claude Code's own setting.
    static let models = ["", "opus", "sonnet", "haiku", "fable"]
    static let efforts = ["", "low", "medium", "high", "max"]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            T("Model Davranışı", bold: true)
            Seg(options: [(false, "Otomatik"), (true, "Elle")], value: $manual)
            if manual {
                picker("Ana İş", selection: $plan.main, values: Self.models)
                picker("Efor", selection: $plan.mainEffort, values: Self.efforts, titled: true)
                picker("Alt Ajanlar", selection: $plan.subagents, values: Self.models)
                // Only models that can advise this main model: never a weaker one.
                picker("Danışman", selection: $plan.advisor, values: ModelPlan.advisors(for: plan.main))
                Toggle(isOn: $plan.useAdvisor) { T("Danışmanı Kullan") }.toggleStyle(.checkbox)
                Dim("Danışman her çağrıda tüm konuşmayı okur ve limitten yer. Ana iş bu oturuma hemen uygulanır, alt ajan ve danışman yeni oturumda geçerli olur.")
                HStack {
                    Btn("Bu Oturuma Uygula", kind: .primary) { apply() }
                        .disabled(plan.main.isEmpty)
                    Btn("Yeni Oturumların Varsayılanı", kind: .plain) { settings.settings.defaultPlan = plan }
                }
            } else if settings.settings.defaultPlan == ModelPlan() {
                Dim("Model ve efor Claude Code'daki kendi ayarınızdan gelir. Enterm kendiliğinden model seçmez.")
            } else {
                Dim("Yeni oturumlar sizin kaydettiğiniz seçimle açılır: \(Self.summary(settings.settings.defaultPlan)).")
                Btn("Claude Code'un Ayarına Dön", kind: .plain) {
                    settings.settings.defaultPlan = ModelPlan()
                    plan = ModelPlan()
                }
            }
        }
        .onAppear { plan = settings.settings.defaultPlan }
        // Turning to Elle with nothing chosen yet starts from the suggestion, not from empty fields.
        .onChange(of: manual) { value in
            if value, plan == ModelPlan() { plan = .suggested }
        }
        .onChange(of: plan.main) { main in
            let allowed = ModelPlan.advisors(for: main)
            if !allowed.contains(plan.advisor), let first = allowed.first { plan.advisor = first }
        }
    }
    static func summary(_ plan: ModelPlan) -> String {
        var parts: [String] = []
        if !plan.main.isEmpty { parts.append("Ana İş \(plan.main.capitalized)") }
        if !plan.mainEffort.isEmpty { parts.append("Efor \(SessionText.effortTitle(plan.mainEffort))") }
        if !plan.subagents.isEmpty { parts.append("Alt Ajan \(plan.subagents.capitalized)") }
        if plan.useAdvisor { parts.append("Danışman \(plan.advisor.capitalized)") }
        return parts.isEmpty ? "Claude Code'un Ayarı" : parts.joined(separator: " · ")
    }

    private func picker(_ title: String, selection: Binding<String>, values: [String], titled: Bool = false) -> some View {
        HStack {
            T(title)
            Spacer()
            Picker("", selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(value.isEmpty ? "Claude Code'un Ayarı" : (titled ? SessionText.effortTitle(value) : value.capitalized)).font(Theme.swiftFont()).tag(value)
                }
            }
            .frame(width: 150)
        }
    }
    /// Uses the official slash command, typed into the session like the user would.
    private func apply() {
        AppModel.shared.connection.sendInput(number: info.number, bytes: Data("/model \(plan.main)\r".utf8))
    }
}

struct LinksTab: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let info: SessionInfo
    @ObservedObject var links = LinkStore.shared
    @ObservedObject var model = AppModel.shared
    @State private var target: UInt32?
    var body: some View {
        let own = links.links.filter { $0.from == info.id || $0.to == info.id }
        // Items of one group sit closer than the 16 between groups.
        VStack(alignment: .leading, spacing: 8) {
            T("\(model.title(for: info)) Bağlantıları", bold: true)
            if own.isEmpty {
                Dim("Bağlantı yok. Tuvalde kutunun kenarından sürükleyin ya da aşağıdan seçin.")
            } else {
                VStack(alignment: .leading, spacing: MenuList<EmptyView>.gap) {
                    ForEach(own) { link in
                        let otherID = link.from == info.id ? link.to : link.from
                        let other = model.sessions.first { $0.id == otherID }
                        MenuRow(title: "\(link.from == info.id ? "→" : "←") \(other.map { model.title(for: $0) } ?? "Kapalı Oturum")",
                                note: "\(link.permission.title) · \(link.bothWays ? "Çift Yön" : "Tek Yön")") {
                            model.overlay = .linkDetail(link.id)
                        }
                        // The row's own 10 would push its text past the title above it.
                        .padding(.horizontal, -10)
                    }
                }
            }
        }
        let others = model.sessions.filter { $0.number != info.number }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                T("Yeni Bağlantı", bold: true)
                ForEach(others) { other in
                    Btn("→ \(model.title(for: other))", kind: .plain) {
                        model.overlay = .linkPermission(from: info.number, to: other.number)
                    }
                }
            }
        }
        Line()
        Dim("Bağlantı yetki vermez. Bir ajan, kendi yetkisinde olmayan işi başka ajana devredemez. Başka ajanın mesajı onay yerine geçmez.")
        Btn("Mesaj Geçmişi", kind: .plain) { model.page = .messages }
    }
}

struct PermissionsTab: View {
    let info: SessionInfo
    @State private var book = PermissionBook.load()
    private let categories: [(PermissionCategory, String)] = [
        (.editFiles, "Çalışma Alanı İçinde"), (.deleteFiles, "rm, git clean, Dosya Silme"), (.ssh, "Sunucu Bağlantıları"),
        (.internet, "Aynı Adres Bir Kez Sorulur"), (.delegate, "Yalnız Kendi Yetkisindeki İşi Devreder"),
        (.pushDeploy, "git push, Yayın Komutları"), (.command, "Öteki Komutlar"),
    ]
    var body: some View {
        T("Yetki Kartı", bold: true)
        // Five names do not fit one line of the side panel: they wrap into rows, each name whole.
        WrapChoice(options: PermissionTemplate.allCases.map { ($0, $0.title) },
                   selected: PermissionTemplate.allCases.first { book.card(for: info.id).modes == $0.card.modes }) { template in
            book.cards[info.id] = template.card
            save()
        }
        ForEach(categories, id: \.0) { category, note in
            VStack(alignment: .leading, spacing: 4) {
                T(category.title)
                Dim(note)
                Seg(options: PermissionMode.allCases.map { ($0, $0.title) }, value: Binding(
                    get: { book.card(for: info.id).mode(category) },
                    set: { value in
                        var card = book.card(for: info.id)
                        card.modes[category] = value
                        book.cards[info.id] = card
                        save()
                    }))
            }
        }
        Btn("SSH Sunucu Listesi: \(book.card(for: info.id).sshRules.count)", kind: .plain) { AppModel.shared.overlay = .sshList(info.id) }
        if !book.rememberedHosts.isEmpty {
            T("Hatırlanan Adresler", bold: true)
            ForEach(book.rememberedHosts, id: \.self) { host in
                HStack {
                    T(host)
                    Spacer()
                    Btn("Sil", kind: .plain) {
                        book.rememberedHosts.removeAll { $0 == host }
                        save()
                    }
                }
            }
        }
        Dim("Değişiklik bir sonraki komuttan itibaren geçerli olur. Kapalı iş başka ajana devredilemez.")
    }
    private func save() {
        book.save()
        AppModel.shared.connection.send(WireMessage(op: "reloadPermissions"))
    }
}

// MARK: New session with options

struct NewSessionOptions: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var accounts = AccountStore.shared
    @State private var name = ""
    @State private var folder = ""
    @State private var tool = ToolKind.claude
    @State private var accountID = ""
    @State private var template = SettingsStore.shared.settings.defaultTemplate
    @State private var error: String?
    var body: some View {
        Panel(border: error == nil ? nil : Theme.palette.err) {
            PanelHeader(title: "Yeni Oturum: Seçenekler") { Dim("Hepsi Hazır, İstediğinizi Değiştirin") }
            VStack(alignment: .leading, spacing: 12) {
                field("Oturum Adı") { EntermField(placeholder: "İsteğe Bağlı", text: $name) }
                field("Klasör") {
                    HStack {
                        EntermField(placeholder: "~/projeler/magaza", text: $folder)
                        Btn("Seç", kind: .plain) { chooseFolder() }
                    }
                }
                if let error { T(error, color: Theme.palette.err) }
                field("Program") { ChoiceMenu(options: ([.terminal] + ToolKind.programs).map { ($0, ToolCatalog.shared.pickerTitle($0)) }, value: $tool) }
                if tool != .terminal {
                    let usable = accounts.accounts.filter { $0.tool == tool }
                    if usable.count > 1 {
                        field("Hesap") { ChoiceMenu(options: usable.map { ($0.id, accountTitle($0)) }, value: $accountID) }
                    }
                    field("Yetki Şablonu") { Seg(options: PermissionTemplate.allCases.map { ($0, $0.title) }, value: $template) }
                }
            }
            .padding(20)
            DialogButtons(note: "Tab Alan Değiştirir") {
                Btn("Vazgeç", kind: .plain, key: "Esc") { model.overlay = nil }
                Btn("Başlat", kind: .primary, key: "⏎") { start() }.keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 640)
        .onAppear {
            folder = model.displayPath(model.focusedInfo?.cwd ?? NSHomeDirectory())
            accountID = "system-claude"
        }
        .onChange(of: tool) { value in accountID = "system-\(value.rawValue)" }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            T(title)
            content()
        }
    }
    private func accountTitle(_ account: Account) -> String {
        if let window = account.lastLimit?.fiveHour { return "\(account.name) · %\(Int(window.usedPercent)) Dolu" }
        return account.name
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { folder = model.displayPath(url.path) }
    }
    private func start() {
        let path = (folder as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            error = "Klasör Bulunamadı."
            return
        }
        model.overlay = nil
        let chosenName = name.isEmpty ? nil : name
        if tool == .terminal {
            model.create(SessionSpec(name: chosenName, tool: .terminal, cwd: path, rows: 30, cols: 100))
            return
        }
        let selected = accountID.hasPrefix("system-") ? nil : accountID
        let card = template.card
        ToolLauncher.start(tool, cwd: path, name: chosenName, accountID: selected) { info in
            var book = PermissionBook.load()
            book.cards[info.id] = card
            book.save()
            AppModel.shared.connection.send(WireMessage(op: "reloadPermissions"))
        }
    }
}

// MARK: Limit reached

enum LimitActions {
    struct Action {
        let title: String
        let note: String
        let run: () -> Void
    }

    private static func conversationNote(_ info: SessionInfo) -> String {
        if let tokens = info.contextTokens { return "Konuşma \(SessionText.shortTokens(tokens)) Token · İlk Mesajda Baştan Okunur" }
        return "İlk Mesajda Konuşma Baştan Okunur"
    }

    static func options(for info: SessionInfo) -> [Action] {
        let accounts = AccountStore.shared
        var actions: [Action] = []
        let others = accounts.accounts.filter { $0.tool == .claude && $0.id != (info.accountID ?? "system-claude") && $0.kind != .apiKey }
        for account in others {
            var limit = "Limit Henüz Bilinmiyor"
            if let snapshot = account.lastLimit, let window = snapshot.fiveHour ?? snapshot.sevenDay {
                let minutes = Int(Date().timeIntervalSince(snapshot.seenAt) / 60)
                limit = "%\(Int(window.usedPercent)) Dolu · \(minutes) dk Önce"
            }
            actions.append(Action(title: "Başka Hesapla Devam: \(account.name)", note: "\(limit) · \(conversationNote(info))") {
                LimitActions.resume(info, accountID: account.id)
            })
        }
        for account in accounts.accounts where account.kind == .apiKey && account.tool == .claude {
            actions.append(Action(title: "API Anahtarıyla Devam: \(account.name)", note: "Kullanıma Göre · Yalnız Bu Oturuma · \(conversationNote(info))") {
                LimitActions.resume(info, accountID: account.id)
            })
        }
        actions.append(Action(title: "Codex'e Özetle Geçir", note: "Yeni Oturum · Özet Aktarılır · Konuşma Geçmişi Taşınmaz") {
            LimitActions.summarizeToCodex(info)
        })
        actions.append(Action(title: "Sıfırlanmayı Bekle", note: "Beklerken Limitten Yemez") { AppModel.shared.overlay = nil })
        return actions
    }

    /// After a conversation did not open under the other account.
    static func resumeOptions(for number: UInt32) -> [Action] {
        let model = AppModel.shared
        guard let info = model.sessions.first(where: { $0.number == number }) else { return [] }
        var actions = [Action(title: "Özetle Yeni Oturum", note: "Son Ekran Aktarılır · Konuşma Geçmişi Taşınmaz") {
            model.overlay = nil
            var tail = WireMessage(op: "tail")
            tail.number = number
            model.connection.request(tail) { reply in
                let summary = (reply.text ?? "").suffix(3000)
                ToolLauncher.start(.claude, cwd: info.cwd, accountID: info.accountID,
                                   extraArguments: NotFoundActions.shellQuote("Önceki oturumun son ekranı aşağıda. Kaldığın yerden devam et:\n\(summary)"))
            }
        }]
        for account in AccountStore.shared.accounts where account.kind == .apiKey && account.tool == .claude {
            actions.append(Action(title: "API Anahtarıyla Aynı Konuşma: \(account.name)", note: "Kullanıma Göre · İlk Mesajda Baştan Okunur") {
                resume(info, accountID: account.id)
            })
        }
        actions.append(Action(title: "Sıfırlanmayı Bekle", note: "Beklerken Limitten Yemez") { model.overlay = nil })
        return actions
    }

    static var current: [() -> Void] = []
    static func perform(index: Int) {
        guard index >= 0, index < current.count else { return }
        current[index]()
    }

    /// Continues the same conversation under another account, by the user's choice only.
    static func resume(_ info: SessionInfo, accountID: String) {
        let model = AppModel.shared
        model.overlay = nil
        let target = info.transcriptPath ?? info.toolSessionID
        let arguments = target.map { "--resume \(NotFoundActions.shellQuote($0))" } ?? "--continue"
        let old = info.number
        LimitWatch.shared.noteSwitch(from: info)
        ToolLauncher.start(.claude, cwd: info.cwd, name: info.name.isEmpty ? nil : info.name, accountID: accountID, extraArguments: arguments) { created in
            LimitWatch.shared.noteResume(created.number)
            AppModel.shared.close(old)
        }
    }

    static func summarizeToCodex(_ info: SessionInfo) {
        let model = AppModel.shared
        model.overlay = nil
        var tail = WireMessage(op: "tail")
        tail.number = info.number
        model.connection.request(tail) { reply in
            let summary = (reply.text ?? "").suffix(3000)
            let prompt = "Başka bir programda süren iş limite takıldı. Kaldığı yerden devam et. Son ekran:\n\(summary)"
            ToolLauncher.start(.codex, cwd: info.cwd, name: info.name.isEmpty ? nil : info.name,
                               extraArguments: NotFoundActions.shellQuote(prompt))
        }
    }
}

struct LimitDialog: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let number: UInt32
    @ObservedObject var model = AppModel.shared
    @ObservedObject var accounts = AccountStore.shared
    var body: some View {
        let info = model.sessions.first { $0.number == number }
        Panel(border: Theme.palette.limit) {
            PanelHeader(title: "\(info.map { model.title(for: $0) } ?? "Oturum"): Limit Doldu") { StatusBadge(status: .limitReached) }
            if let info {
                let waiting = waitWithin24Hours(info)
                let actions = LimitActions.options(for: info)
                VStack(alignment: .leading, spacing: 8) {
                    if let waiting {
                        T("\(waiting)'da Sıfırlanınca Kendiliğinden Sürer", bold: true)
                        Dim("Aynı Hesapla · İzin İstemleri Yine Sorulur · Esc İptal. Beklemek istemezseniz:")
                    } else {
                        Dim("Limit doldu. Çalışan iş kaybolmadı, oturum olduğu yerde bekliyor.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 20, leading: 20, bottom: 0, trailing: 20))
                // MenuList keeps the row text at 20, in line with the lines above it.
                MenuList {
                    ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                        MenuRow(title: action.title, note: action.note, key: "\(index + 1)") { action.run() }
                    }
                }
                DialogButtons(note: "Hesap Değişimi Yalnız Sizin Seçiminizle") {
                    Btn("Kapat", kind: .plain, key: "Esc") { model.overlay = nil }
                }
                .onAppear { LimitActions.current = actions.map(\.run) }
            }
        }
        .frame(width: 640)
    }

    private func waitWithin24Hours(_ info: SessionInfo) -> String? {
        guard info.tool == .claude else { return nil }
        let windows = [info.limit?.fiveHour, info.limit?.sevenDay].compactMap { $0 }
        guard let full = windows.first(where: { $0.usedPercent >= 100 }) ?? windows.max(by: { $0.usedPercent < $1.usedPercent }),
              let resets = full.resetsAt, resets.timeIntervalSinceNow < 86400 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: resets)
    }
}

// MARK: SSH list

struct SSHListDialog: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let sessionID: String
    @ObservedObject var model = AppModel.shared
    @State private var book = PermissionBook.load()
    @State private var newHost = ""
    private var card: PermissionCard { book.card(for: sessionID) }
    var body: some View {
        Panel {
            PanelHeader(title: "SSH: \(model.sessions.first { $0.id == sessionID }.map { model.title(for: $0) } ?? "")") { Dim("Listede Olmayana Bağlanamaz") }
            VStack(alignment: .leading, spacing: 12) {
                if card.sshRules.isEmpty { Dim("Liste boş. Boşken yalnız kartın genel SSH ayarı geçerlidir.") }
                ForEach(card.sshRules) { rule in
                    HStack {
                        T(rule.host)
                        Spacer()
                        Seg(options: PermissionMode.allCases.map { ($0, $0.title) }, value: Binding(
                            get: { rule.mode },
                            set: { value in update { rules in
                                if let index = rules.firstIndex(where: { $0.host == rule.host }) { rules[index].mode = value }
                            } }))
                        Btn("Sil", kind: .plain) { update { $0.removeAll { $0.host == rule.host } } }
                    }
                }
                HStack {
                    EntermField(placeholder: "Sunucu Ekle: staging.example.com", text: $newHost)
                    Btn("Ekle") {
                        guard !newHost.isEmpty else { return }
                        let host = newHost
                        update { rules in if !rules.contains(where: { $0.host == host }) { rules.append(SSHHostRule(host: host)) } }
                        newHost = ""
                    }
                    Btn("~/.ssh/config", kind: .plain) { importConfig() }
                }
                if card.mode(.ssh) == .deny { T("Bu kartta SSH kapalı. Liste, kart açılınca geçerli olur.", color: Theme.palette.limit) }
                Dim("Anahtarlar ~/.ssh içinde kalır, Enterm okumaz.")
            }
            .padding(20)
            DialogButtons {
                Btn("Kapat", kind: .plain, key: "Esc") { model.overlay = nil }
            }
        }
        .frame(width: 640)
    }
    private func update(_ change: (inout [SSHHostRule]) -> Void) {
        var current = book.card(for: sessionID)
        change(&current.sshRules)
        book.cards[sessionID] = current
        book.save()
        model.connection.send(WireMessage(op: "reloadPermissions"))
    }
    private func importConfig() {
        let text = (try? String(contentsOfFile: NSHomeDirectory() + "/.ssh/config", encoding: .utf8)) ?? ""
        let hosts = SSHCommand.hosts(fromConfig: text)
        update { rules in
            for host in hosts where !rules.contains(where: { $0.host == host }) { rules.append(SSHHostRule(host: host)) }
        }
    }
}
