import AppKit
import EntermCore
import SwiftUI

// MARK: Flow view

/// The tree of a session's subagents. It only moves while one of them is really running.
struct FlowView: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let info: SessionInfo
    private var running: Bool { info.subagents?.contains { $0.running } ?? false }
    private var animate: Bool {
        running && !PowerCenter.shared.settings.lowPower && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    var body: some View {
        let agents = info.subagents ?? []
        VStack(alignment: .leading, spacing: 8) {
            Panel(border: Theme.palette.fg) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        T("Ana Oturum", bold: true)
                        Spacer()
                        T("\(info.status.symbol) \(info.status.title)")
                    }
                    Dim([info.model, info.effort.map(SessionText.effortTitle)].compactMap { $0 }.joined(separator: " · "))
                    if let tokens = info.contextTokens { Dim("\(SessionText.shortTokens(tokens)) Token") }
                }
                .padding(8)
            }
            if agents.isEmpty {
                Dim("Alt ajan başlamadı. Veri yoksa hareket de yoktur.")
            } else {
                if animate {
                    TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in
                        tree(agents, phase: context.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    tree(agents, phase: nil)
                }
            }
            Dim("Modeli ve tokeni alt ajan başına göstermek yerel kullanım verisi gerektirir, bu sürümde yok.")
        }
    }

    private func tree(_ agents: [SubagentInfo], phase: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(agents) { agent in
                HStack(spacing: 8) {
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height / 2))
                        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        let moving = agent.running ? phase : nil
                        let style = StrokeStyle(lineWidth: 1.5, dash: moving == nil ? [] : [6, 4], dashPhase: CGFloat(-(moving ?? 0) * 24))
                        context.stroke(path, with: .color(Color(agent.running ? Theme.palette.fg : Theme.palette.line2)), style: style)
                    }
                    .frame(width: 32, height: 12)
                    T(agent.type ?? "Alt Ajan")
                    Spacer()
                    Dim(agent.running ? "● Çalışıyor" : "✓ Bitti")
                }
            }
        }
    }
}

// MARK: Limit states

/// Remembers the account a session started on, to offer a way back when its limit opens.
final class LimitWatch {
    static let shared = LimitWatch()
    private var timers: [String: Timer] = [:]
    private(set) var resumedAt: [UInt32: Date] = [:]
    struct Return: Equatable {
        let sessionName: String
        let cwd: String
        let conversation: String?
        let accountID: String?
        let accountName: String
    }
    var pendingReturn: Return?
    var failedResumes = Set<UInt32>()
    var codexWarnings = Set<UInt32>()

    func returnToStart() {
        guard let target = pendingReturn else { return }
        pendingReturn = nil
        if AppModel.shared.overlay == .limitOpened { AppModel.shared.overlay = nil }
        let arguments = target.conversation.map { "--resume \(NotFoundActions.shellQuote($0))" } ?? "--continue"
        ToolLauncher.start(.claude, cwd: target.cwd, name: target.sessionName.isEmpty ? nil : target.sessionName, accountID: target.accountID, extraArguments: arguments)
    }

    func stayHere() {
        pendingReturn = nil
        if AppModel.shared.overlay == .limitOpened { AppModel.shared.overlay = nil }
    }

    func noteSwitch(from info: SessionInfo) {
        let id = info.accountID ?? "system-claude"
        guard let resets = [info.limit?.fiveHour, info.limit?.sevenDay].compactMap({ $0 }).filter({ $0.usedPercent >= 99 }).compactMap(\.resetsAt).max(),
              resets > Date() else { return }
        let target = Return(sessionName: info.name, cwd: info.cwd, conversation: info.transcriptPath ?? info.toolSessionID,
                            accountID: info.accountID, accountName: AccountStore.shared.account(id: id)?.name ?? "Başladığınız Hesap")
        let timer = Timer(fire: resets, interval: 0, repeats: false) { [weak self] _ in
            self?.pendingReturn = target
            AppModel.shared.overlay = .limitOpened
            PhoneBridge.tellPhones(saying: "✓ Başladığınız hesabın limiti açıldı, dönülsün mü?")
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        timers[info.id] = timer
    }

    func noteResume(_ number: UInt32) { resumedAt[number] = Date() }

    /// A resumed conversation that ends within seconds did not open under this account.
    func resumeFailed(_ number: UInt32) -> Bool {
        guard let when = resumedAt.removeValue(forKey: number) else { return false }
        return Date().timeIntervalSince(when) < 25
    }
}

struct LimitOpenedDialog: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var model = AppModel.shared
    var body: some View {
        Panel(border: Theme.palette.add) {
            PanelHeader(title: "Limit Açıldı") { T("✓ Limit Açıldı", color: Theme.palette.add) }
            if let target = LimitWatch.shared.pendingReturn {
                VStack(alignment: .leading, spacing: 12) {
                    T("Başladığınız hesabın limiti açıldı, dönülsün mü?")
                    Dim("Dönülecek: \(target.accountName). Dönüş, hesap değişimi gibi ilk mesajda konuşmayı baştan okur.")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                DialogButtons {
                    Btn("Burada Kalsın", kind: .plain, key: "Esc") { LimitWatch.shared.stayHere() }
                    Btn("\(target.accountName) Hesabına Dön", kind: .primary, key: "⏎") { LimitWatch.shared.returnToStart() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 560)
    }
}

struct ResumeFailedDialog: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let number: UInt32
    @ObservedObject var model = AppModel.shared
    var body: some View {
        Panel(border: Theme.palette.limit) {
            PanelHeader(title: "Konuşma Bu Hesapta Açılmadı") { T("■ Oturum Durdu", color: Theme.palette.limit, bold: true) }
            VStack(alignment: .leading, spacing: 8) {
                Dim("Bu konuşma başka hesapla sürdürülemedi. Çalışan iş kaybolmadı, eski konuşma yerinde duruyor. Programın hatası terminalde görünür.")
                ForEach(Array(LimitActions.resumeOptions(for: number).enumerated()), id: \.offset) { index, action in
                    MenuRow(title: action.title, note: action.note, key: "\(index + 1)") { action.run() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            DialogButtons {
                Btn("Terminale Bak", kind: .plain, key: "Esc") { model.overlay = nil }
            }
        }
        .frame(width: 600)
    }
}

struct CodexLimitDialog: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    let number: UInt32
    @ObservedObject var model = AppModel.shared
    var body: some View {
        Panel(border: Theme.palette.limit) {
            PanelHeader(title: "Limit Dolmuş Olabilir, Kontrol Edin") { T("■ Kontrol Edin", color: Theme.palette.limit, bold: true) }
            VStack(alignment: .leading, spacing: 12) {
                Dim("Codex limit sözü geçen bir hata yazdı, kesin bilgi gelmedi.")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            DialogButtons {
                Btn("Sorun Yok", kind: .plain, key: "Esc") { model.overlay = nil }
                Btn("Terminale Bak", kind: .plain) { model.overlay = nil }
                Btn("Limit Doldu") { model.overlay = .limit(number) }
            }
        }
        .frame(width: 520)
    }
}

// MARK: Scheduler

/// One timer aimed at the next due job. Nothing runs between jobs.
final class Scheduler: ObservableObject {
    static let shared = Scheduler()
    @Published var jobs: [ScheduledJob] = ScheduleBook.load()
    @Published var missed: [ScheduledJob] = []
    private var timer: Timer?

    @Published var pendingTriggers: [(folder: String, trigger: RepoTrigger)] = []
    private var gate = TriggerGate.load()
    private var scanned = Set<String>()

    func start() {
        missed = jobs.filter { $0.missedRun(now: Date()) }
        arm()
    }

    /// Looks for a schedule file in folders that sessions open. A repository's jobs never run until accepted.
    func scan(folders: [String]) {
        var changed = false
        for folder in folders where !scanned.contains(folder) {
            scanned.insert(folder)
            let triggers = RepoTrigger.load(folder: folder)
            guard !triggers.isEmpty else { continue }
            // A job that was accepted before but whose content changed stops here.
            let active = gate.active(triggers, folder: folder).map(\.fingerprint)
            let before = jobs.count
            jobs.removeAll { job in
                job.cwd == folder && job.sourceFingerprint != nil && !active.contains(job.sourceFingerprint ?? "")
            }
            changed = changed || before != jobs.count
            for trigger in gate.pending(triggers, folder: folder) where !pendingTriggers.contains(where: { $0.folder == folder && $0.trigger == trigger }) {
                pendingTriggers.append((folder, trigger))
                AppModel.shared.hint = "◆ Depodan Gelen Tetik: Onay Bekliyor"
            }
        }
        if changed { save() }
    }

    func runOnce(_ item: (folder: String, trigger: RepoTrigger)) {
        var spec = SessionSpec(name: item.trigger.name, tool: .terminal, cwd: item.folder, rows: 30, cols: 100)
        spec.env = ["ENTERM_STARTUP": item.trigger.command]
        AppModel.shared.create(spec)
        pendingTriggers.removeAll { $0.folder == item.folder && $0.trigger == item.trigger }
    }

    func accept(_ item: (folder: String, trigger: RepoTrigger)) {
        gate.accepted[item.folder, default: []].insert(item.trigger.fingerprint)
        gate.save()
        var job = ScheduledJob(name: item.trigger.name, command: item.trigger.command, tool: .terminal, cwd: item.folder, kind: .cron, first: Date())
        job.cron = item.trigger.cron
        job.sourceFingerprint = item.trigger.fingerprint
        jobs.append(job)
        pendingTriggers.removeAll { $0.folder == item.folder && $0.trigger == item.trigger }
        save()
    }

    func reject(_ item: (folder: String, trigger: RepoTrigger)) {
        gate.rejected[item.folder, default: []].insert(item.trigger.fingerprint)
        gate.save()
        pendingTriggers.removeAll { $0.folder == item.folder && $0.trigger == item.trigger }
    }


    func save() {
        ScheduleBook.save(jobs)
        arm()
    }

    private func arm() {
        timer?.invalidate()
        timer = nil
        let now = Date()
        guard let next = jobs.compactMap({ $0.nextRun(after: now) }).min() else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.fireDue() }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fireDue() {
        let now = Date()
        for index in jobs.indices where jobs[index].enabled {
            let reference = jobs[index].lastRun ?? jobs[index].first.addingTimeInterval(jobs[index].kind == .cron ? -120 : -1)
            // Only what is due now. Older runs stay in the missed list until the user answers.
            guard let due = jobs[index].nextRun(after: reference), due <= now, now.timeIntervalSince(due) < 120 else { continue }
            run(index: index)
        }
        save()
    }

    func run(job: ScheduledJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        run(index: index)
        missed.removeAll { $0.id == job.id }
        save()
    }

    private func run(index: Int) {
        let job = jobs[index]
        jobs[index].lastRun = Date()
        if job.tool == .terminal {
            var spec = SessionSpec(name: job.name, tool: .terminal, cwd: job.cwd, rows: 30, cols: 100)
            spec.env = ["ENTERM_STARTUP": job.command]
            AppModel.shared.create(spec)
        } else {
            ToolLauncher.start(job.tool, cwd: job.cwd, name: job.name, extraArguments: NotFoundActions.shellQuote(job.command))
        }
    }
}

struct SchedulerPage: View {
    @ObservedObject private var appearance = AppearanceTick.shared
    @ObservedObject var scheduler = Scheduler.shared
    @ObservedObject var model = AppModel.shared
    @State private var name = ""
    @State private var command = ""
    @State private var tool = ToolKind.terminal
    @State private var kind = ScheduleKind.daily
    @State private var first = Date().addingTimeInterval(3600)
    @State private var minutes = "60"
    @State private var cron = "0 3 * * *"
    var body: some View {
        PageFrame(title: "Zamanlayıcı") {
            if !scheduler.missed.isEmpty {
                T("Kaçan İşler", bold: true)
                ForEach(scheduler.missed) { job in
                    Panel(border: Theme.palette.need) {
                        HStack {
                            VStack(alignment: .leading) {
                                T(job.name, bold: true)
                                Dim("Enterm kapalıyken zamanı geldi. Kendiliğinden çalıştırılmadı.")
                            }
                            Spacer()
                            Btn("Şimdi Çalıştır", kind: .primary) { scheduler.run(job: job) }
                            Btn("Atla", kind: .plain) {
                                if let index = scheduler.jobs.firstIndex(where: { $0.id == job.id }) { scheduler.jobs[index].lastRun = Date() }
                                scheduler.missed.removeAll { $0.id == job.id }
                                scheduler.save()
                            }
                        }
                        .padding(12)
                    }
                }
            }
            ForEach(Array(scheduler.pendingTriggers.enumerated()), id: \.offset) { _, item in
                Panel(border: Theme.palette.need) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            T("Bu Depodaki Zamanlayıcı Çalışmak İstiyor", bold: true)
                            Spacer()
                            StatusBadge(status: .needsApproval)
                        }
                        Dim("\(item.folder)/.enterm/zamanlayici.json")
                        Mono(item.trigger.command).textSelection(.enabled)
                        Dim("\(item.trigger.name) · Cron: \(item.trigger.cron)")
                        Dim("Depodan gelen hiçbir tetik siz onaylamadan çalışmaz. İçerik değişirse yeniden sorulur.")
                        HStack {
                            Btn("Bir Kez Çalıştır") { scheduler.runOnce(item) }
                            Btn("Hep İzin Ver", kind: .primary) { scheduler.accept(item) }
                            Btn("Reddet", kind: .danger) { scheduler.reject(item) }
                        }
                    }
                    .padding(12)
                }
            }
            if scheduler.jobs.isEmpty { Dim("Henüz iş yok.") }
            Panel {
                ForEach(scheduler.jobs) { job in
                    Row {
                        VStack(alignment: .leading) {
                            T(job.name, bold: true)
                            Dim("\(job.tool.title): \(job.command)").lineLimit(1)
                        }
                        Spacer()
                        Dim(describe(job))
                        Btn(job.enabled ? "Durdur" : "Başlat", kind: .plain) {
                            if let index = scheduler.jobs.firstIndex(where: { $0.id == job.id }) { scheduler.jobs[index].enabled.toggle() }
                            scheduler.save()
                        }
                        Btn("Sil", kind: .plain) {
                            scheduler.jobs.removeAll { $0.id == job.id }
                            scheduler.save()
                        }
                    }
                    Line()
                }
            }
            T("Yeni İş", bold: true)
            EntermField(placeholder: "Ad: Gece Testleri", text: $name)
            Seg(options: [(ToolKind.terminal, "Komut"), (ToolKind.claude, "Claude Code"), (ToolKind.codex, "Codex")], value: $tool)
            EntermField(placeholder: tool == .terminal ? "Komut: php artisan test" : "İş: Güncel olmayan paketleri listele", text: $command)
            Seg(options: ScheduleKind.allCases.map { ($0, $0.title) }, value: $kind)
            if kind == .cron {
                EntermField(placeholder: "Dakika Saat Gün Ay Haftanın Günü", text: $cron)
                if CronExpression(cron) == nil { T("Geçersiz Cron", color: Theme.palette.err) }
            }
            HStack {
                if kind != .cron {
                    T(kind == .once ? "Zaman" : "İlk Çalışma")
                    DatePicker("", selection: $first).labelsHidden()
                }
                if kind == .interval {
                    EntermField(placeholder: "Dakika", text: $minutes).frame(width: 90)
                    Dim("Dakikada Bir")
                }
            }
            Dim("Klasör: \(model.displayPath(model.focusedInfo?.cwd ?? NSHomeDirectory())). Yalnız Enterm açıkken çalışır, kapalıyken kaçan iş size sorulur. Güç sınırındaysa ajan işi Sırada bekler.")
            Btn("Ekle", kind: .primary) { add() }
        }
    }
    private func describe(_ job: ScheduledJob) -> String {
        let date = job.nextRun(after: Date())
        let next = date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Bitti"
        let last = job.lastRun.map { " · Son: \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "\(job.kind.title) · \(next)\(last)"
    }
    private func add() {
        guard !command.isEmpty, kind != .cron || CronExpression(cron) != nil else { return }
        var job = ScheduledJob(name: name.isEmpty ? command : name, command: command, tool: tool,
                               cwd: model.focusedInfo?.cwd ?? NSHomeDirectory(), kind: kind, first: kind == .cron ? Date() : first, intervalMinutes: Int(minutes) ?? 60)
        if kind == .cron { job.cron = cron }
        scheduler.jobs.append(job)
        scheduler.save()
        name = ""
        command = ""
    }
}
