import AppKit
import EntermCore
import SwiftUI
import WebKit

// The settings that came with the new design. Every line here does what it says.

/// A heading above a group of rows, with room for a sentence under it.
struct SectionHead: View {
    let title: String
    var note = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            T(title, bold: true, style: .section)
            if !note.isEmpty { Dim(note).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct SettingsLine<Content: View>: View {
    let title: String
    var note = ""
    @ViewBuilder var content: () -> Content
    var body: some View {
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
}

// MARK: Programs

struct ProgramsSettings: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var catalog = ToolCatalog.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Terminal", note: "Program gerekmez") { defaultButton("terminal") }
                ForEach(ToolKind.programs, id: \.self) { tool in
                    let hidden = store.settings.hiddenTools.contains(tool.rawValue)
                    SettingsLine(title: tool.title, note: presence(tool)) {
                        // The default control comes last, so it stands in one column in every row, Terminal's included.
                        HStack(spacing: 8) {
                            Seg(options: [(false, "Göster"), (true, "Gizle")], value: Binding(
                                get: { hidden },
                                set: { hide in
                                    store.settings.hiddenTools.removeAll { $0 == tool.rawValue }
                                    if hide { store.settings.hiddenTools.append(tool.rawValue) }
                                }))
                            defaultButton(programID(tool))
                        }
                    }
                }
            }
            Dim("Enterm bu programların ayar dosyalarına yazmaz. Claude Code ve Codex durumunu kendi söyler, diğerlerinin durumu yazıp yazmadığından anlaşılır.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { catalog.refresh() }
    }

    private func programID(_ tool: ToolKind) -> String {
        switch tool {
        case .antigravity: return "agy"
        case .terminal: return "terminal"
        default: return tool.rawValue
        }
    }

    private func presence(_ tool: ToolKind) -> String {
        if case .installed? = catalog.presence[tool] { return "Kurulu" }
        let note = catalog.note(tool)
        return note.isEmpty ? "Bakılıyor" : note
    }

    @ViewBuilder
    private func defaultButton(_ id: String) -> some View {
        if store.settings.defaultProgram == id {
            // Takes the button's width, so nothing beside it moves when the default changes.
            Btn("Varsayılan Yap", kind: .plain) {}
                .hidden()
                .overlay { T("Varsayılan", color: Theme.palette.need, style: .secondary, weight: .semibold) }
        } else {
            Btn("Varsayılan Yap", kind: .plain) { store.settings.defaultProgram = id }
        }
    }
}

struct CustomProgramsSettings: View {
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Dim("Listede olmayan bir programı ya da kendi betiğinizi ekleyin. Yeni Oturum menüsünde görünür.")
            ForEach($store.settings.customPrograms) { $program in
                Panel {
                    SettingsLine(title: "Ad") { EntermField(placeholder: "Benim Aracım", text: $program.name).frame(width: 320) }
                    SettingsLine(title: "Komut", note: "Terminale yazar gibi") { EntermField(placeholder: "aracim", text: $program.command).frame(width: 320) }
                    SettingsLine(title: "Argümanlar") { EntermField(placeholder: "--model hizli", text: $program.arguments).frame(width: 320) }
                    SettingsLine(title: "Ortam Değişkenleri", note: "Satır başına ANAHTAR=değer") {
                        EnvironmentEditor(environment: $program.environment).frame(width: 320)
                    }
                    HStack {
                        Spacer()
                        Btn("Kaldır", kind: .danger) { store.settings.customPrograms.removeAll { $0.id == program.id } }
                    }
                    .settingsRow()
                }
            }
            Btn("Program Ekle", kind: .primary, icon: "plus") { store.settings.customPrograms.append(CustomProgram()) }
        }
    }
}

private struct EnvironmentEditor: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @Binding var environment: [String: String]
    @State private var text = ""
    var body: some View {
        TextEditor(text: $text)
            .font(Theme.swiftFont(size: 12))
            .scrollContentBackground(.hidden)
            // The text view adds 5 on each side, so the text sits 12 in, like the text of an EntermField.
            .padding(.horizontal, 7)
            .padding(.vertical, 12)
            .frame(height: 64)
            .background(Color(Theme.palette.terminal))
            .cornerRadius(Theme.cornerControl)
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerControl).stroke(Color(Theme.palette.hair2)))
            .onAppear { text = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") }
            .onChange(of: text) { value in
                var result: [String: String] = [:]
                for line in value.split(separator: "\n") {
                    let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                    if parts.count == 2, !parts[0].isEmpty { result[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1] }
                }
                environment = result
            }
    }
}

// MARK: Model gateway

struct GatewaySettings: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var models: [String] = []
    @State private var status = ""
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Dim("Claude Code oturumlarını kendi OpenAI ya da Anthropic uyumlu sunucunuza yönlendirin. Anahtarın kendisi saklanmaz, yalnız kabuğunuzdaki değişkenin adı saklanır.")
                .fixedSize(horizontal: false, vertical: true)
            Panel {
                SettingsLine(title: "Ağ Geçidini Kullan", note: "Kapalıyken programlar kendi hesabıyla açılır") {
                    Seg(options: [(false, "Kapalı"), (true, "Açık")], value: $store.settings.gatewayOn)
                }
                SettingsLine(title: "Sunucu Adresi") { EntermField(placeholder: "https://gateway.ornek.com", text: $store.settings.gatewayURL).frame(width: 320) }
                SettingsLine(title: "Anahtar Değişkeni", note: "Örnek: GATEWAY_API_KEY") { EntermField(placeholder: "GATEWAY_API_KEY", text: $store.settings.gatewayKeyVariable).frame(width: 320) }
                SettingsLine(title: "Model") {
                    if models.isEmpty {
                        EntermField(placeholder: "Programın varsayılanı", text: $store.settings.gatewayModel).frame(width: 320)
                    } else {
                        ChoiceMenu(options: [("", "Programın Varsayılanı")] + models.map { ($0, $0) }, value: $store.settings.gatewayModel)
                    }
                }
                HStack(spacing: 12) {
                    if !status.isEmpty { Dim(status) }
                    Spacer()
                    Btn(busy ? "Bakılıyor" : "Modelleri Bul") { discover() }
                        .disabled(busy || store.settings.gatewayURL.isEmpty)
                }
                .settingsRow()
            }
        }
    }

    /// Asked through the user's own shell, which is where the key lives. Only runs on this click.
    private func discover() {
        busy = true
        status = ""
        let settings = store.settings
        DispatchQueue.global(qos: .userInitiated).async {
            let list = Gateway.discover(url: settings.gatewayURL, keyVariable: settings.gatewayKeyVariable)
            DispatchQueue.main.async {
                busy = false
                models = list ?? []
                status = list == nil ? "Sunucudan Yanıt Alınamadı" : "\(list?.count ?? 0) Model Bulundu"
            }
        }
    }
}

enum Gateway {
    static func discover(url: String, keyVariable: String) -> [String]? {
        let base = url.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard base.hasPrefix("http") else { return nil }
        let header = keyVariable.isEmpty ? "" : " -H \"Authorization: Bearer $\(keyVariable)\""
        let line = "curl -fsS --max-time 8\(header) \(NotFoundActions.shellQuote(base + "/v1/models"))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        process.arguments = ["-ilc", line]
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let start = data.firstIndex(of: UInt8(ascii: "{")),
              let object = (try? JSONSerialization.jsonObject(with: data[start...])) as? [String: Any],
              let items = object["data"] as? [[String: Any]] else { return nil }
        return items.compactMap { $0["id"] as? String }.sorted()
    }

    /// The environment of a Claude Code start when the gateway is on, and the words the shell needs in front of the command.
    static func claudeLaunch() -> (env: [String: String], prefix: String)? {
        let settings = SettingsStore.shared.settings
        guard settings.gatewayOn, !settings.gatewayURL.isEmpty else { return nil }
        var env = ["ANTHROPIC_BASE_URL": settings.gatewayURL]
        if !settings.gatewayModel.isEmpty { env["ANTHROPIC_MODEL"] = settings.gatewayModel }
        let prefix = settings.gatewayKeyVariable.isEmpty ? "" : "ANTHROPIC_AUTH_TOKEN=\"$\(settings.gatewayKeyVariable)\" "
        return (env, prefix)
    }
}

// MARK: Usage

struct UsageSettings: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var accounts = AccountStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Yüzde Nasıl Gösterilsin") {
                    Seg(options: [(false, "Kullanılan"), (true, "Kalan")], value: $store.settings.usageRemaining)
                }
            }
            SectionHead(title: "Hesaplar", note: "Limit, programın ilk yanıtından sonra görünür.")
            Panel {
                ForEach(Array(accounts.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Line() }
                    AccountRow(account: account, sessions: AppModel.shared.sessions.filter { ($0.accountID ?? "system-\($0.tool.rawValue)") == account.id }.count)
                }
            }
            Btn("Maliyet Geçmişi") { AppModel.shared.page = .cost }
        }
        .onAppear { accounts.refreshCodex() }
    }
}

// MARK: Commit messages

struct CommitSettings: View {
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Yazan Program", note: "Yalnız düğmeye basınca çalışır, hazırlanan değişikliği okur") {
                    Seg(options: [("claude", "Claude Code"), ("codex", "Codex")], value: $store.settings.commitProgram)
                }
                SettingsLine(title: "Ek Yönerge") {
                    EntermField(placeholder: "Örnek: Türkçe ve tek satır yaz", text: $store.settings.commitPrompt).frame(width: 320)
                }
            }
            Dim("Değişiklikler ekranında “İleti Yaz” düğmesi görünür. Kendi hesabınızın limitini kullanır.")
        }
    }
}

// MARK: Terminal

struct TerminalSettings: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = SettingsStore.shared

    private static let fonts: [String] = {
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 13) else { return false }
            return font.isFixedPitch && !family.hasPrefix(".")
        }
        return families.sorted()
    }()

    var body: some View {
        let theme = TerminalThemes.preview(store.settings.terminalTheme)
        VStack(alignment: .leading, spacing: 16) {
            preview(theme)
            Panel {
                SettingsLine(title: "Renk Teması") {
                    ChoiceMenu(options: TerminalTheme.all.filter { $0.id != "entermLight" }.map { ($0.id, $0.title) }, value: bound(\.terminalTheme))
                }
                SettingsLine(title: "Yazı Tipi") {
                    ChoiceMenu(options: [("", "JetBrains Mono")] + Self.fonts.filter { $0 != "JetBrains Mono" }.map { ($0, $0) }, value: bound(\.fontName))
                }
                SettingsLine(title: "Yazı Boyutu") {
                    NumberStepper(value: Int(store.settings.fontSize), minimum: 9, maximum: 28) { changeFont(Double($0) - store.settings.fontSize) }
                }
                SettingsLine(title: "İmleç") {
                    HStack(spacing: 8) {
                        Seg(options: [("block", "Blok"), ("bar", "Çubuk"), ("underline", "Alt Çizgi")], value: bound(\.cursorStyle))
                        Seg(options: [(true, "Yanıp Söner"), (false, "Sabit")], value: bound(\.cursorBlink))
                    }
                }
                SettingsLine(title: "Seçince Kopyala", note: "Fareyle seçilen yazı panoya gider") {
                    Seg(options: [(false, "Kapalı"), (true, "Açık")], value: bound(\.copyOnSelect))
                }
                SettingsLine(title: "Geçmiş Satır Sayısı", note: "Yeni açılan terminallerde geçerli") {
                    Seg(options: [(5000, "5.000"), (10000, "10.000"), (50000, "50.000")], value: $store.settings.scrollbackLines)
                }
            }
        }
    }

    private func bound<Value>(_ path: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: path] }, set: { value in
            store.settings[keyPath: path] = value
            AppModel.shared.hosts.values.forEach { $0.applyTheme() }
            AppModel.shared.onLayoutChange?()
        })
    }

    private func changeFont(_ delta: Double) {
        store.settings.fontSize = min(max(store.settings.fontSize + delta, 9), 28)
        AppModel.shared.hosts.values.forEach { $0.applyTheme() }
        AppModel.shared.onLayoutChange?()
    }

    private func preview(_ theme: TerminalTheme) -> some View {
        let font = Font(Theme.font(size: 13))
        func color(_ index: Int) -> Color { Color(NSColor.hex(theme.ansi[index])) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("~/proje ").foregroundColor(color(4))
                Text("git:(main) ").foregroundColor(color(2))
                Text("npm test").foregroundColor(Color(theme.foregroundColor))
            }
            HStack(spacing: 0) {
                Text("✓ 12 test geçti  ").foregroundColor(color(2))
                Text("✕ 1 test kaldı  ").foregroundColor(color(1))
                Text("⚠ 2 uyarı").foregroundColor(color(3))
            }
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { index in
                    Rectangle().fill(color(index)).frame(width: 18, height: 10)
                }
            }
            .padding(.top, 4)
        }
        .font(font)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(theme.backgroundColor))
        .cornerRadius(Theme.cornerCard)
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).stroke(Color(Theme.palette.hair2)))
    }
}

enum TerminalThemes {
    static func preview(_ id: String) -> TerminalTheme {
        if id == "enterm" { return Theme.isLight ? .entermLight : .enterm }
        return TerminalTheme.all.first { $0.id == id } ?? .enterm
    }
}

// MARK: Shell and sessions

struct ShellSettings: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Varsayılan Kabuk", note: "Boş bırakılırsa sistemin kabuğu açılır") {
                    EntermField(placeholder: "/bin/zsh", text: $store.settings.defaultShell).frame(width: 320)
                }
            }
            if !store.settings.defaultShell.isEmpty, !FileManager.default.isExecutableFile(atPath: store.settings.defaultShell) {
                T("Bu dosya bulunamadı, sistemin kabuğu açılır.", color: Theme.palette.limit, style: .secondary)
            }
            Dim(".zshrc ve .bashrc dosyalarınız değişmez. Enterm kendi eklerini açılışta verir.")
        }
    }
}

struct SessionSettings: View {
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Terminal Dökümünü Sakla", note: "Yeniden açılışta geri gelir, diske şifresiz yazılır") {
                    Seg(options: [(true, "Açık"), (false, "Kapalı")], value: $store.settings.keepTranscript)
                }
                SettingsLine(title: "Program Açılınca", note: "Son görünüm: kapattığınız ekranla açılır") {
                    Seg(options: [(true, "Son Görünüm"), (false, "Tek Terminal")], value: $store.settings.openWithLastView)
                }
            }
            Dim("Pencereyi kapatsanız da oturumlar Enterm servisinde çalışmaya devam eder. Bilgisayar yeniden başlarsa oturumları tek tıkla geri getirebilirsiniz.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Browser

struct BrowserSettings: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var checking = false
    @State private var result: String?
    @State private var checked = false
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Girişleri Hatırla", note: "Enterm'in tarayıcısında girdiğiniz hesaplar kapanınca da kalır. Ajanlar da bu hesapları kullanabilir.") {
                    Seg(options: [(false, "Kapalı"), (true, "Açık")], value: keepLogins)
                }
                if store.settings.browserKeepLogins {
                    SettingsLine(title: "Kayıtlı Girişler", note: cleared ? "Silindi." : "Bu tarayıcıdaki tüm hesaplardan çıkılır.") {
                        Btn("Sil", kind: .outline) { clearLogins() }
                    }
                }
            }
            SectionHead(title: "Safari", note: "Ajanlar sayfaları Safari'nizde, kendi penceresinde açar. Girişleriniz hazır olur. Her site için bir kez izin sorulur, açık sekmelerinize dokunulmaz.")
            Panel {
                SettingsLine(title: "Ajanlar Safari'yi Kullansın", note: "Kapalıyken macOS hiçbir şey sormaz.") {
                    Seg(options: [(false, "Kapalı"), (true, "Açık")], value: $store.settings.safariForAgents)
                }
                if store.settings.safariForAgents {
                    SettingsLine(title: "Bağlantı", note: note) {
                        Btn(checking ? "Deneniyor" : "Dene", kind: .outline) { check() }
                    }
                }
            }
            if store.settings.safariForAgents {
                Dim("Önce Safari'nin Geliştir menüsünde Apple Olaylarından JavaScript'e izin verin. Bu menü yoksa Safari Ayarları → Gelişmiş'ten açılır. İlk denemede macOS izin sorar.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var note: String {
        if let result { return result }
        return checked ? "Safari'ye bağlanıldı." : "Bir pencere açıp kapatır."
    }

    private var keepLogins: Binding<Bool> {
        Binding(get: { store.settings.browserKeepLogins }, set: {
            store.settings.browserKeepLogins = $0
            // The next page opens with the chosen store.
            BrowserCenter.shared.close()
        })
    }

    private func clearLogins() {
        BrowserCenter.shared.close()
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { cleared = true }
    }

    private func check() {
        checking = true
        SafariBridge.shared.check { problem in
            checking = false
            result = problem
            checked = problem == nil
        }
    }
}

// MARK: Behaviour

struct BehaviorSettings: View {
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Yeni Terminal", note: "İkinci terminal nasıl açılsın") {
                    Seg(options: [(false, "Yan Yana"), (true, "Sekme")], value: $store.settings.newTerminalAsTab)
                }
                SettingsLine(title: "Izgaraya Yasla", note: "Kutular taşınırken 24 noktalık ızgaraya oturur") {
                    Seg(options: [(false, "Kapalı"), (true, "Açık")], value: $store.settings.snapToGrid)
                }
                SettingsLine(title: "Üzerine Gelince Odaklan", note: "Fare hangi terminaldeyse tuşlar oraya gider") {
                    Seg(options: [(false, "Kapalı"), (true, "Açık")], value: $store.settings.focusFollowsPointer)
                }
                SettingsLine(title: "Durak Hattı", note: "Tuvalde solda oturum listesi") {
                    Seg(options: [(true, "Açık"), (false, "Kapalı")], value: layout(\.showRail))
                }
                SettingsLine(title: "Küçük Harita", note: "Kutular elle dizildiğinde sağ altta") {
                    Seg(options: [(false, "Kapalı"), (true, "Açık")], value: layout(\.miniMap))
                }
                SettingsLine(title: "Çıkarken Sor", note: "Oturumlar arkada sürer, yine de bir kez sorulur") {
                    Seg(options: [(true, "Açık"), (false, "Kapalı")], value: $store.settings.confirmQuit)
                }
            }
            SectionHead(title: "Uyku")
            Panel {
                SettingsLine(title: "Program Çalışırken Bilgisayar Uyumasın", note: "İş bitince engel kalkar. Düz terminal için çalışmaz.") {
                    Seg(options: [(false, "Kapalı"), (true, "Açık")], value: $store.settings.keepAwakeWhileAgents)
                }
                HStack { T("Şu An"); Spacer(); Dim(ExtensionsHub.shared.isHoldingAwake ? "Uyku Engelleniyor" : "Engel Yok") }.settingsRow()
            }
            Dim("Kapak kapanırsa macOS yine uyuyabilir.")
        }
    }

    private func layout(_ path: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: path] }, set: { value in
            store.settings[keyPath: path] = value
            AppModel.shared.onLayoutChange?()
        })
    }
}

// MARK: Appearance

struct AppearanceSettings: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Tema") {
                    Seg(options: [("dark", "Koyu"), ("light", "Açık"), ("system", "Sistem")], value: refreshed(\.theme))
                }
                SettingsLine(title: "Vurgu Rengi", note: "Ana düğme, komut satırı ve sizi bekleyen her şey") {
                    HStack(spacing: 8) {
                        ForEach(AccentChoice.all) { choice in
                            AccentDot(choice: choice, on: store.settings.accent == choice.id) { apply(\.accent, choice.id) }
                        }
                    }
                }
                SettingsLine(title: "Neon Işık", note: "Köşelerdeki ışıklar sabittir, işlemci harcamaz") {
                    Seg(options: [("off", "Kapalı"), ("soft", "Hafif"), ("strong", "Belirgin")], value: refreshed(\.neon))
                }
                SettingsLine(title: "Hareket", note: "Yalnız bir şey olduğunda çalışır, boşta sıfır") {
                    Seg(options: [(true, "Olay Olunca"), (false, "Kapalı")], value: refreshed(\.motion))
                }
                SettingsLine(title: "Tuval Izgarası") {
                    Seg(options: [(true, "Açık"), (false, "Kapalı")], value: refreshed(\.canvasDots))
                }
            }
            SectionHead(title: "Tuval Arka Planı", note: "Kutuların arkasında durur, yalnız pencere boyutu değişince yeniden çizilir.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(Wallpaper.all) { wallpaper in
                    wallpaperButton(wallpaper)
                }
                WallpaperTile(on: store.settings.wallpaper.hasPrefix("file:"), action: choosePicture) {
                    ZStack {
                        Color(Theme.palette.fill)
                        VStack(spacing: 4) {
                            Symbol("photo", color: Theme.palette.text2)
                            Dim("Görsel Seç")
                        }
                    }
                }
            }
        }
    }

    private func wallpaperButton(_ wallpaper: Wallpaper) -> some View {
        WallpaperTile(on: store.settings.wallpaper == wallpaper.id, action: { apply(\.wallpaper, wallpaper.id) }) {
            ZStack(alignment: .bottomLeading) {
                if wallpaper.colors.isEmpty {
                    Color(Theme.palette.surface0)
                } else {
                    LinearGradient(colors: wallpaper.colors.map { Color(NSColor.hex($0)) }, startPoint: .bottomLeading, endPoint: .topTrailing)
                }
                T(wallpaper.title, color: wallpaper.colors.isEmpty ? Theme.palette.text1 : .white, style: .secondary, weight: .medium).padding(8)
            }
        }
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Seç"
        if panel.runModal() == .OK, let url = panel.url { apply(\.wallpaper, "file:" + url.path) }
    }

    private func refreshed<Value>(_ path: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: path] }, set: { value in apply(path, value) })
    }

    private func apply<Value>(_ path: WritableKeyPath<AppSettings, Value>, _ value: Value) {
        store.settings[keyPath: path] = value
        (NSApp.delegate as? AppDelegate)?.applyAppearance()
    }
}

/// A wallpaper choice: lit edge when chosen, the plain button's hover edge under the pointer.
private struct WallpaperTile<Content: View>: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let on: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, minHeight: 64)
                .cornerRadius(Theme.cornerCard)
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerCard).stroke(Color(on ? palette.need : (hovering ? palette.focus.withAlphaComponent(0.35) : palette.hair2)), lineWidth: on ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
    }
}

/// An accent color: a full ring when chosen, a faint one under the pointer.
private struct AccentDot: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let choice: AccentChoice
    let on: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let palette = Theme.palette
        Button(action: action) {
            Circle()
                .fill(Color(NSColor.hex(Theme.isLight ? choice.light : choice.dark)))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color(on ? palette.text1 : palette.text3), lineWidth: on ? 2 : (hovering ? 1 : 0)).padding(-3))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .onHover { hovering = $0 }
        .help(choice.title)
    }
}

// MARK: Notch

struct NotchSettings: View {
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Çentikte Göster", note: "Program çalışırken MacBook çentiğinin iki yanında durum işaretleri") {
                    Seg(options: [(true, "Açık"), (false, "Kapalı")], value: Binding(
                        get: { store.settings.notch },
                        set: { value in
                            store.settings.notch = value
                            NotchCenter.shared.update()
                        }))
                }
            }
            Dim("Üzerine gelince oturum listesi açılır, tıklayınca o oturuma gidersiniz. Çentiksiz ekranlarda menü çubuğunun ortasında durur. Program çalışmıyorsa hiç görünmez.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Notifications

struct NotificationSettings: View {
    @ObservedObject var store = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                SettingsLine(title: "Sistem Bildirimleri", note: "İş bitince, onay istenince, limit dolunca") {
                    Seg(options: [(true, "Açık"), (false, "Kapalı")], value: $store.settings.systemNotifications)
                }
                SettingsLine(title: "Ses", note: "Onay istenince ve iş bitince kısa bir ses") {
                    Seg(options: [(true, "Açık"), (false, "Kapalı")], value: $store.settings.notifySound)
                }
                if store.settings.notifySound {
                    SettingsLine(title: "Ses Düzeyi") {
                        HStack(spacing: 8) {
                            Slider(value: $store.settings.notifyVolume, in: 0.1...1).frame(width: 160)
                            Btn("Dene", kind: .plain) { NotifySound.play(.needsYou) }
                        }
                    }
                }
            }
            SectionHead(title: "Betikten Bildirim", note: "Kendi betiğiniz telefona bildirim göndersin. Bu bilgisayarda anahtar gerekmez.")
            CommandBox(text: "enterm notify \"Derleme bitti\"")
        }
    }
}

enum NotifySound {
    enum Kind { case needsYou, finished }
    static func play(_ kind: Kind) {
        let settings = SettingsStore.shared.settings
        guard settings.notifySound, let sound = NSSound(named: kind == .needsYou ? "Tink" : "Glass")?.copy() as? NSSound else { return }
        sound.volume = Float(settings.notifyVolume)
        sound.play()
    }
}

// MARK: About

struct AboutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                HStack { T("Sürüm"); Spacer(); Mono(EntermVersion.current) }.settingsRow()
                SettingsLine(title: "Kurulum Turu", note: "Karşılama ekranını yeniden gösterir") {
                    Btn("Aç") { AppModel.shared.page = .welcome }
                }
                SettingsLine(title: "Gizlilik", note: "Enterm kullanım verisi göndermez. Terminal içeriği bilgisayardan çıkmaz.") {
                    EmptyView()
                }
                SettingsLine(title: "Kaldır", note: "Enterm'in bıraktığı her şeyi görüp silersiniz") {
                    Btn("Enterm'i Kaldır", kind: .danger) { AppModel.shared.page = .uninstall }
                }
            }
        }
    }
}
