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
    public var defaultTemplate = PermissionTemplate.development
    public var voiceEnabled = true
    public var voiceEngine = "system"
    public var voiceLanguage = "tr-TR"
    public var manualModels: [String: ModelPlan] = [:]
    public var defaultPlan = ModelPlan()
    public init() {}
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
