import AppKit
import Combine
import EntermCore
import SwiftUI

// MARK: The race

/// Runs races: opens a worktree and a box per program, watches who is done, keeps the score, merges the winner.
/// Git runs off the main queue; the record lives in `races.json` so a race survives a restart.
final class RaceCenter: ObservableObject {
    static let shared = RaceCenter()
    @Published private(set) var book = RaceBook.load()
    /// The canvas redraws the lanes when the score changes.
    var onChange: (() -> Void)?
    /// Programs that take a first instruction on their command line and stay open to talk.
    static let programs: [ToolKind] = [.claude, .codex, .gemini]

    private var bags = Set<AnyCancellable>()
    private var worked: Set<String> = []
    /// A task and test command handed over by the Library, read once by the race page.
    var prefill: (task: String, test: String, forceTest: Bool)?
    /// The tab the person started a race from, to go back to when it ends.
    private var origin: [String: String] = [:]
    private var timer: Timer?
    private let queue = DispatchQueue(label: "enterm.race", qos: .utility)

    private init() {
        AppModel.shared.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in self?.watch(sessions) }
            .store(in: &bags)
        updateTimer()
    }

    var open: [Race] { book.races.filter { !$0.closed } }
    func race(_ id: String) -> Race? { book.races.first { $0.id == id } }

    /// The lane a box shows, if its session is racing.
    func lane(for sessionID: String) -> (race: Race, entrant: RaceEntrant)? {
        guard let race = book.race(of: sessionID), let entrant = race.entrants.first(where: { $0.sessionID == sessionID }) else { return nil }
        return (race, entrant)
    }

    private func change(_ id: String, _ edit: (inout Race) -> Void) {
        guard let index = book.races.firstIndex(where: { $0.id == id }) else { return }
        edit(&book.races[index])
        book.save()
        onChange?()
        updateTimer()
    }

    // MARK: Start

    /// Checks the folder, opens one worktree and one box per program. Returns what went wrong, if anything.
    func start(task: String, programs: [ToolKind], folder: String, testCommand: String) -> String? {
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return "Görevi yazın." }
        guard programs.count >= 2 else { return "Yarış için en az iki program seçin." }
        let runner = CommandRunner(remote: nil, folder: folder)
        let top = Git.run(["rev-parse", "--show-toplevel"], runner: runner)
        guard top.ok else { return "Bu klasör bir git deposu değil." }
        let root = top.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootRunner = CommandRunner(remote: nil, folder: root)
        let head = Git.run(["rev-parse", "HEAD"], runner: rootRunner)
        guard head.ok else { return "Depoda henüz commit yok. Yarış bir commit'ten başlar." }
        let base = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(Git.run(["branch", "--format=%(refname:short)"], runner: rootRunner).output.split(separator: "\n").map(String.init))
        var race = Race(task: task, root: root, base: base, testCommand: testCommand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : testCommand)
        var names = taken
        for tool in programs {
            let branch = RacePlan.branch(task: task, tool: tool.rawValue, taken: names)
            names.insert(branch)
            let path = RacePlan.folder(root: root, branch: branch)
            let made = Git.run(["worktree", "add", path, "-b", branch, base], runner: rootRunner)
            guard made.ok else {
                remove(race, keepWinner: false)
                return "Worktree açılmadı: \(made.output.prefix(160))"
            }
            race.entrants.append(RaceEntrant(tool: tool.rawValue, title: tool.title, branch: branch, folder: path))
        }
        book.races.append(race)
        book.save()
        let model = AppModel.shared
        model.page = nil
        let group = "Yarış: \(Self.short(task))"
        origin[race.id] = model.activeProject
        let prompt = RacePlan.prompt(task: task)
        for entrant in race.entrants {
            guard let tool = ToolKind(rawValue: entrant.tool) else { continue }
            let arguments = tool == .gemini ? "-i \(NotFoundActions.shellQuote(prompt))" : NotFoundActions.shellQuote(prompt)
            ToolLauncher.start(tool, cwd: entrant.folder, name: entrant.title, extraArguments: arguments, announcesQueue: false) { [weak self] info in
                self?.joined(race: race.id, branch: entrant.branch, session: info, group: group)
            }
        }
        model.hint = "Yarış Başladı · \(race.entrants.count) Ajan Aynı Görevde"
        return nil
    }

    /// A task short enough for a tab, cut between words.
    static func short(_ task: String, limit: Int = 26) -> String {
        guard task.count > limit else { return task }
        let cut = task.prefix(limit)
        let words = cut.split(separator: " ").dropLast()
        return (words.isEmpty ? String(cut) : words.joined(separator: " ")) + "…"
    }

    /// A box opened for the race: the clock starts, the boxes stand together.
    private func joined(race id: String, branch: String, session info: SessionInfo, group name: String) {
        let model = AppModel.shared
        change(id) { race in
            guard let index = race.entrants.firstIndex(where: { $0.branch == branch }) else { return }
            race.entrants[index].sessionID = info.id
            race.entrants[index].startedAt = Date()
        }
        // The race has a tab of its own, so its boxes stand side by side and nothing else is in the way.
        model.state.projects[info.id] = name
        if let existing = model.state.groups.first(where: { $0.name == name }) {
            model.addToGroup(info.id, group: existing.id)
        } else {
            model.addToNewGroup(info.id, name: name)
        }
        if race(id)?.entrants.allSatisfy({ $0.sessionID != nil }) == true {
            // All in: the race's tab, the boxes in a row, every one in view.
            model.switchProject(name)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                model.fitCanvas?()
                // Said last, so it is not replaced by the note about two boxes side by side.
                model.hint = "Yarış Başladı · \(self.race(id)?.entrants.count ?? 0) Ajan Aynı Görevde"
            }
        }
    }

    // MARK: Watching

    /// A box that worked and then went quiet with changes in its folder has crossed the line.
    private func watch(_ sessions: [SessionInfo]) {
        for race in open {
            for entrant in race.entrants where entrant.finishedAt == nil {
                guard let id = entrant.sessionID, let info = sessions.first(where: { $0.id == id }) else { continue }
                if info.status == .running { worked.insert(id); continue }
                if info.status == .idle, worked.contains(id) {
                    measure(race.id, entrant, finishing: true)
                }
            }
        }
    }

    /// Lines while the race runs, a few seconds apart; nothing when no one is racing.
    private func updateTimer() {
        let racing = open.contains { !$0.isFinished }
        if racing, timer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 2
            self.timer = timer
        } else if !racing, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    private func tick() {
        guard AppModel.shared.windowVisible else { return }
        for race in open where !race.isFinished {
            for entrant in race.entrants where entrant.finishedAt == nil { measure(race.id, entrant, finishing: false) }
        }
    }

    /// What the agent changed since the start, new files included.
    private func measure(_ id: String, _ entrant: RaceEntrant, finishing: Bool) {
        guard let base = race(id)?.base else { return }
        queue.async { [weak self] in
            let runner = CommandRunner(remote: nil, folder: entrant.folder)
            // New files count too: marked, not staged, so the diff sees them.
            Git.run(["add", "-A", "--intent-to-add"], runner: runner)
            let stat = DiffStat.parse(Git.run(["diff", "--shortstat", base], runner: runner).output)
            DispatchQueue.main.async {
                guard let self else { return }
                var crossed = false
                self.change(id) { race in
                    guard let index = race.entrants.firstIndex(where: { $0.branch == entrant.branch }) else { return }
                    race.entrants[index].stat = stat
                    if let id = entrant.sessionID, let path = AppModel.shared.sessions.first(where: { $0.id == id })?.transcriptPath {
                        race.entrants[index].transcript = path
                    }
                    // Quiet with nothing changed is a question to the person, not a finish.
                    if finishing, stat.files > 0, race.entrants[index].finishedAt == nil {
                        race.entrants[index].finishedAt = Date()
                        crossed = true
                    }
                }
                if crossed { self.crossed(id, entrant) }
            }
        }
    }

    private func crossed(_ id: String, _ entrant: RaceEntrant) {
        guard let race = race(id) else { return }
        let place = race.place(of: entrant.branch) ?? 0
        AppModel.shared.hint = "\(place). Bitirdi: \(entrant.title)"
        if race.isFinished {
            AppModel.shared.hint = "Yarış Bitti · Sonuçlar Hazır"
            Notifier.shared.post(title: "Yarış Bitti", body: race.task, onlyWhenInactive: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                // The person may be typing in a box; the results wait in the bar if so.
                if AppModel.shared.page == nil, AppModel.shared.overlay == nil { AppModel.shared.page = .race(id) }
            }
        }
    }

    // MARK: Tests

    func test(_ id: String, branch: String? = nil) {
        guard let race = race(id), let command = race.testCommand else { return }
        for entrant in race.entrants where branch == nil || entrant.branch == branch {
            change(id) { race in
                if let index = race.entrants.firstIndex(where: { $0.branch == entrant.branch }) { race.entrants[index].tests = .running }
            }
            queue.async { [weak self] in
                let passed = Self.runTests(command, in: entrant.folder)
                DispatchQueue.main.async {
                    self?.change(id) { race in
                        if let index = race.entrants.firstIndex(where: { $0.branch == entrant.branch }) { race.entrants[index].tests = passed ? .passed : .failed }
                    }
                }
            }
        }
    }

    /// The person's own shell, so the test command finds what the terminal would. Ten minutes at most.
    private static func runTests(_ command: String, in folder: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        process.arguments = ["-lc", "cd \(NotFoundActions.shellQuote(folder)) && \(command)"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 600) { if process.isRunning { kill(pid, SIGKILL) } }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: The end

    /// Commits what the winner left, merges its branch into the repository, then clears every worktree.
    func merge(_ id: String, winner branch: String) -> String? {
        guard let race = race(id), let entrant = race.entrants.first(where: { $0.branch == branch }) else { return "Yarış bulunamadı." }
        let root = CommandRunner(remote: nil, folder: race.root)
        let dirty = Git.run(["status", "--porcelain", "--untracked-files=no"], runner: root)
        guard dirty.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Ana klasörde kaydedilmemiş değişiklikler var. Önce onları commit'leyin ya da saklayın."
        }
        let own = CommandRunner(remote: nil, folder: entrant.folder)
        Git.run(["add", "-A"], runner: own)
        if !Git.run(["diff", "--cached", "--quiet"], runner: own).ok {
            Git.run(["commit", "-m", "\(race.task) (\(entrant.title))"], runner: own)
        }
        let merged = Git.run(["merge", "--no-ff", "-m", "Race: \(race.task) · winner \(entrant.title)", branch], runner: root)
        guard merged.ok else {
            Git.run(["merge", "--abort"], runner: root)
            return "Birleştirilemedi: \(merged.output.prefix(200))"
        }
        change(id) { $0.winner = branch }
        remove(self.race(id) ?? race, keepWinner: true)
        AppModel.shared.hint = "Kazanan Birleştirildi: \(entrant.title)"
        return nil
    }

    /// Ends a race without a winner: every box closes, every worktree and branch goes.
    func drop(_ id: String) {
        guard let race = race(id) else { return }
        remove(race, keepWinner: false)
        AppModel.shared.hint = "Yarış Bırakıldı"
    }

    private func remove(_ race: Race, keepWinner: Bool) {
        let model = AppModel.shared
        let root = CommandRunner(remote: nil, folder: race.root)
        // The boxes leave one after another, losers first, so the end is seen.
        let order = race.entrants.sorted { a, _ in a.branch != race.winner }
        for (offset, entrant) in order.enumerated() {
            let close = {
                if let id = entrant.sessionID, let info = model.sessions.first(where: { $0.id == id }) { model.close(info.number) }
            }
            if Motion.allowed { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(offset), execute: close) } else { close() }
        }
        queue.asyncAfter(deadline: .now() + 0.3 * Double(order.count) + 0.5) {
            for entrant in race.entrants {
                Git.run(["worktree", "remove", "--force", entrant.folder], runner: root)
                Git.run(["branch", keepWinner && entrant.branch == race.winner ? "-d" : "-D", entrant.branch], runner: root)
            }
            Git.run(["worktree", "prune"], runner: root)
        }
        if book.races.contains(where: { $0.id == race.id }) {
            change(race.id) { $0.closed = true }
        }
        model.state.groups.removeAll { $0.name.hasPrefix("Yarış: ") && $0.members.allSatisfy { id in race.entrants.contains { $0.sessionID == id } } }
        model.saveState()
        // Back to where the race was started from, once its boxes are gone.
        let back = origin.removeValue(forKey: race.id) ?? nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(order.count) + 0.3) {
            if let back, model.projectNames.contains(back) { model.switchProject(back) } else if let first = model.projectNames.first { model.switchProject(first) }
        }
    }
}

// MARK: Setup page

struct RaceSetupPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var catalog = ToolCatalog.shared
    @State private var task = ""
    @State private var chosen: Set<ToolKind> = [.claude, .codex]
    @State private var testCommand = ""
    @State private var folder = ""
    @State private var error = ""
    @State private var starting = false

    var body: some View {
        PageFrame(title: "Yarış Başlat") {
            VStack(alignment: .leading, spacing: 16) {
                Dim("Aynı görev, birkaç ajan, her biri kendi worktree'sinde. Bitince yan yana karşılaştırır, kazananı birleştirirsiniz.")
                T("Görev", bold: true)
                EntermField(placeholder: "> Giriş sayfasına şifre sıfırlama ekle", text: $task)
                T("Yarışanlar", bold: true)
                let installed = RaceCenter.programs.filter { !catalog.isMissing($0) }
                if installed.count < 2 {
                    // A race needs two runners: say which are here and where the rest come from.
                    HStack(spacing: 8) {
                        Dim(installed.isEmpty ? "Yarış için en az iki program kurulu olmalı. Şu an hiçbiri kurulu değil." : "Yarış için en az iki program kurulu olmalı. Kurulu olan: \(installed.map(\.title).joined(separator: ", ")).")
                        Spacer(minLength: 0)
                        Btn("Programları Gör", kind: .outline) { model.page = .settings(.programs) }
                    }
                }
                Panel {
                    MenuList {
                        ForEach(RaceCenter.programs, id: \.self) { tool in
                            MenuRow(title: tool.title, note: catalog.note(tool), key: chosen.contains(tool) ? "✓" : "", selected: chosen.contains(tool)) {
                                // A program that is not installed cannot race; its row says so.
                                guard !catalog.isMissing(tool) else { return }
                                if chosen.contains(tool) { chosen.remove(tool) } else { chosen.insert(tool) }
                            }
                            .opacity(catalog.isMissing(tool) ? 0.5 : 1)
                        }
                    }
                }
                T("Test Komutu", bold: true)
                EntermField(placeholder: "Boş bırakılırsa test çalışmaz", text: $testCommand)
                Dim("Klasör: \(model.displayPath(folder))")
                if !error.isEmpty { T(error, color: Theme.palette.err) }
                HStack {
                    Btn("Vazgeç", kind: .plain, key: "Esc") { model.page = nil }
                    Btn("Yarışı Başlat", kind: .primary, key: "⏎") { begin() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(starting)
                    Spacer()
                    Dim("Ana klasörünüz değişmez. Kazananı siz seçersiniz.")
                }
            }
        }
        .onAppear {
            catalog.refresh()
            folder = model.focusedInfo?.cwd ?? NSHomeDirectory()
            let files = Set((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            testCommand = RacePlan.testCommand(files: files) ?? ""
            // From the Library: its task, and its test command when the project has none of its own.
            if let prefill = RaceCenter.shared.prefill {
                task = prefill.task
                if prefill.forceTest || testCommand.isEmpty { testCommand = prefill.test }
                RaceCenter.shared.prefill = nil
            }
            chosen = chosen.filter { !catalog.isMissing($0) }
        }
    }

    private func begin() {
        starting = true
        error = RaceCenter.shared.start(task: task, programs: RaceCenter.programs.filter(chosen.contains), folder: folder, testCommand: testCommand) ?? ""
        starting = false
    }
}

// MARK: Results page

struct RaceResultPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var center = RaceCenter.shared
    @ObservedObject var model = AppModel.shared
    let id: String
    @State private var error = ""
    @State private var appeared = false

    var body: some View {
        PageFrame(title: "Yarış Sonucu", wide: true) {
            if let race = center.race(id) {
                VStack(alignment: .leading, spacing: 16) {
                    T(race.task, bold: true)
                    Dim(race.isFinished ? "Herkes bitirdi. Farklara bakın, testleri çalıştırın, kazananı seçin." : "Yarış sürüyor. Sıra bitiriş sırasıdır.")
                    Panel {
                        ForEach(Array(race.standings.enumerated()), id: \.element.id) { offset, entrant in
                            if offset > 0 { Line() }
                            row(race, entrant, offset: offset)
                        }
                    }
                    Dim("Satır sayısı kaliteyi göstermez; farka ve testlere bakın.")
                    if !error.isEmpty { T(error, color: Theme.palette.err) }
                    HStack(spacing: 8) {
                        Btn("Yarışı Tekrar İzle", kind: .outline, icon: "play.fill") { model.page = .timeline("race:\(id)") }
                        if race.testCommand != nil, !race.closed {
                            Btn("Hepsini Test Et", kind: .outline) { center.test(id) }
                        }
                        Spacer()
                        if !race.closed {
                            Btn("Yarışı Bırak", kind: .plain) {
                                model.confirm(title: "Yarış Bırakılsın mı?", detail: "Bütün kutular kapanır, worktree'ler ve dallar silinir. Ana klasörünüz değişmez.", action: "Yarışı Bırak", danger: true) {
                                    center.drop(id)
                                    model.page = nil
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    if Motion.allowed { withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) { appeared = true } } else { appeared = true }
                }
            } else {
                Dim("Bu yarış artık yok.")
            }
        }
    }

    private func row(_ race: Race, _ entrant: RaceEntrant, offset: Int) -> some View {
        let palette = Theme.palette
        let place = race.place(of: entrant.branch)
        let winner = race.winner == entrant.branch
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(RaceLaneView.medal(place) ?? palette.fill)).frame(width: 30, height: 30)
                Text(verbatim: place.map { "\($0)" } ?? "…").font(.system(size: 13, weight: .bold)).foregroundColor(Color(place == nil ? palette.text2 : palette.btnfg))
            }
            .scaleEffect(appeared ? 1 : 0.2)
            .opacity(appeared ? 1 : 0)
            .animation(Motion.allowed ? .spring(response: 0.45, dampingFraction: 0.6).delay(0.12 * Double(offset)) : nil, value: appeared)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    T(entrant.title, bold: true)
                    if winner { T("Kazanan", color: palette.need, style: .secondary, weight: .semibold) }
                }
                Dim("\(RaceLaneView.clock(entrant.duration)) · \(RaceLaneView.files(entrant.stat.files)) · +\(entrant.stat.insertions) −\(entrant.stat.deletions)")
            }
            Spacer()
            tests(entrant)
            if !race.closed {
                Btn("Farkı Gör", kind: .plain) {
                    if let id = entrant.sessionID, let info = model.sessions.first(where: { $0.id == id }) { model.setFocus(info.number) }
                    model.page = .changes
                }
                if race.testCommand != nil {
                    Btn("Test Et", kind: .plain) { center.test(race.id, branch: entrant.branch) }
                }
                Btn("Kazanan Bu", kind: .primary) {
                    model.confirm(title: "\(entrant.title) Birleştirilsin mi?", detail: "Dalı ana klasöre birleştirilir. Diğer kutular kapanır, bütün worktree'ler silinir.", action: "Birleştir", danger: false) {
                        error = center.merge(race.id, winner: entrant.branch) ?? ""
                    }
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func tests(_ entrant: RaceEntrant) -> some View {
        let palette = Theme.palette
        switch entrant.tests {
        case .running?: T("Test Sürüyor…", color: palette.text2, style: .secondary)
        case .passed?: T("✓ Testler Geçti", color: palette.add, style: .secondary, weight: .semibold)
        case .failed?: T("✗ Testler Kaldı", color: palette.err, style: .secondary, weight: .semibold)
        case nil: EmptyView()
        }
    }
}

// MARK: The lane in a racing box

/// A strip under a racing box's terminal: the time, what changed, and a runner on a track that reaches the flag
/// when the agent is done. It moves when the numbers do, never on its own.
final class RaceLaneView: NSView {
    static let height: CGFloat = 26
    private let label = NSTextField(labelWithString: "")
    private let track = CALayer()
    private let runner = CALayer()
    private let flag = NSTextField(labelWithString: "🏁")
    private let medal = CATextLayer()
    private var shownPlace: Int?
    private var shownProgress: Double = -1
    var raceID: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = Theme.ui(.secondary)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        flag.font = .systemFont(ofSize: 11)
        addSubview(flag)
        layer?.addSublayer(track)
        layer?.addSublayer(runner)
        layer?.addSublayer(medal)
        track.cornerRadius = 1.5
        runner.cornerRadius = 5
        medal.alignmentMode = .center
        medal.fontSize = 10
        medal.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        medal.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        medal.isHidden = true
        toolTip = L("Yarış · Sonuçlar için tıklayın")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        if let raceID { AppModel.shared.page = .race(raceID) }
    }

    static func medal(_ place: Int?) -> NSColor? {
        switch place {
        case 1?: return .hex(0xF4C84A)
        case 2?: return .hex(0xC9D1D6)
        case 3?: return .hex(0xD39A6A)
        case _?: return Theme.palette.text3
        case nil: return nil
        }
    }

    /// "3 dosya"; English counts one apart.
    static func files(_ count: Int) -> String {
        Loc.isTurkish ? "\(count) dosya" : (count == 1 ? "1 file" : "\(count) files")
    }

    static func clock(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "–" }
        let total = Int(seconds)
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }

    func show(_ race: Race, _ entrant: RaceEntrant) {
        let palette = Theme.palette
        raceID = race.id
        let place = race.place(of: entrant.branch)
        label.stringValue = "\(Self.clock(entrant.duration)) · \(Self.files(entrant.stat.files)) · +\(entrant.stat.insertions) −\(entrant.stat.deletions)"
        label.textColor = palette.text2
        label.sizeToFit()
        label.frame = NSRect(x: 8, y: (Self.height - label.frame.height) / 2, width: min(label.frame.width, bounds.width * 0.5), height: label.frame.height)
        let start = label.frame.maxX + 12
        let end = bounds.width - 30
        flag.sizeToFit()
        flag.frame.origin = NSPoint(x: end + 6, y: (Self.height - flag.frame.height) / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.backgroundColor = palette.hair2.cgColor
        track.frame = CGRect(x: start, y: Self.height / 2 - 1.5, width: max(0, end - start), height: 3)
        runner.backgroundColor = (Self.medal(place) ?? palette.need).cgColor
        runner.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        CATransaction.commit()
        let progress = race.progress(of: entrant.branch)
        let target = CGPoint(x: start + CGFloat(progress) * max(0, end - start), y: Self.height / 2)
        if progress != shownProgress {
            if Motion.allowed, shownProgress >= 0 {
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = runner.presentation()?.position ?? runner.position
                move.toValue = target
                move.duration = 0.7
                move.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                runner.add(move, forKey: "move")
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            runner.position = target
            CATransaction.commit()
            shownProgress = progress
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            runner.position = target
            CATransaction.commit()
        }
        if place != shownPlace {
            shownPlace = place
            showMedal(place, at: target)
        } else if let place {
            placeMedal(place, at: target)
        }
    }

    private func placeMedal(_ place: Int, at point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        medal.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        medal.position = CGPoint(x: point.x, y: point.y)
        medal.cornerRadius = 9
        medal.backgroundColor = (Self.medal(place) ?? Theme.palette.fill).cgColor
        medal.foregroundColor = Theme.palette.btnfg.cgColor
        medal.string = "\(place)"
        CATransaction.commit()
    }

    /// The finish: the place pops in where the runner stopped, the box lights up once.
    private func showMedal(_ place: Int?, at point: CGPoint) {
        guard let place else { medal.isHidden = true; return }
        placeMedal(place, at: point)
        medal.isHidden = false
        runner.isHidden = true
        guard Motion.allowed else { return }
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.1
        pop.toValue = 1
        pop.damping = 9
        pop.initialVelocity = 6
        pop.duration = pop.settlingDuration
        medal.add(pop, forKey: "pop")
        if let panel = (superview as? SessionBox)?.panel.layer {
            let glow = CABasicAnimation(keyPath: "borderColor")
            glow.fromValue = (Self.medal(place) ?? Theme.palette.need).cgColor
            glow.toValue = panel.borderColor
            glow.duration = 1.6
            glow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.add(glow, forKey: "finish")
            let width = CABasicAnimation(keyPath: "borderWidth")
            width.fromValue = 3
            width.toValue = panel.borderWidth
            width.duration = 1.6
            panel.add(width, forKey: "finishWidth")
        }
    }
}
