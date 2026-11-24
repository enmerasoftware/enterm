import AppKit
import EntermCore
import SwiftUI

// MARK: The Library

/// Reads the shared Library, keeps what the person saved, and turns an item into a session, a race or a skill pack.
/// Nothing runs by itself: every action starts from a button on an item the person is looking at.
final class LibraryCenter: ObservableObject {
    static let shared = LibraryCenter()
    @Published private(set) var index: LibraryIndex
    @Published private(set) var shelf = LibraryShelf.load()
    @Published private(set) var loading = false
    @Published private(set) var problem: String?
    /// A skill pack downloaded and waiting for the person to look at its files and add it.
    @Published private(set) var staged: StagedSkill?
    private var lastRead = Date.distantPast

    struct StagedSkill: Equatable {
        let item: LibraryEntry
        let folder: URL
        let files: [String]
        /// Files that run something: shown first, so they are read before the pack is added.
        let scripts: [String]
    }

    private init() {
        index = (try? Data(contentsOf: LibraryIndex.cacheFile)).flatMap(LibraryIndex.parse) ?? LibraryIndex()
    }

    /// Fetches the index again at most every few minutes; the saved copy shows meanwhile and offline.
    func refresh(force: Bool = false) {
        guard !loading, force || Date().timeIntervalSince(lastRead) > 300 else { return }
        loading = true
        problem = nil
        var request = URLRequest(url: LibraryIndex.indexURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Enterm/\(EntermVersion.current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200, let fresh = LibraryIndex.parse(data) else {
                    self.problem = self.index.items.isEmpty ? "Kütüphaneye ulaşılamadı. İnternet bağlantınızı denetleyip yeniden deneyin." : nil
                    return
                }
                self.lastRead = Date()
                self.index = fresh
                try? data.write(to: LibraryIndex.cacheFile, options: .atomic)
            }
        }.resume()
    }

    func isSaved(_ item: LibraryEntry) -> Bool { shelf.saved.contains(item.id) }

    func toggleSave(_ item: LibraryEntry) {
        shelf.toggle(item.id)
        shelf.save()
    }

    var savedItems: [LibraryEntry] { shelf.saved.compactMap { id in index.items.first { $0.id == id } } }

    // MARK: Using an item

    /// A new session with the prompt as its first message, in the folder in front of the person.
    func run(_ item: LibraryEntry, with tool: ToolKind, folder: String) {
        guard let text = item.text, !text.isEmpty else { return }
        let quoted = NotFoundActions.shellQuote(text)
        let arguments = tool == .gemini ? "-i \(quoted)" : quoted
        AppModel.shared.page = nil
        ToolLauncher.start(tool, cwd: folder, name: item.title(turkish: Loc.isTurkish), extraArguments: arguments)
    }

    /// The race page with this task and its test command filled in.
    func race(_ item: LibraryEntry) {
        RaceCenter.shared.prefill = (item.text ?? "", item.test ?? "", false)
        AppModel.shared.page = .raceSetup
    }

    // MARK: Skill packs

    /// Downloads the pack into a temporary folder and lists its files. It is added only when the person says so.
    func stage(_ item: LibraryEntry) {
        guard let source = item.skill, !loading else { return }
        loading = true
        problem = nil
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("enterm-skill-\(UUID().uuidString)", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.download(source, into: work)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                switch result {
                case .success(let folder):
                    let files = Self.files(in: folder)
                    let scripts = files.filter { Self.runs($0) }
                    self.staged = StagedSkill(item: item, folder: folder, files: files, scripts: scripts)
                case .failure(let message):
                    self.problem = message.text
                }
            }
        }
    }

    func cancelStaged() {
        if let staged { try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent()) }
        staged = nil
    }

    /// Moves the looked-at pack into Enterm's own skills folder and switches it on for new Claude Code sessions.
    func addStaged() {
        guard let staged else { return }
        let manager = FileManager.default
        let target = SkillPack.userRoot.appendingPathComponent(LibraryShare.folderName(for: staged.item), isDirectory: true)
        try? manager.createDirectory(at: SkillPack.userRoot, withIntermediateDirectories: true)
        try? manager.removeItem(at: target)
        do {
            try manager.copyItem(at: staged.folder, to: target)
        } catch {
            problem = "Paket eklenemedi: \(error.localizedDescription)"
            return
        }
        cancelStaged()
        if let pack = SkillPack.packs(in: SkillPack.userRoot).first(where: { $0.folder.standardizedFileURL == target.standardizedFileURL }) {
            let store = SettingsStore.shared
            if !store.settings.skillPacks.contains(pack.id) { store.settings.skillPacks.append(pack.id) }
        }
        shelf.installedSkills[staged.item.id] = Date()
        shelf.save()
        AppModel.shared.hint = "Beceri Paketi Eklendi · Yeni Claude Code Oturumlarında"
    }

    func removeSkill(_ item: LibraryEntry) {
        let target = SkillPack.userRoot.appendingPathComponent(LibraryShare.folderName(for: item), isDirectory: true)
        if let pack = SkillPack.packs(in: SkillPack.userRoot).first(where: { $0.folder.standardizedFileURL == target.standardizedFileURL }) {
            SettingsStore.shared.settings.skillPacks.removeAll { $0 == pack.id }
        }
        try? FileManager.default.removeItem(at: target)
        shelf.installedSkills[item.id] = nil
        shelf.save()
    }

    func isInstalled(_ item: LibraryEntry) -> Bool { shelf.installedSkills[item.id] != nil }

    private struct Failure: Error { let text: String }

    /// The repository's archive from GitHub, unpacked with the system's tar; only the pack's own folder is kept.
    private static func download(_ source: LibraryEntry.SkillSource, into work: URL) -> Result<URL, Failure> {
        let manager = FileManager.default
        guard source.repo.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil,
              !source.path.contains(".."), let url = URL(string: "https://codeload.github.com/\(source.repo)/tar.gz/\(source.ref)") else {
            return .failure(Failure(text: "Paketin adresi geçersiz."))
        }
        try? manager.createDirectory(at: work, withIntermediateDirectories: true)
        let archive = work.appendingPathComponent("pack.tar.gz")
        let semaphore = DispatchSemaphore(value: 0)
        var downloaded = false
        URLSession.shared.downloadTask(with: url) { file, response, _ in
            if let file, (response as? HTTPURLResponse)?.statusCode == 200 {
                downloaded = (try? manager.moveItem(at: file, to: archive)) != nil
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 60)
        guard downloaded else { return .failure(Failure(text: "Paket indirilemedi. Bağlantınızı denetleyip yeniden deneyin.")) }
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        try? manager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path, "-C", unpacked.path]
        do { try tar.run() } catch { return .failure(Failure(text: "Paket açılamadı.")) }
        tar.waitUntilExit()
        // GitHub puts everything under one "<repo>-<ref>" folder.
        guard tar.terminationStatus == 0, let top = (try? manager.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil))?.first else {
            return .failure(Failure(text: "Paket açılamadı."))
        }
        let folder = top.appendingPathComponent(source.path, isDirectory: true).standardizedFileURL
        guard folder.path.hasPrefix(top.standardizedFileURL.path),
              manager.fileExists(atPath: folder.appendingPathComponent(".claude-plugin/plugin.json").path) else {
            return .failure(Failure(text: "Bu klasör bir beceri paketi değil: .claude-plugin/plugin.json yok."))
        }
        return .success(folder)
    }

    private static func files(in folder: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var out: [String] = []
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            out.append(String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1)))
        }
        return out.sorted()
    }

    /// Scripts and hooks: what a skill could run, as opposed to what it only reads.
    private static func runs(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        let ext = (path as NSString).pathExtension.lowercased()
        return ["sh", "bash", "zsh", "py", "js", "mjs", "cjs", "ts", "rb", "pl", "swift"].contains(ext)
            || name == "hooks.json" || path.hasPrefix("hooks/") || path.contains("/hooks/")
    }
}

// MARK: The page

struct LibraryPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var center = LibraryCenter.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var catalog = ToolCatalog.shared
    @State var selected: String?
    @State private var query = ""
    @State private var kind: LibraryEntry.Kind?
    @State private var tag: String?
    @State private var savedOnly = false
    @State private var sharing = false

    var body: some View {
        PageFrame(title: "Kütüphane", wide: true) {
            VStack(alignment: .leading, spacing: 16) {
                Dim("Topluluğun paylaştığı istemler, yarış görevleri ve beceri paketleri. Hiçbir şey kendiliğinden çalışmaz: önce okursunuz, sonra tek tıkla kullanırsınız.")
                    .fixedSize(horizontal: false, vertical: true)
                toolbar
                if let problem = center.problem { T(problem, color: Theme.palette.err, style: .secondary) }
                HStack(alignment: .top, spacing: 16) {
                    list.frame(width: 360)
                    detail.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .onAppear {
            center.refresh()
            catalog.refresh()
            if selected == nil { selected = results.first?.id }
        }
        .sheet(isPresented: $sharing) { LibraryShareSheet { sharing = false } }
        .sheet(isPresented: Binding(get: { center.staged != nil }, set: { if !$0 { center.cancelStaged() } })) {
            if let staged = center.staged { SkillReview(staged: staged) }
        }
    }

    private var results: [LibraryEntry] {
        center.index.filter(query: query, kind: kind, tag: tag, saved: savedOnly ? Set(center.shelf.saved) : nil)
    }

    private var toolbar: some View {
        // The search takes the room left; the rest keep their size.
        HStack(spacing: 8) {
            EntermField(placeholder: "Kütüphanede Ara", text: $query).frame(minWidth: 180, maxWidth: .infinity)
            Btn(savedOnly ? "Kaydedilenler ✓" : "Kaydedilenler", kind: savedOnly ? .selected : .plain, icon: "bookmark") { savedOnly.toggle() }
                .fixedSize()
            if center.loading { ProgressView().controlSize(.small) }
            IconBtn("arrow.clockwise", label: "Yenile") { center.refresh(force: true) }.help("Yenile")
            Btn("İstem Paylaş", kind: .outline, icon: "square.and.arrow.up") { sharing = true }.fixedSize()
        }
    }

    private var list: some View {
        let palette = Theme.palette
        return Panel {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Seg(options: [(nil, "Tümü"), (.prompt, "İstemler"), (.race, "Yarış"), (.skill, "Beceriler")] as [(LibraryEntry.Kind?, String)], value: $kind)
                        .padding([.horizontal, .top], 12)
                    tags
                    if results.isEmpty {
                        Dim(center.index.items.isEmpty ? "Kütüphane okunuyor…" : (savedOnly ? "Henüz kaydettiğiniz bir şey yok." : "Aramanıza uyan bir şey yok."))
                            .padding(16)
                    }
                    ForEach(results) { item in
                        Button { selected = item.id } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Symbol(Self.symbol(item.kind), color: item.id == selected ? palette.need : palette.text2, size: 13)
                                    .frame(width: 18)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: item.title(turkish: Loc.isTurkish))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color(palette.text1))
                                        .lineLimit(1)
                                    Text(verbatim: item.summary(turkish: Loc.isTurkish))
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(palette.text2))
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                if center.isSaved(item) { Symbol("bookmark.fill", color: palette.need, size: 11).padding(.top, 2) }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(item.id == selected ? Color(palette.fillSelected) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 420)
        }
    }

    private var tags: some View {
        let palette = Theme.palette
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(center.index.tags.prefix(14), id: \.self) { name in
                    Button { tag = tag == name ? nil : name } label: {
                        Text(verbatim: "#\(name)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(tag == name ? palette.btnfg : palette.text2))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(Color(tag == name ? palette.need : palette.fill)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let item = results.first(where: { $0.id == selected }) ?? center.index.items.first(where: { $0.id == selected }) {
            LibraryDetail(item: item)
                .id(item.id)
        } else {
            Panel {
                Dim("Soldan bir öğe seçin.").padding(16).frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }

    static func symbol(_ kind: LibraryEntry.Kind) -> String {
        switch kind {
        case .prompt: return "text.quote"
        case .race: return "flag.checkered"
        case .skill: return "puzzlepiece.extension"
        }
    }
}

/// One item, all of it: the text that will be sent, where it works, and what can be done with it.
private struct LibraryDetail: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var center = LibraryCenter.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var catalog = ToolCatalog.shared
    let item: LibraryEntry
    @State private var tool: ToolKind = .claude

    private var choices: [ToolKind] {
        let all: [ToolKind] = [.claude, .codex, .gemini, .opencode, .copilot, .cursor]
        let suited = item.programs.compactMap(ToolKind.init(rawValue:))
        return (suited.isEmpty ? all : suited).filter { !catalog.isMissing($0) }
    }

    private var folder: String { model.focusedInfo?.cwd ?? NSHomeDirectory() }

    var body: some View {
        let palette = Theme.palette
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: item.title(turkish: Loc.isTurkish)).font(.system(size: 18, weight: .semibold)).foregroundColor(Color(palette.text1))
                        Text(verbatim: item.summary(turkish: Loc.isTurkish)).font(.system(size: 13)).foregroundColor(Color(palette.text2))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    IconBtn(center.isSaved(item) ? "bookmark.fill" : "bookmark", label: center.isSaved(item) ? "Kaydedildi" : "Kaydet", active: center.isSaved(item)) {
                        center.toggleSave(item)
                    }
                    .help(center.isSaved(item) ? "Kaydedildi" : "Kaydet")
                }
                // One fact per line, so a narrow pane wraps nothing in the middle of a word.
                VStack(alignment: .leading, spacing: 3) {
                    Dim("\(L(Self.kindTitle(item.kind))) · @\(item.author)").lineLimit(1)
                    if !item.programs.isEmpty {
                        Dim(item.programs.compactMap { ToolKind(rawValue: $0)?.title }.joined(separator: " · ")).lineLimit(1)
                    }
                    if !item.tags.isEmpty { Dim(item.tags.map { "#\($0)" }.joined(separator: "  ")).lineLimit(1) }
                }
                if let text = item.text {
                    ScrollView {
                        Text(verbatim: text)
                            .font(Theme.swiftFont(size: 12))
                            .foregroundColor(Color(palette.text1))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                    }
                    .frame(minHeight: 160, maxHeight: 320)
                    .background(Color(palette.terminal))
                    .cornerRadius(Theme.cornerControl)
                    if let test = item.test { Dim(L("Önerilen test komutu: \(test)")) }
                }
                actions
            }
            .padding(16)
        }
        .onAppear { if !choices.contains(tool), let first = choices.first { tool = first } }
    }

    @ViewBuilder
    private var actions: some View {
        switch item.kind {
        case .prompt, .race:
            HStack(spacing: 8) {
                if choices.isEmpty {
                    Dim("Bu istemin çalıştığı programlardan hiçbiri kurulu değil.")
                } else {
                    ChoiceMenu(options: choices.map { ($0, $0.title) }, value: $tool).frame(width: 160)
                    Btn("Çalıştır", kind: .primary, icon: "play.fill") { center.run(item, with: tool, folder: folder) }
                }
                Btn("Yarıştır", kind: .outline, icon: "flag.checkered") { center.race(item) }
                Btn("Kopyala", kind: .plain, icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text ?? "", forType: .string)
                    model.hint = "Panoya Kopyalandı"
                }
                Spacer()
                if let url = item.webURL { Btn("GitHub'da Aç", kind: .plain) { NSWorkspace.shared.open(url) } }
            }
            Dim(L("Klasör: \(model.displayPath(folder)) · Yeni oturum bu klasörde açılır."))
        case .skill:
            HStack(spacing: 8) {
                if center.isInstalled(item) {
                    T("✓ Eklendi", color: Theme.palette.add, style: .secondary, weight: .semibold)
                    Btn("Kaldır", kind: .plain) { center.removeSkill(item) }
                } else {
                    Btn("Dosyalara Bak ve Ekle", kind: .primary, icon: "puzzlepiece.extension") { center.stage(item) }
                }
                Spacer()
                if let url = item.webURL { Btn("GitHub'da Aç", kind: .plain) { NSWorkspace.shared.open(url) } }
            }
            Dim("Paket Enterm'in kendi klasörüne iner ve yalnız yeni Claude Code oturumlarına verilir; ~/.claude klasörünüze hiçbir şey yazılmaz.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func kindTitle(_ kind: LibraryEntry.Kind) -> String {
        switch kind {
        case .prompt: return "İstem"
        case .race: return "Yarış Görevi"
        case .skill: return "Beceri Paketi"
        }
    }
}

/// A downloaded pack before it is added: every file it brings, the ones that can run something first.
struct SkillReview: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var center = LibraryCenter.shared
    let staged: LibraryCenter.StagedSkill

    var body: some View {
        let palette = Theme.palette
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: staged.item.title(turkish: Loc.isTurkish)).font(.system(size: 17, weight: .semibold)).foregroundColor(Color(palette.text1))
            Dim(L("\(staged.files.count) dosya · kaynak: \(staged.item.skill?.repo ?? "")"))
            if !staged.scripts.isEmpty {
                T("Çalıştırılabilen dosyalar: eklemeden önce okuyun", color: palette.limit, style: .secondary, weight: .semibold)
                fileList(staged.scripts, color: palette.limit)
            }
            T("Bütün dosyalar", style: .secondary, weight: .semibold)
            fileList(staged.files, color: palette.text2)
            HStack {
                Btn("Klasörü Göster", kind: .plain) { NSWorkspace.shared.activateFileViewerSelecting([staged.folder]) }
                Spacer()
                Btn("Vazgeç", kind: .plain, key: "Esc") { center.cancelStaged() }
                Btn("Ekle", kind: .primary, key: "⏎") { center.addStaged() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(Color(palette.surface1))
    }

    private func fileList(_ files: [String], color: NSColor) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(files, id: \.self) { file in
                    Text(verbatim: file).font(Theme.swiftFont(size: 11)).foregroundColor(Color(color)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: files.count > 8 ? 180 : nil)
        .background(Color(Theme.palette.fill))
        .cornerRadius(Theme.cornerControl)
    }
}

/// Sharing a prompt: written here, sent as a prefilled GitHub issue the person reads before submitting.
private struct LibraryShareSheet: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let close: () -> Void
    @State private var title = ""
    @State private var summary = ""
    @State private var text = ""
    @State private var kind: LibraryEntry.Kind = .prompt
    @State private var programs: Set<String> = ["claude"]

    var body: some View {
        let palette = Theme.palette
        VStack(alignment: .leading, spacing: 12) {
            Text("İstem Paylaş").font(.system(size: 17, weight: .semibold)).foregroundColor(Color(palette.text1))
            Dim("GitHub'da önceden doldurulmuş bir öneri açılır; göndermeden önce okursunuz. İncelendikten sonra Kütüphane'ye eklenir. Gizli bilgi, şifre ya da şirkete özel ayrıntı yazmayın.")
                .fixedSize(horizontal: false, vertical: true)
            EntermField(placeholder: "Başlık", text: $title)
            EntermField(placeholder: "Tek cümlelik özet", text: $summary)
            Seg(options: [(.prompt, "İstem"), (.race, "Yarış Görevi")] as [(LibraryEntry.Kind, String)], value: $kind)
            TextEditor(text: $text)
                .font(Theme.swiftFont(size: 12))
                .frame(height: 160)
                .padding(6)
                .background(Color(palette.terminal))
                .cornerRadius(Theme.cornerControl)
            HStack(spacing: 6) {
                ForEach(["claude", "codex", "gemini", "opencode", "copilot", "cursor"], id: \.self) { program in
                    Btn(ToolKind(rawValue: program)?.title ?? program, kind: programs.contains(program) ? .selected : .plain) {
                        if programs.contains(program) { programs.remove(program) } else { programs.insert(program) }
                    }
                }
            }
            HStack {
                Spacer()
                Btn("Vazgeç", kind: .plain, key: "Esc", action: close)
                Btn("GitHub'da Aç", kind: .primary) {
                    if let url = LibraryShare.issueURL(title: title, summary: summary, text: text, kind: kind, programs: programs.sorted()) {
                        NSWorkspace.shared.open(url)
                    }
                    close()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(Color(palette.surface1))
    }
}
