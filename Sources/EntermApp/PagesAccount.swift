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
                ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Line() }
                    AccountRow(account: account, sessions: model.sessions.filter { ($0.accountID ?? "system-\($0.tool.rawValue)") == account.id }.count)
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
        Row {
            VStack(alignment: .leading, spacing: 2) {
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
    }
}

/// The login happens on the provider's own screen, in a separate configuration directory.
struct AccountAddPage: View {
    @ObservedObject var model = AppModel.shared
    @State private var tool = ToolKind.claude
    @State private var name = ""
    @State private var started: Account?
    var body: some View {
        PageFrame(title: "Hesap Ekle", centered: true) {
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Seg(options: [(ToolKind.claude, "Claude Code"), (ToolKind.codex, "Codex")], value: $tool)
                    EntermField(placeholder: "Bu Hesabın Adı: İş, Kişisel", text: $name)
                    if started == nil {
                        Dim("Giriş sağlayıcının kendi ekranında tamamlanır. Enterm abonelik şifresi ya da oturum token'ı görmez. Hesap ayrı bir yapılandırma dizininde durur, oturumu resmi program saklar.")
                        // The main action stands on the right, as at the foot of a dialog.
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Btn("Girişi Başlat", kind: .primary) { start() }
                        }
                    } else {
                        T("● Giriş Bekleniyor", bold: true)
                        Dim("Yeni açılan terminalde resmi program giriş ekranını gösterir. Bitince burayı kapatın. Hesabın yüzdesi ilk yanıttan sonra görünür.")
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Btn("Giriş Bitti", kind: .primary) { model.page = .accounts }
                        }
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
        PageFrame(title: "API Anahtarı Ekle", centered: true) {
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Dim("Kullanıma Göre Ücretlenir")
                    Seg(options: [(ToolKind.claude, "Anthropic"), (ToolKind.codex, "OpenAI")], value: $tool)
                    EntermField(placeholder: "Ad: Yedek Anahtar", text: $name)
                    SecureEntermField(placeholder: "Anahtar", text: $key)
                    EntermField(placeholder: "Aylık Harcama Sınırı (USD), İsteğe Bağlı: Hatırlatma İçindir", text: $cap)
                    Dim("Anahtar macOS Anahtar Zinciri'nde durur, ekranda gösterilmez, günlüğe yazılmaz. Yalnız seçtiğiniz oturuma verilir.")
                    if let result { T(result, color: Theme.palette.err) }
                    // The main action is the last one, on the right, as at the foot of a dialog.
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
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

/// `EntermField` for a secret: the same box, font, colors and focus ring, the text never shown.
private struct SecureEntermField: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        let palette = Theme.palette
        SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(Color(palette.text3)))
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

struct InboxPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var inbox = Inbox.shared
    @ObservedObject var power = PowerCenter.shared
    var body: some View {
        let pending = model.sessions.compactMap(\.pendingApproval)
        let asking = model.sessions.filter { $0.status == .needsApproval && $0.pendingApproval == nil }
        PageFrame(title: "Onay Kutusu") {
            T("Sizi Bekleyenler", bold: true, style: .section)
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
                        VStack(alignment: .leading, spacing: 4) {
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
                        VStack(alignment: .leading, spacing: 4) {
                            T("◷ \(queued.spec.tool.title) Sırada", bold: true)
                            Dim("\(queued.reason). Yer Açılınca Kendiliğinden Başlar, Token Harcamıyor.")
                        }
                        Spacer()
                        Btn("Yine De Başlat") { power.startAndShow(queued) }
                    }
                    .padding(12)
                }
            }
            if !inbox.finished.isEmpty {
                HStack {
                    T("Biten İşler", bold: true, style: .section)
                    Spacer()
                    Btn("Tümünü Okundu Say", kind: .plain) { inbox.finished.removeAll() }
                }
                Panel {
                    ForEach(inbox.finished) { item in
                        HStack(alignment: .top) {
                            T("\(item.symbol) \(item.title):")
                            Dim(item.detail).lineLimit(2)
                            Spacer()
                            Dim(item.at.formatted(date: .omitted, time: .shortened))
                        }
                        .settingsRow()
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
                    .settingsRow()
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
                // Right edge of the column, in line with the search field below: the window buttons keep the left.
                HStack {
                    Spacer()
                    Btn("Geri", kind: .plain, key: "Esc", icon: "chevron.left") { AppModel.shared.goBack() }
                }
                .padding(.leading, 72)
                .padding(.trailing, 12)
                .frame(height: 44)
                // The space under the field comes from the list's own inset below.
                EntermField(placeholder: "Ayarlarda Ara", text: $search)
                    .padding(.horizontal, 12)
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
                    // One inset on all four sides, so the last lit row sits as far from the bottom as from the edges.
                    .padding(12)
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
        SideItem(title: title, icon: icon, selected: selected, action: action)
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
                // The number belongs to "Elle": with "Otomatik" Enterm picks it and there is nothing to set.
                HStack(spacing: 8) {
                    Seg(options: [(true, "Otomatik"), (false, "Elle")], value: $power.settings.sessionsAutomatic)
                    if !power.settings.sessionsAutomatic {
                        NumberStepper(value: power.settings.maxSessions, minimum: 1) { power.settings.maxSessions = $0 }
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

/// One row of the settings list: lit when chosen, a faint fill under the pointer.
private struct SideItem: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            HStack(spacing: 8) {
                Symbol(icon, color: selected ? palette.need : (hovering ? palette.text1 : palette.text2))
                T(title, weight: selected ? .medium : .regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(selected ? Color(palette.fillSelected) : (hovering ? Color(palette.fill) : .clear))
            .cornerRadius(Theme.cornerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}
