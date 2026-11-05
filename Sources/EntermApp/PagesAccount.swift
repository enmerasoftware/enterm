import AppKit
import EntermCore
import SwiftUI

struct AccountsPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = AccountStore.shared
    @ObservedObject var model = AppModel.shared
    var body: some View {
        PageFrame(title: nil) {
            HStack(alignment: .top) {
                PageTitle(text: "Hesaplar")
                Spacer()
                Btn("API Anahtarı Ekle") { model.page = .apiKey }
                Btn("Hesap Ekle", kind: .primary) { model.page = .accountAdd }
            }
            Panel {
                ForEach(store.accounts) { account in
                    AccountRow(account: account, sessions: model.sessions.filter { ($0.accountID ?? "system-\($0.tool.rawValue)") == account.id }.count)
                    Line()
                }
            }
            Dim("Limit dolunca oturum durur, iş kaybolmaz. Hesap değişimini her seferinde siz seçersiniz.")
        }
        .onAppear { store.refreshCodex() }
    }
}

struct AccountRow: View {
    let account: Account
    let sessions: Int
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                T(account.tool.title)
                Dim(account.name)
            }
            .frame(width: 200, alignment: .leading)
            switch (account.tool, account.kind) {
            case (_, .apiKey):
                Dim("Abonelik Limiti Yok · Kullanıma Göre")
            case (.antigravity, _):
                Dim("Limit Bilinmiyor")
            default:
                if let snapshot = account.lastLimit {
                    VStack(alignment: .leading, spacing: 8) { LimitBars(snapshot: snapshot) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Dim("Henüz Bilinmiyor · İlk Yanıttan Sonra Görünür")
                }
            }
            Spacer(minLength: 0)
            Dim("\(sessions) Oturum")
            if account.kind != .system {
                Btn("Kaldır", kind: .plain) { AccountStore.shared.remove(account.id) }
            }
        }
        .padding(12)
    }
}

/// The login happens on the provider's own screen, in a separate configuration directory.
struct AccountAddPage: View {
    @ObservedObject var model = AppModel.shared
    @State private var tool = ToolKind.claude
    @State private var name = ""
    @State private var started: Account?
    var body: some View {
        PageFrame(title: "Hesap Ekle") {
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Seg(options: [(ToolKind.claude, "Claude Code"), (ToolKind.codex, "Codex")], value: $tool)
                    EntermField(placeholder: "Bu Hesabın Adı: İş, Kişisel", text: $name)
                    if started == nil {
                        Dim("Giriş sağlayıcının kendi ekranında tamamlanır. Enterm abonelik şifresi ya da oturum token'ı görmez. Hesap ayrı bir yapılandırma dizininde durur, oturumu resmi program saklar.")
                        Btn("Girişi Başlat", kind: .primary) { start() }
                    } else {
                        T("● Giriş Bekleniyor", bold: true)
                        Dim("Yeni açılan terminalde resmi program giriş ekranını gösterir. Bitince burayı kapatın. Hesabın yüzdesi ilk yanıttan sonra görünür.")
                        Btn("Giriş Bitti", kind: .primary) { model.page = .accounts }
                    }
                }
                .padding(12)
            }
        }
    }
    private func start() {
        started = AccountStore.shared.beginLogin(tool: tool, name: name)
    }
}

struct ApiKeyPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @State private var tool = ToolKind.claude
    @State private var name = ""
    @State private var key = ""
    @State private var cap = ""
    @State private var result: String?
    var body: some View {
        PageFrame(title: "API Anahtarı Ekle") {
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Dim("Kullanıma Göre Ücretlenir")
                    Seg(options: [(ToolKind.claude, "Anthropic"), (ToolKind.codex, "OpenAI")], value: $tool)
                    EntermField(placeholder: "Ad: Yedek Anahtar", text: $name)
                    SecureField("", text: $key, prompt: Text("Anahtar").foregroundColor(Color(Theme.palette.dim)))
                        .textFieldStyle(.plain)
                        .font(Theme.swiftFont())
                        .foregroundColor(Color(Theme.palette.fg))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(Theme.palette.line2)))
                    EntermField(placeholder: "Aylık Harcama Sınırı (USD), İsteğe Bağlı: Hatırlatma İçindir", text: $cap)
                    Dim("Anahtar macOS Anahtar Zinciri'nde durur, ekranda gösterilmez, günlüğe yazılmaz. Yalnız seçtiğiniz oturuma verilir.")
                    if let result { T(result, color: Theme.palette.err) }
                    HStack {
                        Btn("Vazgeç", kind: .plain, key: "Esc") { model.page = .accounts }
                        Btn("Kaydet", kind: .primary, key: "⏎") { save() }
                    }
                }
                .padding(12)
            }
        }
    }
    private func save() {
        guard !key.isEmpty else {
            result = "Anahtar Boş."
            return
        }
        let account = AccountStore.shared.addKey(tool: tool, name: name.isEmpty ? "Yedek Anahtar" : name, cap: Double(cap))
        if Keychain.save(key, account: account.id) {
            key = ""
            model.page = .accounts
        } else {
            AccountStore.shared.remove(account.id)
            result = "Anahtar Zinciri'ne Yazılamadı."
        }
    }
}

struct InboxPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var inbox = Inbox.shared
    @ObservedObject var power = PowerCenter.shared
    var body: some View {
        let pending = model.sessions.compactMap(\.pendingApproval)
        let asking = model.sessions.filter { $0.status == .needsApproval && $0.pendingApproval == nil }
        PageFrame(title: "Onay Kutusu") {
            T("Sizi Bekleyenler", bold: true)
            if pending.isEmpty && asking.isEmpty && inbox.limits.isEmpty && power.queue.isEmpty {
                Dim("Bekleyen Bir Şey Yok")
            }
            ForEach(asking) { info in
                Panel(border: Theme.palette.need) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            T("◆ \(model.title(for: info))", color: Theme.palette.need, bold: true)
                            Dim(info.lastActivity ?? "Terminalde Yanıtınızı Bekliyor").lineLimit(2)
                        }
                        Spacer()
                        Btn("Terminale Git", kind: .primary) { Commands.perform("goto:\(info.number)") }
                    }
                    .padding(12)
                }
            }
            ForEach(pending) { request in
                let info = model.sessions.first { $0.id == request.sessionID }
                Panel(border: Theme.palette.need) {
                    VStack(alignment: .leading, spacing: 8) {
                        T("◆ \(info.map { model.title(for: $0) } ?? "Oturum"): \(request.category.title)", color: Theme.palette.need, bold: true)
                        ApprovalCommand(text: request.summary, lines: 4)
                        HStack {
                            Btn("İzin Ver", kind: .primary) { Approvals.decide(id: request.id, decision: "allow", remember: request.category == .internet) }
                            Btn("Reddet") { Approvals.decide(id: request.id, decision: "deny") }
                            Btn("Ayrıntı", kind: .plain) { model.overlay = .approval(request.id) }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(inbox.limits) { item in
                Panel(border: Theme.palette.limit) {
                    HStack {
                        VStack(alignment: .leading) {
                            T("■ \(item.title)", color: Theme.palette.limit, bold: true)
                            Dim(item.detail)
                        }
                        Spacer()
                        if let number = item.sessionNumber {
                            Btn("Seçenekleri Gör") {
                                model.page = nil
                                model.overlay = .limit(number)
                            }
                        }
                    }
                    .padding(12)
                }
            }
            ForEach(power.queue) { queued in
                Panel {
                    HStack {
                        VStack(alignment: .leading) {
                            T("◷ \(queued.spec.tool.title) Sırada", bold: true)
                            Dim("\(queued.reason). Yer Açılınca Kendiliğinden Başlar, Token Harcamıyor.")
                        }
                        Spacer()
                        Btn("Yine De Başlat") { power.startQueued(force: queued) }
                    }
                    .padding(12)
                }
            }
            if !inbox.finished.isEmpty {
                HStack {
                    T("Biten İşler", bold: true)
                    Spacer()
                    Btn("Tümünü Okundu Say", kind: .plain) { inbox.finished.removeAll() }
                }
                ForEach(inbox.finished) { item in
                    HStack(alignment: .top) {
                        T("\(item.symbol) \(item.title):")
                        Dim(item.detail).lineLimit(2)
                        Spacer()
                        Dim(item.at.formatted(date: .omitted, time: .shortened))
                    }
                }
            }
        }
    }
}

struct CostPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    var body: some View {
        PageFrame(title: "Model Ve Maliyet") {
            Panel {
                ForEach(model.sessions.filter { $0.tool != .terminal }) { info in
                    HStack {
                        T(model.title(for: info)).frame(width: 240, alignment: .leading).lineLimit(1)
                        Dim(info.model ?? info.tool.title).frame(width: 160, alignment: .leading)
                        Dim(info.contextTokens.map { SessionText.shortTokens($0) + " Bağlam" } ?? "Bilinmiyor")
                        Spacer()
                        Dim(info.costUSD.map { String(format: "$%.2f Liste Fiyatı", $0) } ?? "")
                    }
                    .padding(12)
                    Line()
                }
            }
            Dim("Yalnız bu oturumun program bildirdiği rakamlar. Limit yüzdesi oturum başına ayrılamaz. Danışman ayrı sayımı iç biçime dayandığı için bu sürümde yok.")
            Dim("Boşta duran ajan token harcamaz.")
        }
    }
}

struct SettingsPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @State var tab: SettingsTab
    @State private var search = ""
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var power = PowerCenter.shared

    private var groups: [(title: String, tabs: [SettingsTab])] {
        let needle = search.lowercased(with: Locale(identifier: "tr_TR")).trimmingCharacters(in: .whitespaces)
        if needle.isEmpty { return SettingsTab.groups }
        return SettingsTab.groups.compactMap { group in
            let tabs = group.tabs.filter { $0.searchText.contains(needle) }
            return tabs.isEmpty ? nil : (group.title, tabs)
        }
    }

    var body: some View {
        let palette = Theme.palette
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Btn("Geri", kind: .plain, key: "Esc", icon: "chevron.left") { AppModel.shared.goBack() }
                    Spacer()
                }
                .padding(.leading, 72)
                .frame(height: 44)
                EntermField(placeholder: "Ayarlarda Ara", text: $search)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                T(group.title, color: palette.text3, style: .hint, weight: .semibold).padding(.horizontal, 8).padding(.bottom, 4)
                                ForEach(group.tabs) { item in
                                    sideItem(item.title, icon: item.icon, selected: tab == item) { tab = item }
                                }
                            }
                        }
                        if groups.isEmpty { Dim("Sonuç Yok").padding(.horizontal, 8) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .frame(width: 240)
            .background(Color(palette.surface1))
            .overlay(alignment: .trailing) { Rectangle().fill(Color(palette.hair)).frame(width: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !tab.bringsOwnTitle { PageTitle(text: tab.title) }
                    detail
                }
                .padding(EdgeInsets(top: 44, leading: 32, bottom: 40, trailing: 32))
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(ZStack { Color(palette.surface0); CornerGlows(second: .bottomTrailing) })
        }
        .environment(\.embeddedPage, true)
        .background(Color(palette.surface0))
    }

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .programs: ProgramsSettings()
        case .accounts: AccountsPage()
        case .custom: CustomProgramsSettings()
        case .gateway: GatewaySettings()
        case .usage: UsageSettings()
        case .commits: CommitSettings()
        case .terminal: TerminalSettings()
        case .shell: ShellSettings()
        case .session: SessionSettings()
        case .behavior: BehaviorSettings()
        case .browser: BrowserSettings()
        case .appearance: AppearanceSettings()
        case .notch: NotchSettings()
        case .notifications: NotificationSettings()
        case .voice: VoiceSettings()
        case .shortcuts: ShortcutEditor()
        case .phone: PhonePage()
        case .ssh: RemotePage()
        case .power: powerSection
        case .security: security
        case .about: AboutSettings()
        }
    }

    private func sideItem(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Symbol(icon, color: selected ? Theme.palette.need : Theme.palette.text2)
                T(title, weight: selected ? .medium : .regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(selected ? Color(Theme.palette.fillSelected) : .clear)
            .cornerRadius(Theme.cornerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func line<Content: View>(_ title: String, _ note: String = "", @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                T(title)
                if !note.isEmpty { Dim(note).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            content()
        }
        .settingsRow()
    }

    private var security: some View {
        Panel {
            line("Yeni Oturumda Varsayılan Şablon", "Serbest: programın kendi kuralları geçerli, düz terminaldeki gibi") {
                Seg(options: PermissionTemplate.allCases.map { ($0, $0.title) }, value: Binding(
                    get: { PermissionBook.load().defaultTemplate },
                    set: { value in
                        var book = PermissionBook.load()
                        book.defaultTemplate = value
                        book.save()
                        store.settings.defaultTemplate = value
                        AppModel.shared.connection.send(WireMessage(op: "reloadPermissions"))
                    }))
            }
            line("Tek Tık Onay", "Program izin isteyince soru kutunun altında da çıkar. Programın kendi sorusu en çok 45 saniye bekler. Kapalıyken düz terminaldeki gibi hemen sorar.") {
                Seg(options: [(true, "Açık"), (false, "Kapalı")], value: $store.settings.oneClickApprovals)
            }
            line("Program Mesajı Onay Sayılmaz", "Bir programın başka programa yazdığı mesaj sizin onayınızın yerine geçmez") { T("Zorunlu", color: Theme.palette.text2) }
        }
    }

    private var powerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
            line("Düşük Güçlü Bilgisayar", "Hareket kapalı, odak dışındaki kutular seyrek güncellenir, tarayıcı açılmaz.") {
                Seg(options: [(false, "Kapalı"), (true, "Açık")], value: $power.settings.lowPower)
            }
            line("Bilgisayarın Gücünün En Çok Şu Kadarını Kullan") {
                Seg(options: [(25, "%25"), (50, "%50"), (75, "%75"), (100, "Sınırsız")], value: $power.settings.cpuLimit)
            }
            line("Aynı Anda En Çok Şu Kadar Oturum Çalışsın", "Fazlası Sırada bekler, çalışan iş durmaz.") {
                HStack {
                    Seg(options: [(true, "Otomatik"), (false, "Elle")], value: $power.settings.sessionsAutomatic)
                    if !power.settings.sessionsAutomatic {
                        Btn("−", kind: .plain) { power.settings.maxSessions = max(1, power.settings.maxSessions - 1) }
                        T("\(power.settings.maxSessions)")
                        Btn("+", kind: .plain) { power.settings.maxSessions += 1 }
                    } else {
                        Dim("\(power.effectiveMaxSessions)")
                    }
                }
            }
            }
            Dim("Bu bir üst hedeftir, kesin ölçüm değildir. Sınıra yaklaşınca yeni iş sıraya girer, arka plandaki oturumun önceliği düşer. İşlemciyle birlikte bellek baskısı da sayılır. Düz terminallere dokunulmaz.")
            T("Ağır İş Sırası", bold: true, style: .section)
            Panel { HeavyQueueList() }
            T("Şu Anki Kullanım", bold: true, style: .section)
            Panel {
            HStack { T("Enterm"); Spacer(); Dim(String(format: "%%%.1f · %.0f MB", power.enterm.cpu, power.enterm.memoryMB)) }.settingsRow()
            HStack { T("Claude Code, Codex Ve Antigravity"); Spacer(); Dim(String(format: "%%%.1f · %.0f MB", power.agents.cpu, power.agents.memoryMB)) }.settingsRow()
            HStack { T("Bellek Baskısı"); Spacer(); Dim(power.pressure.title) }.settingsRow()
            }
            HStack(spacing: 24) {
                Dim("Ajanların yükü Enterm'in elinde değildir. Aynı anda çalışan oturum sayısıyla azalır.").fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Btn("Yeniden Ölç") { power.measureUsage() }
            }
        }
        .onAppear { power.measureUsage() }
    }
}

struct ShortcutEditor: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @State private var book = ShortcutBook.load()
    @State private var capturing: String?
    @State private var message = ""
    @State private var monitor: Any?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
            ForEach(ShortcutBook.defaults, id: \.id) { item in
                HStack {
                    T(item.title)
                    Spacer()
                    if book.overrides[item.id] != nil {
                        Btn("Varsayılan", kind: .plain) {
                            book.overrides[item.id] = nil
                            commit()
                        }
                    }
                    Btn(capturing == item.id ? "Tuşa Basın" : (book.combo(for: item.id)?.display ?? ""), kind: capturing == item.id ? .selected : .outline) {
                        startCapture(item.id)
                    }
                }
                .settingsRow()
            }
            HStack { T("Oturum 1 İla 9"); Spacer(); Key("⌘1 - ⌘9") }.settingsRow()
            HStack { T("Konuşarak Yaz"); Spacer(); Key("⌃⌘ Basılı") }.settingsRow()
            HStack { T("İzin Ver, Reddet"); Spacer(); Key("Y N") }.settingsRow()
            }
            if !message.isEmpty { T(message, color: Theme.palette.err) }
            Dim("Terminal odaktayken tuşlar terminale gider, Esc çalışmayı keser. Kısayol ⌘ ya da ⌃ içermelidir, tek tuş terminale aittir.")
        }
        .onDisappear(perform: stopCapture)
    }
    private func startCapture(_ id: String) {
        stopCapture()
        capturing = id
        message = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 {
                stopCapture()
                return nil
            }
            let key = event.keyCode == 36 ? "\r" : (event.charactersIgnoringModifiers ?? "")
            let combo = KeyCombo(key, command: flags.contains(.command), shift: flags.contains(.shift), option: flags.contains(.option), control: flags.contains(.control))
            guard combo.isUsable else {
                message = "Kısayol ⌘ ya da ⌃ içermeli."
                return nil
            }
            if let conflict = book.conflict(for: combo, assigningTo: id) {
                message = "\(combo.display) Kullanılıyor: \(conflict)"
                return nil
            }
            book.overrides[id] = combo
            commit()
            stopCapture()
            return nil
        }
    }
    private func stopCapture() {
        capturing = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    private func commit() {
        book.save()
        (NSApp.delegate as? AppDelegate)?.buildMenu()
    }
}

struct HeavyQueueList: View {
    @ObservedObject var model = AppModel.shared
    var body: some View {
        if model.heavyQueue.isEmpty {
            DimRow("Sırada ağır iş yok. Derleme ve toplu test gibi komutlar ajanlar arasında tek tek çalışır (Claude Code).")
        }
        ForEach(Array(model.heavyQueue.enumerated()), id: \.element.id) { index, item in
            HStack {
                Mono("\(index + 1). \(item.name): \(item.command)").lineLimit(1)
                Spacer()
                Dim(item.running ? "● Çalışıyor" : "○ Sırada")
            }
            .settingsRow()
        }
    }
}

private struct DimRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Dim(text).fixedSize(horizontal: false, vertical: true).settingsRow() }
}
