import Foundation

public struct AppSettings: Codable, Equatable {
    public var theme = "dark"
    public var newTerminalAsTab = false
    public var openWithLastView = true
    public var fontSize: Double = 13.333
    public var canvasDots = true
    public var flowStartsOpen = false
    public var keepTranscript = true
    public var localUsageData = true
    public var keepAwakeWhileAgents = true
    public var keepAwakeBatteryFloor = 20
    public var systemNotifications = true
    public var defaultTemplate = PermissionTemplate.development
    public var voiceEnabled = true
    public var voiceEngine = "system"
    public var voiceLanguage = "tr-TR"
    public var manualModels: [String: ModelPlan] = [:]
    public var defaultPlan = ModelPlan()
    public init() {}

    // Settings written by an older version keep working: a missing key takes its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? d.theme
        newTerminalAsTab = try c.decodeIfPresent(Bool.self, forKey: .newTerminalAsTab) ?? d.newTerminalAsTab
        openWithLastView = try c.decodeIfPresent(Bool.self, forKey: .openWithLastView) ?? d.openWithLastView
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        canvasDots = try c.decodeIfPresent(Bool.self, forKey: .canvasDots) ?? d.canvasDots
        flowStartsOpen = try c.decodeIfPresent(Bool.self, forKey: .flowStartsOpen) ?? d.flowStartsOpen
        keepTranscript = try c.decodeIfPresent(Bool.self, forKey: .keepTranscript) ?? d.keepTranscript
        localUsageData = try c.decodeIfPresent(Bool.self, forKey: .localUsageData) ?? d.localUsageData
        keepAwakeWhileAgents = try c.decodeIfPresent(Bool.self, forKey: .keepAwakeWhileAgents) ?? d.keepAwakeWhileAgents
        keepAwakeBatteryFloor = try c.decodeIfPresent(Int.self, forKey: .keepAwakeBatteryFloor) ?? d.keepAwakeBatteryFloor
        systemNotifications = try c.decodeIfPresent(Bool.self, forKey: .systemNotifications) ?? d.systemNotifications
        defaultTemplate = try c.decodeIfPresent(PermissionTemplate.self, forKey: .defaultTemplate) ?? d.defaultTemplate
        voiceEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceEnabled) ?? d.voiceEnabled
        voiceEngine = try c.decodeIfPresent(String.self, forKey: .voiceEngine) ?? d.voiceEngine
        voiceLanguage = try c.decodeIfPresent(String.self, forKey: .voiceLanguage) ?? d.voiceLanguage
        manualModels = try c.decodeIfPresent([String: ModelPlan].self, forKey: .manualModels) ?? d.manualModels
        defaultPlan = try c.decodeIfPresent(ModelPlan.self, forKey: .defaultPlan) ?? d.defaultPlan
    }
}

/// Which model does which job. Only Claude Code has an advisor.
public struct ModelPlan: Codable, Equatable {
    public var main = "sonnet"
    public var mainEffort = "high"
    public var plan = "opus"
    public var search = "haiku"
    public var subagents = "haiku"
    public var advisor = "opus"
    public var useAdvisor = false
    public init() {}
}

public struct PowerSettings: Codable, Equatable {
    public var lowPower = false
    public var cpuLimit = 75
    public var sessionsAutomatic = true
    public var maxSessions = 4
    public var memoryLimitGB = 8
    public var scrollbackLines = 10000
    public init() {}
}

public enum AccountKind: String, Codable {
    case system
    case subscription
    case apiKey
}

public struct Account: Codable, Equatable, Identifiable {
    public var id: String
    public var tool: ToolKind
    public var name: String
    public var kind: AccountKind
    /// `CLAUDE_CONFIG_DIR` or `CODEX_HOME`. The official program keeps the login there.
    public var configDir: String?
    public var lastLimit: LimitSnapshot?
    public var monthlyCap: Double?
    public init(id: String, tool: ToolKind, name: String, kind: AccountKind, configDir: String? = nil) {
        self.id = id
        self.tool = tool
        self.name = name
        self.kind = kind
        self.configDir = configDir
    }
}

public enum LinkPermission: String, Codable, CaseIterable, Identifiable {
    case summary
    case delegate
    public var id: String { rawValue }
    public var title: String { self == .summary ? "Özetini Görür" : "İş Verebilir" }
    public var note: String {
        self == .summary ? "Hedefin özetini okur, iş veremez." : "Hedefe görev yazar, hedef kendi yetkisiyle yapar."
    }
}

/// A line drawn between two boxes. A link never grants permissions.
public struct SessionLink: Codable, Equatable, Identifiable {
    public var id: String
    public var from: String
    public var to: String
    public var permission: LinkPermission
    public var bothWays: Bool
    public init(id: String = UUID().uuidString, from: String, to: String, permission: LinkPermission, bothWays: Bool) {
        self.id = id
        self.from = from
        self.to = to
        self.permission = permission
        self.bothWays = bothWays
    }
    public func allows(from source: String, to target: String, need: LinkPermission) -> Bool {
        let direct = from == source && to == target
        let reverse = bothWays && from == target && to == source
        guard direct || reverse else { return false }
        return need == .summary || permission == .delegate
    }
}

public struct AgentMail: Codable, Equatable, Identifiable {
    public var id: String
    public var from: String
    public var fromName: String
    public var to: String
    public var toName: String
    public var kind: String
    public var text: String
    public var at: Date
    public var claimedApproval: Bool
    public init(from: String, fromName: String, to: String, toName: String, kind: String, text: String, at: Date = Date()) {
        id = UUID().uuidString
        self.from = from
        self.fromName = fromName
        self.to = to
        self.toName = toName
        self.kind = kind
        self.text = text
        self.at = at
        claimedApproval = AgentMail.claimsApproval(text)
    }
    /// An agent saying "the user approved" is recorded as a claim and never treated as an approval.
    public static func claimsApproval(_ text: String) -> Bool {
        let lower = text.lowercased(with: Locale(identifier: "tr_TR"))
        return ["kullanıcı onayladı", "onay verildi", "onayladı,", "user approved", "sinan onayladı"].contains { lower.contains($0) }
    }
}

public enum BoardColumn: String, Codable, CaseIterable, Identifiable {
    case todo, doing, review, decision, done
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .todo: return "Yapılacak"
        case .doing: return "Sürüyor"
        case .review: return "Kontrolde"
        case .decision: return "Karar Bekliyor"
        case .done: return "Bitti"
        }
    }
}

public struct CardComment: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var author: String
    public var isAgent: Bool
    public var text: String
    public var at = Date()
    public init(author: String, isAgent: Bool, text: String) {
        self.author = author
        self.isAgent = isAgent
        self.text = text
    }
}

public struct AgentReport: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var author: String
    public var changed: String
    public var tried: String
    public var notTried: String
    public var waiting: String
    public var at = Date()
    public var file: String?
    public init(author: String, changed: String, tried: String, notTried: String, waiting: String) {
        self.author = author
        self.changed = changed
        self.tried = tried
        self.notTried = notTried
        self.waiting = waiting
    }
}

public struct BoardCard: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var title: String
    public var details = ""
    public var column = BoardColumn.todo
    public var members: [String] = []
    public var sessionID: String?
    public var due: Date?
    public var priority = 0
    public var comments: [CardComment] = []
    public var report: AgentReport?
    public init(title: String) { self.title = title }
}

public struct Board: Codable, Equatable {
    public var cards: [BoardCard] = []
    public init() {}
    public mutating func applyReport(sessionID: String, report: AgentReport) {
        guard let index = cards.firstIndex(where: { $0.sessionID == sessionID && $0.column != .done }) else { return }
        cards[index].report = report
        // A report never finishes a card. Only the user moves it to done.
        cards[index].column = .review
    }
    public static func load() -> Board { JSONStore.load(Board.self, from: EntermPaths.boardFile) ?? Board() }
    public func save() { JSONStore.save(self, to: EntermPaths.boardFile) }
}

public struct TeamMember: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var name: String
    public var role: String
    public var tool: ToolKind
    public var model: String
    public var effort: String
    public var template: PermissionTemplate
    public var sources: String
    public var sessionID: String?
    public init(name: String, role: String, tool: ToolKind = .claude, model: String = "sonnet", effort: String = "medium",
                template: PermissionTemplate = .development, sources: String = "CLAUDE.md, README.md") {
        self.name = name
        self.role = role
        self.tool = tool
        self.model = model
        self.effort = effort
        self.template = template
        self.sources = sources
    }
}

public struct Team: Codable, Equatable {
    public var name = ""
    public var folder = ""
    public var brief = ""
    public var members: [TeamMember] = []
    public var managerID: String?
    public var reports: [AgentReport] = []
    public init() {}
    public static func load() -> Team? { JSONStore.load(Team.self, from: EntermPaths.teamFile) }
    public func save() { JSONStore.save(self, to: EntermPaths.teamFile) }

    public static func template(_ key: String) -> [TeamMember] {
        switch key {
        case "software":
            return [TeamMember(name: "Deniz", role: "Yönetici", template: .manager, sources: "ekip/EL-KITABI.md, README.md"),
                    TeamMember(name: "Arda", role: "Yazılım"),
                    TeamMember(name: "Selin", role: "Test", tool: .codex, model: "gpt-5-codex", sources: "tests/, README.md"),
                    TeamMember(name: "Zeynep", role: "Kod İnceleme", model: "haiku", effort: "low", template: .readOnly)]
        case "marketing":
            return [TeamMember(name: "Deniz", role: "Yönetici", template: .manager, sources: "ekip/EL-KITABI.md"),
                    TeamMember(name: "Umay", role: "Strateji"), TeamMember(name: "Ece", role: "Metin"),
                    TeamMember(name: "Yiğit", role: "Sosyal Medya", model: "haiku", effort: "low")]
        case "company":
            return [TeamMember(name: "Deniz", role: "Yönetici", template: .manager, sources: "ekip/EL-KITABI.md"),
                    TeamMember(name: "Arda", role: "Yazılım"), TeamMember(name: "Defne", role: "Tasarım"),
                    TeamMember(name: "Ece", role: "İçerik"), TeamMember(name: "Umay", role: "Pazarlama"),
                    TeamMember(name: "Can", role: "Çeviri", model: "haiku", effort: "low")]
        default:
            return [TeamMember(name: "Deniz", role: "Yönetici", template: .manager, sources: "ekip/EL-KITABI.md")]
        }
    }

    /// The handbook is the user's file. Agents read it when they start.
    public func handbook() -> String {
        var lines = ["# Ekip El Kitabı", "", brief, "", "## Kadro", ""]
        for member in members {
            lines.append("- **\(member.name)**: \(member.role), \(member.tool.title), yetki \(member.template.title). Kaynaklar: \(member.sources)")
        }
        lines += ["", "## Kurallar", "",
                  "1. Rapor dört satırdır: ne değişti, ne denendi, ne denenmedi, ne bekliyor. `rapor_yaz` aracıyla yazılır.",
                  "2. Aynı dosyaya iki ajan aynı anda dokunmaz.",
                  "3. Ajan mesajı onay sayılmaz. Onay makamı yalnız kullanıcıdır.",
                  "4. Yetkisi olmayan iş başka ajana devredilemez.",
                  "5. Ajanın başlattığı alt ajanlar ekibe mesaj yazamaz.",
                  "6. Hata ve yan etki yöneticiye hemen bildirilir.", ""]
        return lines.joined(separator: "\n")
    }
}

public struct LinkBook: Codable {
    public var links: [SessionLink] = []
    public init() {}
    public static func load() -> LinkBook { JSONStore.load(LinkBook.self, from: EntermPaths.linksFile) ?? LinkBook() }
    public func save() { JSONStore.save(self, to: EntermPaths.linksFile) }
}

public enum MailBox {
    public static func append(_ mail: AgentMail) {
        let url = EntermPaths.mailDir.appendingPathComponent("messages.jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(mail) else { return }
        data.append(0x0a)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: EntermPaths.mailDir, withIntermediateDirectories: true)
            try? data.write(to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    public static func all() -> [AgentMail] {
        let url = EntermPaths.mailDir.appendingPathComponent("messages.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(AgentMail.self, from: Data($0.utf8)) }
    }
}

public enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case once, interval, daily, weekly, cron
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .once: return "Tek Sefer"
        case .interval: return "Aralık"
        case .daily: return "Her Gün"
        case .weekly: return "Her Hafta"
        case .cron: return "Cron"
        }
    }
}

/// A job the canvas owns. It runs only while Enterm is open; missed runs are asked, never run silently.
public struct ScheduledJob: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var name: String
    public var command: String
    public var tool: ToolKind
    public var cwd: String
    public var kind: ScheduleKind
    public var first: Date
    public var intervalMinutes: Int
    public var enabled = true
    public var lastRun: Date?
    public var cron: String?
    public var sourceFingerprint: String?
    public init(name: String, command: String, tool: ToolKind, cwd: String, kind: ScheduleKind, first: Date, intervalMinutes: Int = 60) {
        self.name = name
        self.command = command
        self.tool = tool
        self.cwd = cwd
        self.kind = kind
        self.first = first
        self.intervalMinutes = intervalMinutes
    }

    /// The first run time after `date`, or nil when the job is finished.
    public func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        if kind == .cron {
            return cron.flatMap { CronExpression($0) }?.next(after: max(date, first), calendar: calendar)
        }
        if first > date { return first }
        switch kind {
        case .cron:
            return nil
        case .once:
            return nil
        case .interval:
            let step = TimeInterval(max(intervalMinutes, 1) * 60)
            let passed = (date.timeIntervalSince(first) / step).rounded(.down) + 1
            return first.addingTimeInterval(passed * step)
        case .daily, .weekly:
            let days = kind == .daily ? 1 : 7
            var candidate = first
            let total = calendar.dateComponents([.day], from: first, to: date).day ?? 0
            let jumps = total / days
            candidate = calendar.date(byAdding: .day, value: jumps * days, to: first) ?? first
            while candidate <= date {
                candidate = calendar.date(byAdding: .day, value: days, to: candidate) ?? date.addingTimeInterval(86400)
            }
            return candidate
        }
    }

    /// True when a run fell between the last run and now.
    public func missedRun(now: Date) -> Bool {
        guard enabled else { return false }
        if kind == .once { return first <= now && lastRun == nil }
        let start = lastRun ?? first
        guard start <= now else { return false }
        if lastRun == nil { return first <= now }
        guard let due = nextRun(after: start) else { return false }
        return due <= now
    }
}

public enum ScheduleBook {
    public static var file: URL { EntermPaths.support.appendingPathComponent("schedule.json") }
    public static func load() -> [ScheduledJob] { JSONStore.load([ScheduledJob].self, from: file) ?? [] }
    public static func save(_ jobs: [ScheduledJob]) { JSONStore.save(jobs, to: file) }
}

/// Standard five field cron: minute hour day month weekday. Supports `*`, lists, ranges and steps.
public struct CronExpression: Equatable {
    let fields: [Set<Int>]

    public init?(_ text: String) {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count == 5 else { return nil }
        let ranges = [0...59, 0...23, 1...31, 1...12, 0...7]
        var parsed: [Set<Int>] = []
        for (part, range) in zip(parts, ranges) {
            guard let set = Self.parse(part, range: range) else { return nil }
            parsed.append(set)
        }
        // 7 means Sunday as well as 0.
        if parsed[4].contains(7) { parsed[4].insert(0) }
        fields = parsed
    }

    private static func parse(_ text: String, range: ClosedRange<Int>) -> Set<Int>? {
        var result = Set<Int>()
        for item in text.split(separator: ",", omittingEmptySubsequences: false) {
            let pieces = item.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard pieces.count <= 2 else { return nil }
            let step = pieces.count == 2 ? Int(pieces[1]) : 1
            guard let step, step > 0 else { return nil }
            var low: Int
            var high: Int
            if pieces[0] == "*" {
                low = range.lowerBound
                high = range.upperBound
            } else if pieces[0].contains("-") {
                let ends = pieces[0].split(separator: "-").compactMap { Int($0) }
                guard ends.count == 2 else { return nil }
                low = ends[0]
                high = ends[1]
            } else {
                guard let value = Int(pieces[0]) else { return nil }
                low = value
                high = pieces.count == 2 ? range.upperBound : value
            }
            guard range.contains(low), range.contains(high), low <= high else { return nil }
            result.formUnion(Swift.stride(from: low, through: high, by: step))
        }
        return result
    }

    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        var start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        start.second = 0
        guard var candidate = calendar.date(from: start) else { return nil }
        for _ in 0..<(366 * 24 * 60) {
            candidate = candidate.addingTimeInterval(60)
            let c = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: candidate)
            if fields[0].contains(c.minute!), fields[1].contains(c.hour!), fields[2].contains(c.day!), fields[3].contains(c.month!),
               fields[4].contains(c.weekday! - 1) {
                return candidate
            }
        }
        return nil
    }
}

/// A schedule that came with a repository. Its content is untrusted until the user accepts this exact content.
public struct RepoTrigger: Codable, Equatable, Identifiable {
    public var name: String
    public var command: String
    public var cron: String
    public var id: String { name + "|" + command + "|" + cron }

    public var fingerprint: String {
        // FNV-1a: identifies content, it is not a security boundary on its own.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    public static func load(folder: String) -> [RepoTrigger] {
        let url = URL(fileURLWithPath: folder).appendingPathComponent(".enterm/zamanlayici.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RepoTrigger].self, from: data)) ?? []
    }
}

public struct TriggerGate: Codable, Equatable {
    public var accepted: [String: Set<String>] = [:]
    public var rejected: [String: Set<String>] = [:]
    public init() {}

    /// Edited content has another fingerprint, so an edit always asks again.
    public func pending(_ triggers: [RepoTrigger], folder: String) -> [RepoTrigger] {
        triggers.filter { !(accepted[folder]?.contains($0.fingerprint) ?? false) && !(rejected[folder]?.contains($0.fingerprint) ?? false) }
    }
    public func active(_ triggers: [RepoTrigger], folder: String) -> [RepoTrigger] {
        triggers.filter { accepted[folder]?.contains($0.fingerprint) ?? false }
    }
    public static var file: URL { EntermPaths.support.appendingPathComponent("triggers.json") }
    public static func load() -> TriggerGate { JSONStore.load(TriggerGate.self, from: file) ?? TriggerGate() }
    public func save() { JSONStore.save(self, to: Self.file) }
}

/// Commands that load the whole machine. Only one of them runs at a time across agents.
public enum HeavyWork {
    private static let patterns = ["xcodebuild", "swift build", "swift test", "npm run build", "npm test", "yarn build", "pnpm build", "php artisan test",
                                   "phpunit", "pest", "pytest", "cargo build", "cargo test", "gradle", "gradlew", "docker build", "ffmpeg", "make -j"]
    public static func matches(_ command: String) -> Bool {
        patterns.contains { command.contains($0) }
    }
}

public struct HeavyEntry: Codable, Equatable, Identifiable {
    public var sessionID: String
    public var name: String
    public var command: String
    public var running: Bool
    public var id: String { sessionID + command }
    public init(sessionID: String, name: String, command: String, running: Bool) {
        self.sessionID = sessionID
        self.name = name
        self.command = command
        self.running = running
    }
}

public struct RunConfig: Equatable, Identifiable {
    public var name: String
    public var command: String
    public var source: String
    public var id: String { source + name }
    public init(name: String, command: String, source: String) {
        self.name = name
        self.command = command
        self.source = source
    }

    /// Reads `.vscode/launch.json` and `package.json` scripts. Nothing runs from here.
    public static func load(folder: String) -> [RunConfig] {
        var result: [RunConfig] = []
        let root = URL(fileURLWithPath: folder)
        if let text = try? String(contentsOf: root.appendingPathComponent(".vscode/launch.json"), encoding: .utf8) {
            result += parseLaunch(text)
        }
        if let data = try? Data(contentsOf: root.appendingPathComponent("package.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = object["scripts"] as? [String: Any] {
            for key in ["dev", "start", "serve", "test", "build"] where scripts[key] != nil {
                result.append(RunConfig(name: key, command: "npm run \(key)", source: "package.json"))
            }
        }
        return result
    }

    public static func parseLaunch(_ text: String) -> [RunConfig] {
        // launch.json allows comments and trailing commas.
        var cleaned = ""
        var inString = false
        var escaped = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                cleaned.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
                cleaned.append(c)
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            } else {
                cleaned.append(c)
            }
            i += 1
        }
        cleaned = cleaned.replacingOccurrences(of: ",\\s*([}\\]])", with: "$1", options: .regularExpression)
        guard let object = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any],
              let configurations = object["configurations"] as? [[String: Any]] else { return [] }
        return configurations.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            var words: [String] = []
            if let command = item["command"] as? String {
                words = [command]
            } else if let runtime = item["runtimeExecutable"] as? String {
                words = [runtime] + ((item["runtimeArgs"] as? [String]) ?? [])
            } else if let program = item["program"] as? String {
                words = [program.replacingOccurrences(of: "${workspaceFolder}/", with: "")] + ((item["args"] as? [String]) ?? [])
            }
            guard !words.isEmpty else { return nil }
            return RunConfig(name: name, command: words.joined(separator: " "), source: "launch.json")
        }
    }
}
