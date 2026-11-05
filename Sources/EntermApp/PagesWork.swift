import AppKit
import EntermCore
import SwiftUI

// MARK: Session list

struct SessionListPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
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
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @State private var items: [PastConversation] = []
    var body: some View {
        let cwd = model.focusedInfo?.cwd ?? NSHomeDirectory()
        PageFrame(title: "Geçmiş Konuşmalar") {
            Dim(model.displayPath(cwd)).lineLimit(1).truncationMode(.head)
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
                MenuRow(title: "Beyaz Tahta", note: "Çizin, Ajana Gösterin") { model.page = .whiteboard }
                MenuRow(title: "Çalıştır", note: "Projenin Sunucularını Başlatın") { model.page = .run }
                MenuRow(title: "iOS Simülatörü", note: "Uygulamanızı Yanında Görün") { model.page = .simulator }
            }
        }
    }
}

struct FilesPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @State private var path = ""
    @State private var items: [(name: String, directory: Bool)] = []
    @State private var failed = false
    var body: some View {
        PageFrame(title: "Dosyalar") {
            Dim(model.displayPath(path)).lineLimit(1).truncationMode(.head)
            if let remote = model.focused.flatMap({ model.remotes[$0] }) { Dim("Uzak: \(remote.host). Dosyalar sunucuda, görünüm burada.") }
            Btn("‹ Üst Klasör", kind: .plain) { open((path as NSString).deletingLastPathComponent) }
            if failed { T("✕ Liste Alınamadı", color: Theme.palette.err) }
            Panel {
                ForEach(items, id: \.name) { item in
                    MenuRow(title: item.name + (item.directory ? "/" : "")) {
                        let target = (path as NSString).appendingPathComponent(item.name)
                        if item.directory { open(target) } else { model.page = .editor(target) }
                    }
                }
            }
        }
        .onAppear { open(model.currentRunner.folder) }
    }
    private func open(_ directory: String) {
        path = directory
        let result = model.currentRunner.listing(directory)
        failed = !result.ok
        items = result.items
    }
}

struct EditorPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let path: String
    @ObservedObject var model = AppModel.shared
    @State private var text = ""
    @State private var state = ""
    @State private var loaded = false
    var body: some View {
        PageFrame(title: model.displayPath(path), wide: true) {
            HStack {
                Btn("Kaydet", kind: .primary, key: "⌘S") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!loaded)
                Dim(state)
            }
            TextEditor(text: $text)
                .font(Theme.swiftFont())
                .frame(minHeight: 480)
                .scrollContentBackground(.hidden)
                .background(Color(Theme.palette.panel))
        }
        .onAppear {
            if let value = model.currentRunner.readText(path) {
                text = value
                loaded = true
            } else {
                state = "Bu Dosya Burada Açılamıyor: Çok Büyük Ya Da Metin Değil."
            }
        }
    }
    private func save() {
        state = model.currentRunner.writeText(text, to: path) ? "Kaydedildi." : "Kaydedilemedi."
    }
}

struct NotePage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
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
    @State private var host = ""
    @State private var folder = "~"
    var body: some View {
        PageFrame(title: "Uzak Sunucu") {
            if !hosts.isEmpty {
                Panel {
                    ForEach(hosts, id: \.self) { item in
                        MenuRow(title: item, note: "~/.ssh/config", selected: host == item) { host = item }
                    }
                }
            }
            EntermField(placeholder: "Sunucu: kullanici@sunucu", text: $host)
            EntermField(placeholder: "Uzak Klasör: /var/www/site", text: $folder)
            Dim("Terminal, dosya ve git sunucuda çalışır, görünüm bu bilgisayarda kalır. Anahtarlar ~/.ssh içinde durur, Enterm okumaz. Uzak makinede kurulum kartı ve ajan durumu görünmez.")
            HStack {
                Btn("Vazgeç", kind: .plain, key: "Esc") { model.page = nil }
                Btn("Bağlan", kind: .primary, key: "⏎") { connect() }.keyboardShortcut(.defaultAction).disabled(host.isEmpty)
            }
        }
        .onAppear {
            let text = (try? String(contentsOfFile: NSHomeDirectory() + "/.ssh/config", encoding: .utf8)) ?? ""
            hosts = SSHCommand.hosts(fromConfig: text)
        }
    }
    private func connect() {
        model.page = nil
        RemoteProject(host: host, folder: folder).open()
    }
}

// MARK: Git

enum Git {
    @discardableResult
    static func run(_ arguments: [String], runner: CommandRunner) -> (ok: Bool, output: String) {
        runner.run(["git"] + arguments)
    }
}

struct GitFile: Identifiable, Hashable {
    let path: String
    let staged: Bool
    let code: String
    var id: String { path + (staged ? "+" : "") }
}

struct ChangesPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @State private var branch = ""
    @State private var files: [GitFile] = []
    @State private var selected: GitFile?
    @State private var diff = ""
    @State private var message = ""
    @State private var notice = ""
    @State private var isRepository = true
    @State private var ahead = 0
    @State private var writing = false
    var cwd: String { model.focusedInfo?.cwd ?? NSHomeDirectory() }
    var runner: CommandRunner { model.currentRunner }
    var body: some View {
        PageFrame(title: "Değişiklikler", wide: isRepository) {
            if let remote = model.focused.flatMap({ model.remotes[$0] }) { Dim("Uzak: \(remote.host):\(remote.folder)") }
            if !isRepository {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        T("Bu Klasör Bir Git Deposu Değil", bold: true)
                        Dim(model.displayPath(runner.folder)).lineLimit(1).truncationMode(.head)
                        Btn("Burada Git Başlat") {
                            Git.run(["init"], runner: runner)
                            refresh()
                        }
                    }
                    .padding(16)
                }
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
                            Btn(writing ? "Yazıyor" : "İleti Yaz", kind: .plain, icon: "sparkle") { writeMessage() }
                                .disabled(writing || !files.contains { $0.staged })
                                .help("Hazırlanan değişikliği \(SettingsStore.shared.settings.commitProgram == "codex" ? "Codex" : "Claude Code") okur ve ileti önerir")
                            if ahead > 0 { Btn("Push: \(ahead) Commit") { push() } }
                        }
                        if !notice.isEmpty { T(notice).lineLimit(3) }
                        Dim("Bu düğmeler sizin elinizle çalışır. Ajan için push yetki kartına bağlıdır.")
                    }
                    .frame(width: 400, alignment: .leading)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).prefix(2000).enumerated()), id: \.offset) { _, line in
                                Mono(String(line), color: color(for: line)).lineLimit(1)
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
                Git.run(staged ? ["reset", "-q"] : ["add", "-A"], runner: runner)
                refresh()
            }
        }
        ForEach(list) { file in
            HStack {
                Button { show(file) } label: { T(file.path).lineLimit(1) }.buttonStyle(.plain)
                Spacer()
                Btn(staged ? "Geri Al" : "Hazırla", kind: .plain) {
                    Git.run(staged ? ["reset", "-q", "--", file.path] : ["add", "--", file.path], runner: runner)
                    refresh()
                }
            }
        }
    }
    private func refresh() {
        let top = Git.run(["rev-parse", "--show-toplevel"], runner: runner)
        isRepository = top.ok
        guard top.ok else { return }
        branch = Git.run(["branch", "--show-current"], runner: runner).output.trimmingCharacters(in: .whitespacesAndNewlines)
        var found: [GitFile] = []
        for line in Git.run(["status", "--porcelain", "-uall"], runner: runner).output.split(separator: "\n") where line.count > 3 {
            let index = line[line.startIndex]
            let tree = line[line.index(after: line.startIndex)]
            let path = String(line.dropFirst(3))
            if index != " " && index != "?" { found.append(GitFile(path: path, staged: true, code: String(index))) }
            if tree != " " { found.append(GitFile(path: path, staged: false, code: String(tree))) }
        }
        files = found
        ahead = Int(Git.run(["rev-list", "--count", "@{u}..HEAD"], runner: runner).output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if let first = selected ?? found.first { show(first) } else { diff = "" }
    }
    /// Runs only on this click, with the person's own program and account.
    private func writeMessage() {
        let diff = String(Git.run(["diff", "--cached"], runner: runner).output.prefix(40000))
        let settings = SettingsStore.shared.settings
        writing = true
        notice = ""
        let folder = runner.folder
        DispatchQueue.global(qos: .userInitiated).async {
            let prompt = "Aşağıdaki git değişikliği için kısa bir commit iletisi yaz. Yalnız iletiyi yaz, başka hiçbir şey ekleme. \(settings.commitPrompt)\n\n\(diff)"
            let line = settings.commitProgram == "codex" ? "codex exec \(NotFoundActions.shellQuote(prompt))" : "claude -p \(NotFoundActions.shellQuote(prompt))"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
            process.arguments = ["-ilc", line]
            process.currentDirectoryURL = URL(fileURLWithPath: folder)
            let pipe = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var answer = ""
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 { answer = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            DispatchQueue.main.async {
                writing = false
                if answer.isEmpty { notice = "İleti Yazılamadı" } else { message = answer }
            }
        }
    }

    private func show(_ file: GitFile) {
        selected = file
        var arguments = ["diff"]
        if file.staged { arguments.append("--cached") }
        arguments += ["--", file.path]
        diff = Git.run(arguments, runner: runner).output
    }
    private func commit() {
        guard !message.isEmpty else {
            notice = "Commit İletisi Boş."
            return
        }
        let result = Git.run(["commit", "-m", message], runner: runner)
        notice = result.output.split(separator: "\n").first.map(String.init) ?? ""
        if result.ok { message = "" }
        refresh()
    }
    private func push() {
        let result = Git.run(["push"], runner: runner)
        notice = result.ok ? "Push Tamam." : (result.output.split(separator: "\n").last.map(String.init) ?? "Push Olmadı.")
        refresh()
    }
    private func makeWorktree() {
        let name = "enterm-\(Int(Date().timeIntervalSince1970))"
        let path = (runner.folder as NSString).deletingLastPathComponent + "/" + name
        let result = Git.run(["worktree", "add", "-b", name, path], runner: runner)
        if result.ok {
            model.page = nil
            if model.focused.flatMap({ model.remotes[$0] }) == nil { model.newTerminal(cwd: path) }
        } else {
            notice = result.output.split(separator: "\n").last.map(String.init) ?? "Olmadı."
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
                let banner = "\r\n\u{1B}[2mBilgisayar yeniden başladı · Çalışan komutlar durdu · Yukarısı eski döküm · \(stamp)\u{1B}[0m\r\n"
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
            default: break
            }
        }
        if info.tool == .custom, let program = SettingsStore.shared.settings.customPrograms.first(where: { $0.name == info.name }) {
            ToolLauncher.start(program, cwd: info.cwd)
            return
        }
        ToolLauncher.start(info.tool, cwd: info.cwd, name: info.name.isEmpty ? nil : info.name, accountID: info.accountID, extraArguments: arguments)
    }
}

struct RestorePage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @State private var pending: [SessionInfo] = []
    var body: some View {
        PageFrame(title: "Oturumlar Geri Gelsin Mi?") {
            Dim("Bilgisayar yeniden başladı. Dökümler yerinde. Ajanlar kendiliğinden başlamaz, açtığınızda konuşma kaldığı yerden sürer, ilk mesajda limitten yer.")
            Panel {
                let names = SessionLabel.names(pending)
                ForEach(pending) { info in
                    let exists = FileManager.default.fileExists(atPath: info.cwd)
                    Row {
                        VStack(alignment: .leading) {
                            T(names[info.number] ?? info.tool.title, bold: true)
                            Dim(model.displayPath(info.cwd))
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
                Spacer()
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
