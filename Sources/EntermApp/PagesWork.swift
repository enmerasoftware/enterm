import AppKit
import EntermCore
import SwiftUI
import WebKit

// MARK: Session list

struct SessionListPage: View {
    @ObservedObject var model = AppModel.shared
    var body: some View {
        PageFrame(title: "\(model.sessions.count) Oturum", wide: true) {
            Panel {
                ForEach(model.sessions) { info in
                    Row(action: {
                        model.page = nil
                        model.setFocus(info.number)
                        if model.mode == .canvas { model.maximized = info.number; model.onLayoutChange?() }
                    }) {
                        VStack(alignment: .leading) {
                            T(model.title(for: info), bold: true)
                            Dim(info.lastActivity ?? model.displayPath(info.cwd)).lineLimit(1)
                        }
                        Spacer()
                        Dim(info.tool.title)
                        if info.tool != .terminal { StatusBadge(status: info.status) }
                    }
                    Line()
                }
            }
        }
    }
}

// MARK: Past conversations

struct PastConversation: Identifiable {
    let id: String
    let tool: ToolKind
    let cwd: String
    let title: String
    let path: String
    let date: Date
}

enum ConversationIndex {
    /// Lists the official program's own files by name and date. It reads only the first user line of each.
    static func list(cwd: String) -> [PastConversation] {
        let fm = FileManager.default
        let dirName = cwd.replacingOccurrences(of: "[^A-Za-z0-9]", with: "-", options: .regularExpression)
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects/\(dirName)")
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var result: [PastConversation] = []
        for file in files where file.pathExtension == "jsonl" {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            result.append(PastConversation(id: file.deletingPathExtension().lastPathComponent, tool: .claude, cwd: cwd,
                                           title: firstPrompt(file) ?? file.deletingPathExtension().lastPathComponent, path: file.path, date: date))
        }
        return Array(result.sorted { $0.date > $1.date }.prefix(50))
    }

    private static func firstPrompt(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 64 * 1024)
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "user", let message = object["message"] as? [String: Any] else { continue }
            if let text = message["content"] as? String { return String(text.prefix(100)) }
        }
        return nil
    }
}

struct HistoryPage: View {
    @ObservedObject var model = AppModel.shared
    @State private var items: [PastConversation] = []
    var body: some View {
        let cwd = model.focusedInfo?.cwd ?? NSHomeDirectory()
        PageFrame(title: "Geçmiş Konuşmalar: \(model.displayPath(cwd))") {
            if items.isEmpty { Dim("Bu klasörde Claude Code konuşması bulunamadı. Codex ve Antigravity listesi bu sürümde yok.") }
            Panel {
                ForEach(items) { item in
                    Row(action: {
                        model.page = nil
                        ToolLauncher.start(item.tool, cwd: item.cwd, extraArguments: "--resume \(NotFoundActions.shellQuote(item.path))")
                    }) {
                        VStack(alignment: .leading) {
                            T(item.title).lineLimit(1)
                            Dim("\(item.tool.title) · \(item.date.formatted(date: .abbreviated, time: .shortened))")
                        }
                        Spacer()
                        Key("Sürdür")
                    }
                    Line()
                }
            }
            Dim("Sürdürmek konuşmayı resmi programla açar, ilk mesajda baştan okunur ve limitten yer.")
        }
        .onAppear { items = ConversationIndex.list(cwd: cwd) }
    }
}

// MARK: New view: files, editor, note

struct NewViewPage: View {
    @ObservedObject var model = AppModel.shared
    var body: some View {
        PageFrame(title: "Yeni Görünüm") {
            Dim("Yalnız Açılınca Yüklenir")
            Panel {
                MenuRow(title: "Dosya Gezgini", note: "Bu Klasörün Dosyaları") { model.page = .files }
                MenuRow(title: "Düzenleyici", note: "Dosyayı Burada Açıp Düzeltin") { model.page = .files }
                MenuRow(title: "Not", note: "Bu Klasöre Bağlı Kısa Not") { model.page = .note }
                MenuRow(title: "Zamanlayıcı", note: "Bir Komut Ya Da İş, Belli Saatte") { model.page = .scheduler }
                MenuRow(title: "Beyaz Tahta", note: "Henüz Yok") { model.page = .notYet("Beyaz Tahta") }
                MenuRow(title: "Çalıştır", note: "Henüz Yok") { model.page = .notYet("Çalıştır") }
                MenuRow(title: "iOS Simülatörü", note: "Henüz Yok") { model.page = .notYet("iOS Simülatörü") }
            }
        }
    }
}

struct FilesPage: View {
    @ObservedObject var model = AppModel.shared
    @State private var path = ""
    @State private var items: [URL] = []
    var body: some View {
        PageFrame(title: model.displayPath(path)) {
            Btn("‹ Üst Klasör", kind: .plain) { open(URL(fileURLWithPath: path).deletingLastPathComponent().path) }
            Panel {
                ForEach(items, id: \.self) { url in
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    MenuRow(title: url.lastPathComponent + (isDirectory ? "/" : "")) {
                        if isDirectory { open(url.path) } else { model.page = .editor(url.path) }
                    }
                }
            }
        }
        .onAppear { open(model.focusedInfo?.cwd ?? NSHomeDirectory()) }
    }
    private func open(_ directory: String) {
        path = directory
        let found = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        items = found.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
    }
}

struct EditorPage: View {
    let path: String
    @ObservedObject var model = AppModel.shared
    @State private var text = ""
    @State private var state = ""
    var body: some View {
        PageFrame(title: model.displayPath(path), wide: true) {
            HStack {
                Btn("Kaydet", kind: .primary, key: "⌘S") { save() }.keyboardShortcut("s", modifiers: .command)
                Dim(state)
            }
            TextEditor(text: $text)
                .font(Theme.swiftFont())
                .frame(minHeight: 480)
                .scrollContentBackground(.hidden)
                .background(Color(Theme.palette.panel))
        }
        .onAppear {
            if let data = FileManager.default.contents(atPath: path), data.count < 2_000_000, let value = String(data: data, encoding: .utf8) {
                text = value
            } else {
                state = "Bu Dosya Burada Açılamıyor: Çok Büyük Ya Da Metin Değil."
            }
        }
    }
    private func save() {
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            state = "Kaydedildi."
        } catch {
            state = "Kaydedilemedi."
        }
    }
}

struct NotePage: View {
    @ObservedObject var model = AppModel.shared
    @State private var text = ""
    @State private var file = ""
    var body: some View {
        PageFrame(title: "Not", wide: true) {
            Dim("Dosya: \(model.displayPath(file)). Ajana vermek için dosya yolunu yazın.")
            TextEditor(text: $text)
                .font(Theme.swiftFont())
                .frame(minHeight: 420)
                .scrollContentBackground(.hidden)
                .background(Color(Theme.palette.panel))
                .onChange(of: text) { value in
                    try? FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    try? value.write(toFile: file, atomically: true, encoding: .utf8)
                }
        }
        .onAppear {
            file = (model.focusedInfo?.cwd ?? NSHomeDirectory()) + "/.enterm/not.md"
            text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        }
    }
}

// MARK: Remote

struct RemotePage: View {
    @ObservedObject var model = AppModel.shared
    @State private var hosts: [String] = []
    @State private var custom = ""
    var body: some View {
        PageFrame(title: "Uzak Sunucu") {
            Dim("Terminal bilgisayarınızda çalışır, ssh ile bağlanır. Anahtarlar ~/.ssh içinde kalır, Enterm okumaz. Uzak makinede kurulum kartı ve ajan durumu görünmez.")
            if !hosts.isEmpty {
                Panel {
                    ForEach(hosts, id: \.self) { host in
                        MenuRow(title: host, note: "~/.ssh/config") { connect(host) }
                    }
                }
            }
            HStack {
                EntermField(placeholder: "kullanici@sunucu", text: $custom)
                Btn("Bağlan", kind: .primary) { if !custom.isEmpty { connect(custom) } }
            }
        }
        .onAppear { load() }
    }
    private func load() {
        let text = (try? String(contentsOfFile: NSHomeDirectory() + "/.ssh/config", encoding: .utf8)) ?? ""
        hosts = text.split(separator: "\n").compactMap { line -> String? in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard parts.count == 2, parts[0].lowercased() == "host", !parts[1].contains("*") else { return nil }
            return String(parts[1])
        }
    }
    private func connect(_ host: String) {
        model.page = nil
        var spec = SessionSpec(name: host, tool: .terminal, rows: 30, cols: 100)
        spec.env = ["ENTERM_STARTUP": "ssh \(NotFoundActions.shellQuote(host))"]
        model.create(spec)
    }
}

// MARK: Git

enum Git {
    @discardableResult
    static func run(_ arguments: [String], cwd: String) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return (false, "git başlatılamadı") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }
}

struct GitFile: Identifiable, Hashable {
    let path: String
    let staged: Bool
    let code: String
    var id: String { path + (staged ? "+" : "") }
}

struct ChangesPage: View {
    @ObservedObject var model = AppModel.shared
    @State private var branch = ""
    @State private var files: [GitFile] = []
    @State private var selected: GitFile?
    @State private var diff = ""
    @State private var message = ""
    @State private var notice = ""
    @State private var isRepository = true
    @State private var ahead = 0
    var cwd: String { model.focusedInfo?.cwd ?? NSHomeDirectory() }
    var body: some View {
        PageFrame(title: nil, wide: true) {
            if !isRepository {
                Dim("Bu klasör bir git deposu değil: \(model.displayPath(cwd))")
            } else {
                HStack {
                    T("Dal: \(branch)", bold: true)
                    Spacer()
                    Btn("Yenile", kind: .plain) { refresh() }
                    Btn("Ayrı Kopya: Worktree", kind: .plain) { makeWorktree() }
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        section("Hazırlanan", staged: true)
                        section("Hazırlanmayan", staged: false)
                        EntermField(placeholder: "Commit İletisi", text: $message)
                        HStack {
                            Btn("Commit", kind: .primary) { commit() }
                            if ahead > 0 { Btn("Push: \(ahead) Commit") { push() } }
                        }
                        if !notice.isEmpty { T(notice).lineLimit(3) }
                        Dim("Bu düğmeler sizin elinizle çalışır. Ajan için push yetki kartına bağlıdır.")
                    }
                    .frame(width: 400, alignment: .leading)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).prefix(2000).enumerated()), id: \.offset) { _, line in
                                T(String(line), color: color(for: line)).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                    .frame(minHeight: 480)
                }
            }
        }
        .onAppear { refresh() }
    }
    private func color(for line: Substring) -> NSColor {
        if line.hasPrefix("+") { return Theme.palette.add }
        if line.hasPrefix("-") { return Theme.palette.err }
        if line.hasPrefix("@@") { return Theme.palette.dim }
        return Theme.palette.fg
    }
    @ViewBuilder private func section(_ title: String, staged: Bool) -> some View {
        let list = files.filter { $0.staged == staged }
        HStack {
            T("\(title) \(list.count)", bold: true)
            Spacer()
            Btn(staged ? "Hepsini Geri Al" : "Hepsini Hazırla", kind: .plain) {
                Git.run(staged ? ["reset", "-q"] : ["add", "-A"], cwd: cwd)
                refresh()
            }
        }
        ForEach(list) { file in
            HStack {
                Button { show(file) } label: { T(file.path).lineLimit(1) }.buttonStyle(.plain)
                Spacer()
                Btn(staged ? "Geri Al" : "Hazırla", kind: .plain) {
                    Git.run(staged ? ["reset", "-q", "--", file.path] : ["add", "--", file.path], cwd: cwd)
                    refresh()
                }
            }
        }
    }
    private func refresh() {
        let top = Git.run(["rev-parse", "--show-toplevel"], cwd: cwd)
        isRepository = top.ok
        guard top.ok else { return }
        branch = Git.run(["branch", "--show-current"], cwd: cwd).output.trimmingCharacters(in: .whitespacesAndNewlines)
        var found: [GitFile] = []
        for line in Git.run(["status", "--porcelain", "-uall"], cwd: cwd).output.split(separator: "\n") where line.count > 3 {
            let index = line[line.startIndex]
            let tree = line[line.index(after: line.startIndex)]
            let path = String(line.dropFirst(3))
            if index != " " && index != "?" { found.append(GitFile(path: path, staged: true, code: String(index))) }
            if tree != " " { found.append(GitFile(path: path, staged: false, code: String(tree))) }
        }
        files = found
        ahead = Int(Git.run(["rev-list", "--count", "@{u}..HEAD"], cwd: cwd).output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if let first = selected ?? found.first { show(first) } else { diff = "" }
    }
    private func show(_ file: GitFile) {
        selected = file
        var arguments = ["diff"]
        if file.staged { arguments.append("--cached") }
        arguments += ["--", file.path]
        diff = Git.run(arguments, cwd: cwd).output
    }
    private func commit() {
        guard !message.isEmpty else {
            notice = "Commit İletisi Boş."
            return
        }
        let result = Git.run(["commit", "-m", message], cwd: cwd)
        notice = result.output.split(separator: "\n").first.map(String.init) ?? ""
        if result.ok { message = "" }
        refresh()
    }
    private func push() {
        let result = Git.run(["push"], cwd: cwd)
        notice = result.ok ? "Push Tamam." : (result.output.split(separator: "\n").last.map(String.init) ?? "Push Olmadı.")
        refresh()
    }
    private func makeWorktree() {
        let name = "enterm-\(Int(Date().timeIntervalSince1970))"
        let path = (cwd as NSString).deletingLastPathComponent + "/" + name
        let result = Git.run(["worktree", "add", "-b", name, path], cwd: cwd)
        if result.ok {
            model.page = nil
            model.newTerminal(cwd: path)
        } else {
            notice = result.output.split(separator: "\n").last.map(String.init) ?? "Olmadı."
        }
    }
}

// MARK: Browser

/// A system web view. It starts when the page opens and is released when it closes.
final class BrowserState: ObservableObject {
    @Published var address = "http://localhost:3000"
    @Published var failure: String?
}

struct WebView: NSViewRepresentable {
    @ObservedObject var state: BrowserState
    let reload: Int
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        if let url = URL(string: state.address) { view.load(URLRequest(url: url)) }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.lastReload != reload {
            context.coordinator.lastReload = reload
            if let url = URL(string: state.address) {
                state.failure = nil
                view.load(URLRequest(url: url))
            }
        }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: BrowserState
        var lastReload = 0
        init(state: BrowserState) { self.state = state }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.failure = "Bağlanamadı: \(state.address)"
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url?.absoluteString { state.address = url }
        }
    }
}

struct BrowserPage: View {
    @StateObject private var state = BrowserState()
    @State private var reload = 0
    @ObservedObject var power = PowerCenter.shared
    var body: some View {
        PageFrame(title: nil, wide: true) {
            HStack {
                EntermField(placeholder: "Adres", text: $state.address).onSubmit { reload += 1 }
                Btn("Git", kind: .primary) { reload += 1 }
            }
            if let failure = state.failure {
                T("✕ \(failure)", color: Theme.palette.err)
            }
            WebView(state: state, reload: reload).frame(minHeight: 520)
            Dim("Tarayıcı bilgisayarda çalışır, yalnız bu sayfa açıkken yük bindirir. Oturum açma bilgileri saklanmaz. Ajanın bu tarayıcıyı kullanması ve devralma Henüz Yok.")
        }
    }
}

// MARK: Restore after a restart

enum Restore {
    static func start(_ info: SessionInfo) {
        let model = AppModel.shared
        guard FileManager.default.fileExists(atPath: info.cwd) else {
            model.hint = "Klasör Bulunamadı: \(info.cwd)"
            return
        }
        guard info.tool != .terminal else {
            model.create(SessionSpec(name: info.name.isEmpty ? nil : info.name, tool: .terminal, cwd: info.cwd, rows: 30, cols: 100)) { created in
                let log = EntermPaths.scrollbackDir.appendingPathComponent("\(info.id).log")
                guard let data = try? Data(contentsOf: log), !data.isEmpty else { return }
                let stamp = Date().formatted(date: .omitted, time: .shortened)
                let banner = "\r\n\u{1B}[2mBilgisayar Yeniden Başladı · Yukarısı Eski Döküm · \(stamp)\u{1B}[0m\r\n"
                model.hosts[created.number]?.feedOutput(data + Data(banner.utf8), replay: true)
                try? FileManager.default.removeItem(at: log)
            }
            return
        }
        var arguments = ""
        if let id = info.toolSessionID {
            switch info.tool {
            case .claude: arguments = "--resume \(NotFoundActions.shellQuote(info.transcriptPath ?? id))"
            case .codex: arguments = "resume \(NotFoundActions.shellQuote(id))"
            case .antigravity: arguments = "--conversation=\(NotFoundActions.shellQuote(id))"
            case .terminal: break
            }
        }
        ToolLauncher.start(info.tool, cwd: info.cwd, name: info.name.isEmpty ? nil : info.name, accountID: info.accountID, extraArguments: arguments)
    }
}

struct RestorePage: View {
    @ObservedObject var model = AppModel.shared
    @State private var pending: [SessionInfo] = []
    var body: some View {
        PageFrame(title: "Oturumlar Geri Gelsin Mi") {
            Dim("Bilgisayar Yeniden Başladı. Dökümler yerinde. Ajanlar kendiliğinden başlamaz, açtığınızda konuşma kaldığı yerden sürer, ilk mesajda limitten yer.")
            Panel {
                ForEach(pending) { info in
                    let exists = FileManager.default.fileExists(atPath: info.cwd)
                    Row {
                        VStack(alignment: .leading) {
                            T(info.name.isEmpty ? model.displayPath(info.cwd) : info.name, bold: true)
                            Dim("\(info.tool.title) · \(model.displayPath(info.cwd))")
                        }
                        Spacer()
                        if exists {
                            Btn(info.tool == .terminal ? "Dökümle Aç" : "Sürdür") {
                                Restore.start(info)
                                pending.removeAll { $0.id == info.id }
                                if pending.isEmpty { model.page = nil }
                            }
                        } else {
                            T("✕ Klasör Bulunamadı", color: Theme.palette.err)
                        }
                    }
                    Line()
                }
            }
            HStack {
                Btn("Boş Başla", kind: .plain) { model.page = nil }
                Btn("Şimdi Değil", kind: .plain, key: "Esc") { model.page = nil }
                Btn("Hepsini Sürdür", kind: .primary, key: "⏎") {
                    pending.forEach { Restore.start($0) }
                    model.page = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { pending = model.restorable }
    }
}
