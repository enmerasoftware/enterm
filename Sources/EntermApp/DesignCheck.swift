import AppKit
import EntermCore
import SwiftUI

// Design check: ai-design-check (github.com/enmerasoftware/ai-design-check) run on the project in front of the person.
// Always its latest release through npx, so the rules improve without an Enterm update. Nothing is changed in the
// project unless the person presses a button that says so.

struct DesignFinding: Decodable, Identifiable, Hashable {
    let rule: String
    let area: String?
    let severity: String
    let path: String?
    let line: Int?
    let value: String?
    let message: String
    var id: String { "\(path ?? "")#\(line ?? 0)#\(rule)#\(value ?? "")" }
}

struct DesignReport: Decodable {
    let findings: [DesignFinding]
    let errors: Int?
    let warnings: Int?
    let notes: Int?

    var errorCount: Int { errors ?? findings.filter { $0.severity == "error" }.count }
    var warningCount: Int { warnings ?? findings.filter { $0.severity == "warn" }.count }
    var noteCount: Int { notes ?? findings.filter { $0.severity == "info" }.count }
}

final class DesignCenter: ObservableObject {
    static let shared = DesignCenter()
    @Published private(set) var report: DesignReport?
    @Published private(set) var running = false
    @Published private(set) var problem: String?
    /// What `--fix --dry-run` would change, shown before anything is written.
    @Published private(set) var fixPreview: String?
    @Published private(set) var target = ""
    /// What the last run looked at: the project folder, or a running page's address.
    @Published private(set) var scannedURL: String?

    /// The package, pinned to its newest release each time; `--yes` so npx never stops to ask in the background.
    static let package = "@enmera/ai-design-check@latest"
    static let repository = "enmerasoftware/ai-design-check"
    /// The fix skill, added through the Library like any shared pack: its files are shown before they are added.
    static let skillEntry = LibraryEntry(id: "ai-design-check", kind: .skill, title: "AI design check",
                                         summary: "Find and fix what makes an AI-built interface look generated: rules, a checker and a fix skill.",
                                         text: nil, programs: ["claude"], tags: ["design"], author: "enmerasoftware",
                                         titleTR: "AI design check", summaryTR: "Yapay zekâyla yapılmış arayüzü üretilmiş gösteren şeyleri bulup düzeltir: kurallar, denetleyici ve düzeltme becerisi.",
                                         skill: .init(repo: repository, path: "plugin", ref: "main"))

    func check(folder: String) {
        target = folder
        scannedURL = nil
        run(["--json"] + language, in: folder) { [weak self] output, _ in self?.read(output) }
    }

    func scan(url: String, folder: String) {
        target = folder
        scannedURL = url
        run(["scan", url, "--json"] + language, in: folder) { [weak self] output, _ in self?.read(output) }
    }

    func previewFixes(folder: String) {
        run(["--fix", "--dry-run"] + language, in: folder) { [weak self] output, _ in
            self?.fixPreview = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("Mekanik olarak düzeltilecek bir şey yok.") : output
        }
    }

    func applyFixes(folder: String) {
        fixPreview = nil
        run(["--fix"] + language, in: folder) { [weak self] _, _ in
            AppModel.shared.hint = "Mekanik Düzeltmeler Uygulandı"
            self?.check(folder: folder)
        }
    }

    func dismissPreview() { fixPreview = nil }

    private var language: [String] { Loc.isTurkish ? ["--tr"] : [] }

    private func read(_ output: String) {
        // npm may print notices around the JSON; the report is from the first brace to the last.
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end,
              let data = String(output[start...end]).data(using: .utf8),
              let report = try? JSONDecoder().decode(DesignReport.self, from: data) else {
            problem = output.isEmpty ? L("ai-design-check bir sonuç vermedi.") : String(output.suffix(600))
            return
        }
        problem = nil
        self.report = report
    }

    /// The person's own login shell, so npx and node are found as in their terminal. Four minutes at most.
    private func run(_ arguments: [String], in folder: String, then: @escaping (String, Int32) -> Void) {
        guard !running else { return }
        running = true
        problem = nil
        let command = (["npx", "--yes", Self.package] + arguments).map(NotFoundActions.shellQuote).joined(separator: " ")
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
            var environment = ProcessInfo.processInfo.environment
            // No "new npm available" notice in the middle of the report, and no funding lines.
            environment["NPM_CONFIG_UPDATE_NOTIFIER"] = "false"
            environment["NPM_CONFIG_FUND"] = "false"
            process.environment = environment
            process.arguments = ["-lc", "command -v npx >/dev/null || { echo '__NO_NODE__'; exit 127; }; cd \(NotFoundActions.shellQuote(folder)) && \(command)"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            var output = ""
            var status: Int32 = 1
            if (try? process.run()) != nil {
                let pid = process.processIdentifier
                DispatchQueue.global().asyncAfter(deadline: .now() + 240) { if process.isRunning { kill(pid, SIGKILL) } }
                output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                status = process.terminationStatus
            }
            DispatchQueue.main.async {
                self.running = false
                if output.contains("__NO_NODE__") {
                    self.problem = L("ai-design-check için Node.js gerekiyor. Kurmak için terminalde: brew install node")
                    return
                }
                then(output, status)
            }
        }
    }

    /// The task a design race and the fix button give the agents.
    static func fixPrompt(url: String?) -> String {
        var text = """
        Improve the design of this project's interface so it no longer looks AI-generated, without changing features, data or wording.
        Use ai-design-check: run `npx --yes \(package) --json` first and note the counts, fix what has one answer with `npx --yes \(package) --fix`, then repair the rest in order of harm (accessibility, layout, type, colour, copy).
        """
        if let url { text += "\nThe running page is at \(url); check it with `npx --yes \(package) scan \(url)` before and after." }
        text += "\nFinish by running the checker again and reporting the counts before and after. Commit your work when done."
        return text
    }
}

struct DesignCheckPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var center = DesignCenter.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var library = LibraryCenter.shared
    @State private var area: String?
    @State private var showNotes = false

    private var folder: String { model.focusedInfo?.cwd ?? NSHomeDirectory() }
    private var ports: [Int] { model.focusedInfo?.ports ?? [] }

    var body: some View {
        PageFrame(title: "Tasarım Kontrolü", wide: true) {
            VStack(alignment: .leading, spacing: 16) {
                Dim("ai-design-check, yapay zekâyla yapılmış bir arayüzü \"üretilmiş\" gösteren şeyleri bulur: erişilebilirlik, yerleşim, yazı, renk, metin. Web projeleri ile SwiftUI, Jetpack Compose, Flutter ve React Native uygulamalarını okur. Her zaman en son sürümü çalışır; projenizde siz bir düğmeye basmadan hiçbir şey değişmez.")
                    .fixedSize(horizontal: false, vertical: true)
                controls
                if let problem = center.problem {
                    Panel { T(problem, color: Theme.palette.err, style: .secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                }
                if let preview = center.fixPreview { fixPreview(preview) }
                if let report = center.report { summary(report); findings(report) }
                else if !center.running { empty }
            }
        }
        .onAppear { if center.report == nil || center.target != folder { center.check(folder: folder) } }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Btn("Yeniden Kontrol Et", kind: .outline, icon: "arrow.clockwise") { center.check(folder: folder) }
            if let port = ports.first {
                Btn(L("Çalışan Sayfayı Tara (:\(port))"), kind: .plain, icon: "safari") { center.scan(url: "http://localhost:\(port)", folder: folder) }
            }
            Btn("Mekanik Düzeltmeleri Önizle", kind: .plain, icon: "wand.and.stars") { center.previewFixes(folder: folder) }
            Btn("Ajanla Düzelt", kind: .primary, icon: "sparkles") { fixWithAgent() }
            Btn("Tasarım Yarışı", kind: .outline, icon: "flag.checkered") { designRace() }
            Spacer()
            if center.running { ProgressView().controlSize(.small); Dim("Çalışıyor…") }
        }
    }

    private var empty: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                T("Henüz sonuç yok", bold: true)
                Dim(L("Klasör: \(model.displayPath(folder))"))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summary(_ report: DesignReport) -> some View {
        let palette = Theme.palette
        return HStack(spacing: 12) {
            number(report.errorCount, "Hata", palette.err)
            number(report.warningCount, "Uyarı", palette.limit)
            number(report.noteCount, "Not", palette.text2)
            VStack(alignment: .leading, spacing: 4) {
                Dim(center.scannedURL.map { L("Taranan sayfa: \($0)") } ?? L("Klasör: \(model.displayPath(center.target))"))
                if report.errorCount == 0 && report.warningCount == 0 {
                    T("✓ Temiz: bulunacak bir şey kalmadı", color: palette.add, style: .secondary, weight: .semibold)
                }
            }
            Spacer()
        }
    }

    private func number(_ value: Int, _ title: String, _ color: NSColor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(value)").font(.system(size: 26, weight: .semibold)).monospacedDigit().foregroundColor(Color(value == 0 ? Theme.palette.text3 : color))
            T(title, color: Theme.palette.text2, style: .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(Theme.palette.fill))
        .cornerRadius(Theme.cornerControl)
    }

    private func findings(_ report: DesignReport) -> some View {
        let palette = Theme.palette
        let visible = report.findings.filter { (showNotes || $0.severity != "info") && (area == nil || $0.area == area) }
        let areas = Array(Set(report.findings.compactMap(\.area))).sorted()
        let files = Dictionary(grouping: visible) { $0.path ?? "" }.sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Seg(options: [(nil, "Tümü")] + areas.map { (Optional($0), Self.areaTitle($0)) } as [(String?, String)], value: $area)
                Btn(showNotes ? "Notlar ✓" : "Notlar", kind: showNotes ? .selected : .plain) { showNotes.toggle() }
                Spacer()
                Dim(L("\(visible.count) bulgu"))
            }
            Panel {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(files, id: \.key) { file, items in
                            Button { if !file.isEmpty { model.page = .editor(absolute(file)) } } label: {
                                HStack {
                                    Symbol("doc.text", color: palette.text2, size: 12)
                                    Text(verbatim: file.isEmpty ? L("Sayfa") : file).font(Theme.swiftFont(size: 12)).foregroundColor(Color(palette.text1))
                                    Spacer()
                                    Dim("\(items.count)")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(palette.fill))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            ForEach(items) { finding in row(finding) }
                        }
                    }
                }
                .frame(minHeight: 280, maxHeight: 520)
            }
        }
    }

    private func row(_ finding: DesignFinding) -> some View {
        let palette = Theme.palette
        let color = finding.severity == "error" ? palette.err : (finding.severity == "warn" ? palette.limit : palette.text3)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(Color(color)).frame(width: 7, height: 7)
            Text(verbatim: finding.line.map { "\($0)" } ?? "–").font(Theme.swiftFont(size: 11)).foregroundColor(Color(palette.text3)).frame(width: 40, alignment: .trailing)
            // The checker writes its own messages, in the language it was asked for.
            Text(verbatim: finding.message).font(.system(size: 12)).foregroundColor(Color(palette.text1)).textSelection(.enabled)
            Spacer(minLength: 8)
            Button { NSWorkspace.shared.open(URL(string: "https://github.com/\(DesignCenter.repository)/blob/main/RULES.md#\(finding.rule)")!) } label: {
                Text(verbatim: finding.rule).font(Theme.swiftFont(size: 11)).foregroundColor(Color(palette.text2))
            }
            .buttonStyle(.plain)
            .help("Kuralın açıklaması")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func fixPreview(_ text: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                T("Mekanik düzeltmeler: önizleme", bold: true)
                Dim("Boşluk ve köşeler ölçeğin en yakın adımına, çok kalın yazı kalına taşınır. Renk, dokunma alanı, metin ve hiyerarşi rapora kalır.")
                ScrollView {
                    Text(verbatim: text).font(Theme.swiftFont(size: 11)).foregroundColor(Color(Theme.palette.text1)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                .frame(maxHeight: 220)
                .background(Color(Theme.palette.terminal))
                .cornerRadius(Theme.cornerControl)
                HStack {
                    Spacer()
                    Btn("Vazgeç", kind: .plain) { center.dismissPreview() }
                    Btn("Uygula", kind: .primary) { center.applyFixes(folder: folder) }
                }
            }
            .padding(16)
        }
    }

    /// The checker's areas by name; one it adds later shows as it writes it.
    static func areaTitle(_ area: String) -> String {
        let names = ["accessibility": "Erişilebilirlik", "components": "Bileşenler", "copy": "Metin", "data": "Veri",
                     "layout": "Yerleşim", "motion": "Hareket", "shape": "Biçim", "type": "Yazı", "visual": "Görsel Dil",
                     "writing": "Yazım", "localisation": "Yerelleştirme", "localization": "Yerelleştirme", "phone": "Telefon",
                     "navigation": "Gezinme", "selectors": "Seçiciler", "style": "Stil"]
        return names[area] ?? area
    }

    private func absolute(_ path: String) -> String {
        path.hasPrefix("/") ? path : (center.target as NSString).appendingPathComponent(path)
    }

    /// A new session in this folder, told to fix the design with the checker, with the fix skill when it is added.
    private func fixWithAgent() {
        let prompt = DesignCenter.fixPrompt(url: center.scannedURL)
        let tool: ToolKind = ToolCatalog.shared.isMissing(.claude) ? .codex : .claude
        model.page = nil
        ToolLauncher.start(tool, cwd: folder, name: L("Tasarım"), extraArguments: NotFoundActions.shellQuote(prompt))
    }

    /// Several agents fix the design side by side; the checker itself is the test that tells who got it clean.
    private func designRace() {
        RaceCenter.shared.prefill = (DesignCenter.fixPrompt(url: center.scannedURL), "npx --yes \(DesignCenter.package)", true)
        model.page = .raceSetup
    }
}
