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
    /// What people shared from Enterm, published without review; and the like counts of every item.
    @Published private(set) var community: [LibraryEntry]
    @Published private(set) var votes: [String: Int] = [:]
    private var lastRead = Date.distantPast
    private static var communityCache: URL { EntermPaths.support.appendingPathComponent("library-community.json") }

    struct StagedSkill: Equatable {
        let item: LibraryEntry
        let folder: URL
        let files: [String]
        /// Files that run something: shown first, so they are read before the pack is added.
        let scripts: [String]
    }

    private init() {
        index = (try? Data(contentsOf: LibraryIndex.cacheFile)).flatMap(LibraryIndex.parse) ?? LibraryIndex()
        community = (try? Data(contentsOf: Self.communityCache)).flatMap(CommunityLibrary.parse) ?? []
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
        get(CommunityLibrary.listURL) { [weak self] data in
            guard let self, let items = CommunityLibrary.parse(data) else { return }
            self.community = items
            try? data.write(to: Self.communityCache, options: .atomic)
        }
        get(CommunityLibrary.votesURL) { [weak self] data in
            if let votes = CommunityLibrary.parseVotes(data) { self?.votes = votes }
        }
    }

    /// The reviewed Library and the community shelf together, with the latest like counts.
    var everything: LibraryIndex {
        var all = index
        all.items = (index.items + community).map { item in
            var item = item
            item.votes = votes[item.id] ?? item.votes
            return item
        }
        return all
    }

    func item(_ id: String) -> LibraryEntry? {
        everything.items.first { $0.id == id } ?? shelf.kept.first { $0.id == id }
    }

    func isSaved(_ item: LibraryEntry) -> Bool { shelf.saved.contains(item.id) }

    func toggleSave(_ item: LibraryEntry) {
        shelf.toggle(item)
        shelf.save()
    }

    var savedItems: [LibraryEntry] { shelf.saved.compactMap(item) }

    // MARK: The community shelf

    func isLiked(_ item: LibraryEntry) -> Bool { shelf.liked.contains(item.id) }
    func isMine(_ item: LibraryEntry) -> Bool { shelf.mine.contains(item.id) }
    func likes(_ item: LibraryEntry) -> Int { votes[item.id] ?? item.votes }

    /// Likes or takes the like back at once on screen; the server's count replaces the guess when it answers.
    func toggleLike(_ item: LibraryEntry) {
        let like = !isLiked(item)
        if like { shelf.liked.insert(item.id) } else { shelf.liked.remove(item.id) }
        shelf.save()
        votes[item.id] = max(0, likes(item) + (like ? 1 : -1))
        post("vote", ["id": item.id, "like": like]) { [weak self] status, json in
            guard let self else { return }
            if status == 200, let count = json["votes"] as? Int { self.votes[item.id] = count }
        }
    }

    func report(_ item: LibraryEntry, reason: String) {
        post("report", ["id": item.id, "reason": reason]) { status, _ in
            AppModel.shared.hint = status == 200 ? "Bildirildi · Teşekkürler" : "Bildirim Gönderilemedi"
        }
    }

    /// Takes back something this Mac shared.
    func withdraw(_ item: LibraryEntry) {
        post("delete", ["id": item.id]) { [weak self] status, json in
            guard let self else { return }
            guard status == 200 else {
                AppModel.shared.hint = (json["error"] as? String) ?? "Geri Alınamadı"
                return
            }
            self.community.removeAll { $0.id == item.id }
            self.shelf.mine.remove(item.id)
            if self.isSaved(item) { self.shelf.toggle(item) }
            self.shelf.save()
            AppModel.shared.hint = "Paylaşım Geri Alındı"
        }
    }

    /// Publishes a prompt or race task to the community shelf. The answer is the new item, or why not, in the person's language.
    func share(_ submission: CommunityLibrary.Submission, done: @escaping (Result<LibraryEntry, ShareFailure>) -> Void) {
        guard let body = try? JSONEncoder().encode(submission),
              var fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return }
        fields["device"] = nil
        post("submit", fields) { [weak self] status, json in
            guard let self else { return }
            if status == 201, let raw = json["item"] as? [String: Any], let item = CommunityLibrary.entry(raw) {
                self.community.insert(item, at: 0)
                self.shelf.mine.insert(item.id)
                self.shelf.save()
                done(.success(item))
                return
            }
            let message: String
            switch status {
            case 0: message = L("Sunucuya ulaşılamadı. İnternet bağlantınızı denetleyip yeniden deneyin.")
            case 429: message = L("Kısa sürede çok paylaştınız. Biraz sonra yeniden deneyin.")
            case 409: message = L("Bu istem Kütüphane'de zaten var.")
            default: message = (json["error"] as? String) ?? L("Paylaşılamadı.")
            }
            done(.failure(ShareFailure(text: message)))
        }
    }

    struct ShareFailure: Error { let text: String }

    private func get(_ url: URL, _ use: @escaping (Data) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Enterm/\(EntermVersion.current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async { use(data) }
        }.resume()
    }

    /// A POST with this Mac's random id; status 0 when the server could not be reached.
    private func post(_ name: String, _ fields: [String: Any], _ done: @escaping (Int, [String: Any]) -> Void) {
        var fields = fields
        fields["device"] = CommunityLibrary.deviceID
        var request = URLRequest(url: CommunityLibrary.endpoint(name), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Enterm/\(EntermVersion.current)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: fields)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            DispatchQueue.main.async { done(status, json) }
        }.resume()
    }

    // MARK: Using an item

    /// A new session with the prompt as its first message, in the folder in front of the person.
    func run(_ item: LibraryEntry, with tool: ToolKind, folder: String, values: [String: String] = [:]) {
        guard let raw = item.text, !raw.isEmpty else { return }
        let text = PromptVariables.fill(raw, with: values)
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
    @State private var shelfFilter: String?
    @State private var sharing = false

    var body: some View {
        PageFrame(title: "Kütüphane", wide: true) {
            VStack(alignment: .leading, spacing: 16) {
                Dim("İncelenmiş istemler, yarış görevleri ve beceri paketleri; bir de topluluğun Enterm'den paylaştıkları. Hiçbir şey kendiliğinden çalışmaz: önce okursunuz, sonra tek tıkla kullanırsınız.")
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
        .sheet(isPresented: $sharing) {
            LibraryShareSheet(tags: center.index.tags) { shared in
                sharing = false
                if let shared {
                    shelfFilter = nil
                    savedOnly = false
                    query = ""
                    kind = nil
                    tag = nil
                    selected = shared.id
                }
            }
        }
        .sheet(isPresented: Binding(get: { center.staged != nil }, set: { if !$0 { center.cancelStaged() } })) {
            if let staged = center.staged { SkillReview(staged: staged) }
        }
    }

    private var results: [LibraryEntry] {
        var all = center.everything
        if savedOnly { all.items += center.shelf.kept.filter { kept in !all.items.contains { $0.id == kept.id } } }
        return all.filter(query: query, kind: kind, tag: tag, saved: savedOnly ? Set(center.shelf.saved) : nil)
            .filter { shelfFilter == nil || (shelfFilter == "community") == $0.isCommunity }
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
                    Seg(options: [(nil, "Tümü"), ("library", "İncelenmiş"), ("community", "Topluluk")] as [(String?, String)], value: $shelfFilter)
                        .padding([.horizontal, .top], 12)
                    Seg(options: [(nil, "Tümü"), (.prompt, "İstemler"), (.race, "Yarış"), (.skill, "Beceriler")] as [(LibraryEntry.Kind?, String)], value: $kind)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    tags
                    if results.isEmpty {
                        Dim(center.index.items.isEmpty ? "Kütüphane okunuyor…" : (savedOnly ? "Henüz kaydettiğiniz bir şey yok." : (shelfFilter == "community" && query.isEmpty && tag == nil ? "Toplulukta henüz bir şey yok. İlk paylaşan siz olun: İstem Paylaş." : "Aramanıza uyan bir şey yok.")))
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
                                    if item.isCommunity {
                                        Text(L(item.isReviewedCommunity ? "Topluluk · İncelendi" : "Topluluk · İncelenmedi"))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Color(item.isReviewedCommunity ? palette.add : palette.limit))
                                    }
                                }
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 4) {
                                    if center.isSaved(item) { Symbol("bookmark.fill", color: palette.need, size: 11) }
                                    if center.likes(item) > 0 {
                                        Text(verbatim: "♥ \(center.likes(item))").font(.system(size: 11)).foregroundColor(Color(palette.text3))
                                    }
                                }
                                .padding(.top, 2)
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
                ForEach(center.everything.tags.prefix(14), id: \.self) { name in
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
        if let item = results.first(where: { $0.id == selected }) ?? selected.flatMap(center.item) {
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
    @State private var filling = false
    @State private var values: [String: String] = [:]

    private var variables: [PromptVariables.Variable] { PromptVariables.find(in: item.text ?? "") }

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
                    Btn("\(center.likes(item))", kind: center.isLiked(item) ? .selected : .plain, icon: center.isLiked(item) ? "heart.fill" : "heart") {
                        center.toggleLike(item)
                    }
                    .fixedSize()
                    .help(center.isLiked(item) ? "Beğeniyi Geri Al" : "Beğen")
                    IconBtn(center.isSaved(item) ? "bookmark.fill" : "bookmark", label: center.isSaved(item) ? "Kaydedildi" : "Kaydet", active: center.isSaved(item)) {
                        center.toggleSave(item)
                    }
                    .help(center.isSaved(item) ? "Kaydedildi" : "Kaydet")
                }
                // One fact per line, so a narrow pane wraps nothing in the middle of a word.
                VStack(alignment: .leading, spacing: 3) {
                    Dim(item.isCommunity ? "\(L(Self.kindTitle(item.kind))) · \(item.author) · \(L(item.isReviewedCommunity ? "Topluluk · İncelendi" : "Topluluk · İncelenmedi"))" : "\(L(Self.kindTitle(item.kind))) · @\(item.author)").lineLimit(1)
                    if !item.programs.isEmpty {
                        Dim(item.programs.compactMap { ToolKind(rawValue: $0)?.title }.joined(separator: " · ")).lineLimit(1)
                    }
                    if !item.tags.isEmpty { Dim(item.tags.map { "#\($0)" }.joined(separator: "  ")).lineLimit(1) }
                }
                if item.isCommunity && !item.isReviewedCommunity {
                    T("Bu istem incelenmeden yayınlandı. Çalıştırmadan önce okuyun; sorunluysa bildirin.", color: palette.limit, style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        .sheet(isPresented: $filling) {
            VariablesSheet(item: item, variables: variables, values: $values) { go in
                filling = false
                if go { center.run(item, with: tool, folder: folder, values: values) }
            }
        }
    }

    private func start() {
        if variables.isEmpty { center.run(item, with: tool, folder: folder) } else { filling = true }
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
                    Btn("Çalıştır", kind: .primary, icon: "play.fill") { start() }
                }
                Btn("Yarıştır", kind: .outline, icon: "flag.checkered") { center.race(item) }
                Btn("Kopyala", kind: .plain, icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text ?? "", forType: .string)
                    model.hint = "Panoya Kopyalandı"
                }
                Spacer()
                if item.isCommunity { communityMenu }
                if let url = item.webURL { Btn(item.isCommunity ? "Sitede Aç" : "GitHub'da Aç", kind: .plain) { NSWorkspace.shared.open(url) } }
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

    /// Report it, or take it back when this Mac shared it.
    private var communityMenu: some View {
        Menu {
            if center.isMine(item) {
                Button(L("Paylaşımı Geri Al")) { center.withdraw(item) }
                Divider()
            }
            Button(L("Bildir: Zararlı ya da Tehlikeli")) { center.report(item, reason: "unsafe") }
            Button(L("Bildir: Gizli Bilgi İçeriyor")) { center.report(item, reason: "secret") }
            Button(L("Bildir: Reklam ya da Anlamsız")) { center.report(item, reason: "spam") }
            Button(L("Bildir: Çalışmıyor")) { center.report(item, reason: "broken") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Diğer"))
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

/// The blanks of a prompt, filled in before it starts a session.
private struct VariablesSheet: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let item: LibraryEntry
    let variables: [PromptVariables.Variable]
    @Binding var values: [String: String]
    let done: (Bool) -> Void

    var body: some View {
        let palette = Theme.palette
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: item.title(turkish: Loc.isTurkish)).font(.system(size: 17, weight: .semibold)).foregroundColor(Color(palette.text1))
            Dim("Bu istemde doldurulacak yerler var. Boş bıraktığınız varsayılanını alır.")
            ForEach(variables, id: \.self) { variable in
                VStack(alignment: .leading, spacing: 4) {
                    T(variable.name, style: .secondary, weight: .semibold)
                    EntermField(placeholder: variable.fallback.isEmpty ? L("Değer") : variable.fallback,
                                text: Binding(get: { values[variable.name] ?? "" }, set: { values[variable.name] = $0 }))
                }
            }
            HStack {
                Spacer()
                Btn("Vazgeç", kind: .plain, key: "Esc") { done(false) }
                Btn("Çalıştır", kind: .primary, key: "⏎") { done(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Color(palette.surface1))
    }
}

/// Sharing a prompt or race task: it goes to the community shelf at once, after the server's checks.
private struct LibraryShareSheet: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let tags: [String]
    let close: (LibraryEntry?) -> Void
    @State private var title = ""
    @State private var summary = ""
    @State private var text = ""
    @State private var test = ""
    @State private var kind: LibraryEntry.Kind = .prompt
    @State private var programs: Set<String> = ["claude"]
    @State private var chosenTags: Set<String> = []
    @AppStorage("libraryAuthor") private var author = ""
    @State private var sending = false
    @State private var problem: String?

    private var submission: CommunityLibrary.Submission {
        CommunityLibrary.Submission(kind: kind, title: title, summary: summary, text: text, test: kind == .race ? test : nil,
                                    programs: programs.sorted(), tags: chosenTags.sorted(), author: author,
                                    lang: Loc.isTurkish ? "tr" : "en", device: "")
    }

    var body: some View {
        let palette = Theme.palette
        VStack(alignment: .leading, spacing: 12) {
            Text("İstem Paylaş").font(.system(size: 17, weight: .semibold)).foregroundColor(Color(palette.text1))
            Dim("Otomatik denetimden geçince hemen herkesin Kütüphanesinde ve enterm.enmeraapps.com'da görünür; sonra incelenir. Gizli bilgi, şifre ya da şirkete özel ayrıntı yazmayın. İstediğinizde geri alabilirsiniz.")
                .fixedSize(horizontal: false, vertical: true)
            Seg(options: [(.prompt, "İstem"), (.race, "Yarış Görevi")] as [(LibraryEntry.Kind, String)], value: $kind)
            EntermField(placeholder: "Başlık", text: $title)
            EntermField(placeholder: "Tek cümlelik özet", text: $summary)
            T("İstem metni", style: .secondary, weight: .semibold)
            TextEditor(text: $text)
                .font(Theme.swiftFont(size: 12))
                .frame(height: 160)
                .padding(6)
                .background(Color(palette.terminal))
                .cornerRadius(Theme.cornerControl)
            Dim("Doldurulacak yerler için ${ad} ya da ${ad:varsayılan} yazın; çalıştırırken sorulur.")
            if kind == .race { EntermField(placeholder: "Test komutu (ör. npm test)", text: $test) }
            HStack(spacing: 6) {
                ForEach(["claude", "codex", "gemini", "opencode", "copilot", "cursor"], id: \.self) { program in
                    Btn(ToolKind(rawValue: program)?.title ?? program, kind: programs.contains(program) ? .selected : .plain) {
                        if programs.contains(program) { programs.remove(program) } else { programs.insert(program) }
                    }
                }
            }
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { name in
                            Btn("#\(name)", kind: chosenTags.contains(name) ? .selected : .plain) {
                                if chosenTags.contains(name) { chosenTags.remove(name) } else if chosenTags.count < 4 { chosenTags.insert(name) }
                            }
                        }
                    }
                }
            }
            EntermField(placeholder: "Adınız (isteğe bağlı, herkese görünür)", text: $author)
            if let problem { T(problem, color: palette.err, style: .secondary).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Btn("GitHub'dan Öner", kind: .plain) {
                    if let url = LibraryShare.issueURL(title: title, summary: summary, text: text, kind: kind, programs: programs.sorted(), test: kind == .race ? test : nil) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .help(L("İncelenmiş Kütüphane için GitHub'da bir öneri açar"))
                Spacer()
                if sending { ProgressView().controlSize(.small) }
                Btn("Vazgeç", kind: .plain, key: "Esc") { close(nil) }
                Btn("Paylaş", kind: .primary) { send() }
                    .disabled(sending)
            }
        }
        .padding(20)
        .frame(width: 580)
        .background(Color(palette.surface1))
    }

    private func send() {
        if let local = submission.problem {
            problem = L(local)
            return
        }
        sending = true
        problem = nil
        LibraryCenter.shared.share(submission) { result in
            sending = false
            switch result {
            case .success(let item):
                AppModel.shared.hint = "Paylaşıldı · Herkesin Kütüphanesinde"
                close(item)
            case .failure(let failure):
                problem = failure.text
            }
        }
    }
}
