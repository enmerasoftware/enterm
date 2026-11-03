import AppKit
import EntermCore
import SwiftUI

struct AccountsPage: View {
    @ObservedObject var store = AccountStore.shared
    @ObservedObject var model = AppModel.shared
    var body: some View {
        PageFrame(title: nil) {
            HStack {
                T("Hesaplar", bold: true)
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
            case (.codex, _):
                Dim("Bu Sürümde Okunmuyor")
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
        let account = AccountStore.shared.add(tool: tool, name: name.isEmpty ? tool.title : name)
        started = account
        var spec = SessionSpec(name: "giriş: \(account.name)", tool: .terminal, rows: 30, cols: 100, accountID: account.id)
        var env = AccountStore.shared.environment(for: account.id)
        env["ENTERM_STARTUP"] = tool == .codex ? "codex login" : "claude"
        spec.env = env
        model.create(spec)
    }
}

struct ApiKeyPage: View {
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
    @ObservedObject var model = AppModel.shared
    @ObservedObject var inbox = Inbox.shared
    @ObservedObject var power = PowerCenter.shared
    var body: some View {
        let pending = model.sessions.compactMap(\.pendingApproval)
        PageFrame(title: "Onay Kutusu") {
            T("Sizi Bekleyenler", bold: true)
            if pending.isEmpty && inbox.limits.isEmpty && power.queue.isEmpty {
                Dim("Bekleyen Bir Şey Yok")
            }
            ForEach(pending) { request in
                let info = model.sessions.first { $0.id == request.sessionID }
                Panel(border: Theme.palette.need) {
                    VStack(alignment: .leading, spacing: 8) {
                        T("◆ \(info.map { model.title(for: $0) } ?? "Oturum"): \(request.category.title)", color: Theme.palette.need, bold: true)
                        T(request.summary).lineLimit(4)
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
    @State var tab: SettingsTab
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var power = PowerCenter.shared
    var body: some View {
        PageFrame(title: nil) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { item in
                    Btn(item.title, kind: tab == item ? .selected : .plain) { tab = item }
                }
            }
            switch tab {
            case .appearance: appearance
            case .shortcuts: shortcuts
            case .security: security
            case .power: powerSection
            case .voice: voice
            case .sleep: sleep
            }
        }
    }

    private func line<Content: View>(_ title: String, _ note: String = "", @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                T(title)
                if !note.isEmpty { Dim(note) }
            }
            Spacer(minLength: 16)
            content()
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 16) {
            line("Program Açılınca", "Son görünüm: kapattığınız ekranla açılır") {
                Seg(options: [(true, "Son Görünüm"), (false, "Tek Terminal")], value: $store.settings.openWithLastView)
            }
            line("Yeni Terminal", "İkinci terminal nasıl açılsın") {
                Seg(options: [(false, "Yan Yana"), (true, "Sekme")], value: $store.settings.newTerminalAsTab)
            }
            line("Tema", "Yeniden açınca tam uygulanır") {
                Seg(options: [("dark", "Koyu"), ("light", "Açık"), ("system", "Sistem")], value: $store.settings.theme)
            }
            line("Terminal Yazı Boyutu") {
                HStack {
                    Btn("−", kind: .plain) { changeFont(-1) }
                    T("\(Int(store.settings.fontSize))")
                    Btn("+", kind: .plain) { changeFont(1) }
                }
            }
            line("Tuval Noktaları") {
                Seg(options: [(true, "Açık"), (false, "Kapalı")], value: $store.settings.canvasDots)
            }
        }
    }

    private func changeFont(_ delta: Double) {
        store.settings.fontSize = min(max(store.settings.fontSize + delta, 9), 28)
        AppModel.shared.hosts.values.forEach { $0.applyTheme() }
        AppModel.shared.onLayoutChange?()
    }

    private var shortcuts: some View {
        let rows: [(String, String)] = [("Yeni Terminal", "⌘T"), ("Yeni Oturum", "⌘N"), ("Kutuyu Kapat", "⌘W"), ("Tam Ekran, Tümünü Gör", "⌘⏎"),
                                        ("Ayrıntılar", "⌘I"), ("Durdur", "⌘."), ("Komut Paleti", "⌘K"), ("Onay Kutusu", "⌘⇧O"), ("Pano", "⌘⇧B"),
                                        ("Yönetici Görünümü", "⌘⇧Y"), ("Tarayıcı", "⌘⇧D"), ("Sonraki, Önceki Oturum", "⌘] ⌘["), ("Oturum 1 İla 9", "⌘1 - ⌘9"),
                                        ("Yakınlaştır, Uzaklaştır", "⌘= ⌘-"), ("Konuşarak Yaz", "⌃⌘ Basılı"), ("İzin Ver, Reddet", "y n")]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.0) { row in
                HStack { T(row.0); Spacer(); Key(row.1) }
            }
            Dim("Terminal odaktayken tuşlar terminale gider, Esc çalışmayı keser. Kısayolları yeniden atama henüz yok.")
        }
    }

    private var security: some View {
        VStack(alignment: .leading, spacing: 16) {
            line("Terminal Dökümünü Sakla", "Yeniden açılışta geri gelir, diske şifresiz yazılır") {
                Seg(options: [(true, "Açık"), (false, "Kapalı")], value: $store.settings.keepTranscript)
            }
            line("Yeni Oturumda Varsayılan Şablon") {
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
            line("Ajan Mesajı Onay Sayılmaz", "Kapatılamaz") { T("Zorunlu") }
            line("Bağlı Cihazlar", "Telefon bağlantısı bu sürümde yok") { Dim("Henüz Yok") }
        }
    }

    private var powerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            line("Düşük Güçlü Bilgisayar", "Hareket kapalı, odak dışındaki kutular seyrek güncellenir, tarayıcı açılmaz.") {
                Seg(options: [(false, "Kapalı"), (true, "Açık")], value: $power.settings.lowPower)
            }
            line("Bilgisayarın Gücünün En Çok Şu Kadarını Kullan") {
                Seg(options: [(25, "%25"), (50, "%50"), (75, "%75"), (100, "Sınırsız")], value: $power.settings.cpuLimit)
            }
            Dim("Bu bir üst hedeftir, kesin ölçüm değildir. Sınıra yaklaşınca yeni iş sıraya girer, arka plandaki oturumun önceliği düşer. İşlemciyle birlikte bellek baskısı da sayılır. Düz terminallere dokunulmaz.")
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
            Line()
            T("Şu Anki Kullanım", bold: true)
            HStack { T("Enterm"); Spacer(); Dim(String(format: "%%%.1f · %.0f MB", power.enterm.cpu, power.enterm.memoryMB)) }
            HStack { T("Claude Code, Codex Ve Antigravity"); Spacer(); Dim(String(format: "%%%.1f · %.0f MB", power.agents.cpu, power.agents.memoryMB)) }
            Dim("Ajanların yükü Enterm'in elinde değildir. Aynı anda çalışan oturum sayısıyla azalır.")
            HStack { T("Bellek Baskısı"); Spacer(); Dim(power.memoryPressure ? "Var" : "Yok") }
            Btn("Yeniden Ölç", kind: .plain) { power.measureUsage() }
        }
        .onAppear { power.measureUsage() }
    }

    private var voice: some View {
        VStack(alignment: .leading, spacing: 16) {
            line("Konuşarak Yazma", "Basılı tutun, konuşun, bırakın. Kullanılmadıkça yük bindirmez.") {
                HStack {
                    Key("⌃⌘")
                    Seg(options: [(true, "Açık"), (false, "Kapalı")], value: $store.settings.voiceEnabled)
                }
            }
            Panel {
                Row { VStack(alignment: .leading) { T("Sistem Diktesi"); Dim("İşletim sisteminin hizmeti. İndirme yok, bellek yükü Enterm'de yok. Mümkünse cihazda işlenir.") }; Spacer(); T("Seçili", bold: true) }
                Line()
                Row { VStack(alignment: .leading) { T("Yerel Whisper Modeli"); Dim("Küçük, Orta, Büyük. Ses bilgisayardan çıkmaz.") }; Spacer(); Dim("Henüz Yok") }
            }
            line("Dil") {
                Seg(options: [("tr-TR", "Türkçe"), ("en-US", "English")], value: $store.settings.voiceLanguage)
            }
            Dim("Metni siz gönderirsiniz: Enter'a siz basarsınız. Tuş bırakılınca mikrofon hemen kapanır.")
        }
    }

    private var sleep: some View {
        VStack(alignment: .leading, spacing: 16) {
            line("Ajan Çalışırken Bilgisayar Uyumasın", "Ajan bitince engel kalkar. Düz terminal için çalışmaz.") {
                Seg(options: [(false, "Kapalı"), (true, "Açık")], value: $store.settings.keepAwakeWhileAgents)
            }
            HStack { T("Şu An"); Spacer(); Dim(ExtensionsHub.shared.isHoldingAwake ? "Uyku Engelleniyor" : "Engel Yok") }
            Dim("Kapak kapanırsa macOS yine uyuyabilir.")
        }
    }
}
