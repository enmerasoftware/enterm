import Foundation

/// A program Enterm can start. Enterm never modifies these programs.
public enum ToolKind: String, Codable, CaseIterable {
    case terminal
    case claude
    case codex
    case antigravity
    case gemini
    case opencode
    case grok
    case copilot
    case cursor
    /// A program the user added: its name and command live in the settings.
    case custom

    public var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        case .gemini: return "Gemini"
        case .opencode: return "opencode"
        case .grok: return "Grok"
        case .copilot: return "GitHub Copilot"
        case .cursor: return "Cursor"
        case .custom: return "Özel Program"
        }
    }
    public var command: String? {
        switch self {
        case .terminal, .custom: return nil
        case .claude: return "claude"
        case .codex: return "codex"
        case .antigravity: return "agy"
        case .gemini: return "gemini"
        case .opencode: return "opencode"
        case .grok: return "grok"
        case .copilot: return "copilot"
        case .cursor: return "cursor-agent"
        }
    }
    /// The official programs, in the order they are offered.
    public static let programs: [ToolKind] = [.claude, .codex, .antigravity, .gemini, .opencode, .grok, .copilot, .cursor]

    /// Tells its state through hooks. The others are read from their output: writing or quiet.
    public var reportsStatus: Bool { self == .claude || self == .codex }

    public static func fromCommand(_ name: String) -> ToolKind? {
        allCases.first { $0.command == name }
    }
}

/// A model's file name as a person would say it: claude-sonnet-5-5 is Sonnet 5.5.
public enum ModelName {
    public static func pretty(_ raw: String) -> String {
        var name = raw
        if let bracket = name.firstIndex(of: "[") { name = String(name[..<bracket]) }
        if name.hasPrefix("claude-") { name = String(name.dropFirst(7)) }
        let parts = name.split(separator: "-").map(String.init)
        guard let first = parts.first, parts.count > 1, parts.dropFirst().allSatisfy({ $0.allSatisfy(\.isNumber) && $0.count < 4 }) else { return raw }
        return first.prefix(1).uppercased() + first.dropFirst() + " " + parts.dropFirst().joined(separator: ".")
    }
}

/// A program the user added, started the way they would start it.
public struct CustomProgram: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var command: String
    public var arguments: String
    public var environment: [String: String]

    public init(id: String = UUID().uuidString, name: String = "", command: String = "", arguments: String = "", environment: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }

    /// What is typed into the shell. The shell's own quoting and variables apply, as they would by hand.
    public var startLine: String {
        arguments.isEmpty ? command : "\(command) \(arguments)"
    }
}

/// What a session is doing. Plain terminals only ever use `running` and `exited`.
public enum SessionStatus: String, Codable {
    case starting
    case running
    case idle
    case needsApproval
    case limitReached
    case failed
    case queued
    case unknown
    case notFound
    case exited

    public var title: String {
        switch self {
        case .starting: return "Başlıyor"
        case .running: return "Çalışıyor"
        case .idle: return "Bekliyor"
        case .needsApproval: return "Onay İstiyor"
        case .limitReached: return "Limit Doldu"
        case .failed: return "Hata"
        case .queued: return "Sırada"
        case .unknown: return "Durum Bilinmiyor"
        case .notFound: return "Bulunamadı"
        case .exited: return "Bitti"
        }
    }
    public var symbol: String {
        switch self {
        case .starting, .idle, .unknown: return "○"
        case .running: return "●"
        case .needsApproval: return "◆"
        case .limitReached: return "■"
        case .failed, .notFound: return "✕"
        case .queued: return "◷"
        case .exited: return "○"
        }
    }
}

/// Whether a program can be started, as the user's shell sees it.
public enum ToolPresence: Equatable {
    case installed
    /// On disk, in a folder the shell does not search.
    case elsewhere(String)
    case missing

    /// Prints one line per program, between markers, so that anything a shell file prints is ignored.
    public static let probeScript = """
    printf '__ENTERM_BEGIN__\\n'; for t in \(ToolKind.programs.compactMap(\.command).joined(separator: " ")); do printf '%s=%s\\n' "$t" "$(command -v "$t")"; done; printf '__ENTERM_END__\\n'
    """

    public static func parse(_ output: String, fileExists: (String) -> Bool) -> [ToolKind: ToolPresence] {
        guard let begin = output.range(of: "__ENTERM_BEGIN__"), let end = output.range(of: "__ENTERM_END__"), begin.upperBound <= end.lowerBound else { return [:] }
        var result: [ToolKind: ToolPresence] = [:]
        for line in output[begin.upperBound..<end.lowerBound].split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let tool = ToolKind.fromCommand(parts[0]) else { continue }
            if !parts[1].isEmpty {
                result[tool] = .installed
            } else if let path = knownLocations(tool).first(where: fileExists) {
                result[tool] = .elsewhere(path)
            } else {
                result[tool] = .missing
            }
        }
        return result
    }

    public static func knownLocations(_ tool: ToolKind) -> [String] {
        guard let command = tool.command else { return [] }
        let home = NSHomeDirectory()
        if tool == .codex { return [home + "/.local/bin/codex", "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"] }
        return [home + "/.local/bin/" + command]
    }

    /// The maker's own install command. Enterm shows it and runs it only when the user asks.
    /// Sources: code.claude.com docs, developers.openai.com/codex, codelabs.developers.google.com/antigravity-cli-hands-on.
    public static func installCommand(_ tool: ToolKind) -> String? {
        switch tool {
        case .terminal, .custom: return nil
        case .claude: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex: return "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
        case .antigravity: return "curl -fsSL https://antigravity.google/cli/install.sh | bash"
        case .gemini: return "npm install -g @google/gemini-cli"
        case .opencode: return "curl -fsSL https://opencode.ai/install | bash"
        case .grok: return "npm install -g @xai-official/grok"
        case .copilot: return "npm install -g @github/copilot"
        case .cursor: return "curl -fsS https://cursor.com/install | bash"
        }
    }
}

/// How a session is called: the name the user gave, otherwise the program.
/// A repeated one gets a number from the second on, in opening order.
public enum SessionLabel {
    public static func names(_ sessions: [SessionInfo]) -> [UInt32: String] {
        var seen: [String: Int] = [:]
        var result: [UInt32: String] = [:]
        for info in sessions.sorted(by: { $0.number < $1.number }) {
            // Two sessions given the same name get told apart the same way.
            let base = !info.name.isEmpty ? info.name : (info.title ?? info.tool.title)
            seen[base, default: 0] += 1
            let count = seen[base] ?? 1
            result[info.number] = count > 1 ? "\(base) \(count)" : base
        }
        return result
    }

    /// In the strip the last folder follows. The home folder adds nothing, nor does a name the user chose.
    public static func stripLabels(_ sessions: [SessionInfo]) -> [UInt32: String] {
        let names = names(sessions)
        var result: [UInt32: String] = [:]
        for info in sessions {
            let name = names[info.number] ?? info.tool.title
            let folder = info.cwd == NSHomeDirectory() ? "" : URL(fileURLWithPath: info.cwd).lastPathComponent
            result[info.number] = !info.name.isEmpty || info.title != nil || folder.isEmpty ? name : "\(name) · \(folder)"
        }
        return result
    }
}

public struct SessionSpec: Codable, Equatable {
    public var name: String?
    public var tool: ToolKind
    public var cwd: String?
    /// Full argv for the program. `nil` starts the login shell.
    public var argv: [String]?
    public var env: [String: String]?
    public var rows: Int
    public var cols: Int
    public var group: String?
    public var accountID: String?
    /// True when a session is started with a tool session to resume.
    public var resumeID: String?

    public init(name: String? = nil, tool: ToolKind = .terminal, cwd: String? = nil, argv: [String]? = nil,
                env: [String: String]? = nil, rows: Int = 24, cols: Int = 80, group: String? = nil,
                accountID: String? = nil, resumeID: String? = nil) {
        self.name = name
        self.tool = tool
        self.cwd = cwd
        self.argv = argv
        self.env = env
        self.rows = rows
        self.cols = cols
        self.group = group
        self.accountID = accountID
        self.resumeID = resumeID
    }
}

public struct SessionInfo: Codable, Equatable, Identifiable {
    public var id: String
    public var number: UInt32
    public var name: String
    public var tool: ToolKind
    public var cwd: String
    public var status: SessionStatus
    public var startedAt: Date
    public var lastEventAt: Date?
    public var group: String?
    public var accountID: String?
    public var pid: Int32?
    public var exitCode: Int32?
    public var toolSessionID: String?
    public var transcriptPath: String?
    public var model: String?
    public var effort: String?
    public var pendingApproval: ApprovalRequest?
    public var limit: LimitSnapshot?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var contextTokens: Int?
    public var contextPercent: Int?
    public var costUSD: Double?
    public var subagents: [SubagentInfo]?
    public var lastActivity: String?
    public var hooksTrusted: Bool?
    /// Why the last turn stopped with an error. Gone once the session moves on.
    public var failure: SessionFailure?
    /// The title the program gave the conversation, shown while the person has not named the box.
    public var title: String?
    /// A Claude Code loop: how often, and when it runs next.
    public var loop: String?
    public var loopNext: Date?
    /// TCP ports the session's programs listen on, such as a development server. Looked up after a turn, never on a timer.
    public var ports: [Int]?

    public init(id: String, number: UInt32, name: String, tool: ToolKind, cwd: String,
                status: SessionStatus, startedAt: Date) {
        self.id = id
        self.number = number
        self.name = name
        self.tool = tool
        self.cwd = cwd
        self.status = status
        self.startedAt = startedAt
    }
}

/// An API error that ended a turn, as Claude Code's StopFailure hook reports it.
public struct SessionFailure: Codable, Equatable {
    public var kind: String
    public var detail: String?

    public init(kind: String, detail: String?) {
        self.kind = kind
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.detail = trimmed.isEmpty ? nil : String(trimmed.prefix(300))
    }

    public var title: String {
        switch kind {
        case "overloaded": return "Sunucu Yoğun"
        case "authentication_failed": return "Giriş Geçersiz"
        case "oauth_org_not_allowed": return "Kuruluş İzin Vermiyor"
        case "account_on_hold": return "Hesap Askıda"
        case "billing_error": return "Ödeme Sorunu"
        case "invalid_request": return "İstek Reddedildi"
        case "model_not_found": return "Model Bulunamadı"
        case "server_error": return "Sunucu Hatası"
        case "max_output_tokens": return "Cevap Sınıra Takıldı"
        case "cloud_credential_error": return "Bulut Kimliği Okunamadı"
        default: return "Bilinmeyen Hata"
        }
    }

    /// What usually helps, in one line.
    public var advice: String {
        switch kind {
        case "overloaded", "server_error": return "Geçici. Biraz sonra aynı mesajı yeniden gönderin."
        case "authentication_failed": return "Oturumda /login ile yeniden giriş yapın."
        case "billing_error", "account_on_hold": return "Hesabın ödeme ve durum sayfasına bakın."
        case "model_not_found": return "/model ile başka bir model seçin."
        case "max_output_tokens": return "\"devam et\" yazarak kaldığı yerden sürdürün."
        default: return "Mesajı yeniden gönderin. Sürerse ayrıntıya bakın."
        }
    }
}

public struct SubagentInfo: Codable, Equatable, Identifiable {
    public var id: String
    public var type: String?
    public var running: Bool
    public var startedAt: Date
    public init(id: String, type: String?, running: Bool, startedAt: Date) {
        self.id = id
        self.type = type
        self.running = running
        self.startedAt = startedAt
    }
}

public struct LimitWindow: Codable, Equatable {
    public var usedPercent: Double
    public var resetsAt: Date?
    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// What the official programs report about their limits. Absent windows stay absent.
public struct LimitSnapshot: Codable, Equatable {
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var seenAt: Date
    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?, seenAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.seenAt = seenAt
    }
}

public struct ApprovalRequest: Codable, Equatable, Identifiable {
    public var id: String
    public var sessionID: String
    public var tool: String
    public var summary: String
    public var category: PermissionCategory
    public var requestedAt: Date
    public init(id: String, sessionID: String, tool: String, summary: String, category: PermissionCategory, requestedAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.tool = tool
        self.summary = summary
        self.category = category
        self.requestedAt = requestedAt
    }
}

/// One thing reported by a hook, a status line or the shell integration.
public struct AgentEvent: Codable, Equatable {
    public var sessionID: String
    public var kind: String
    public var tool: String?
    public var toolSessionID: String?
    public var transcriptPath: String?
    public var model: String?
    public var effort: String?
    public var text: String?
    public var limit: LimitSnapshot?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var contextTokens: Int?
    public var contextPercent: Int?
    public var costUSD: Double?
    public var agentID: String?
    public var agentType: String?
    public var errorKind: String?
    public var title: String?
    public var nextRun: Date?

    public init(sessionID: String, kind: String) {
        self.sessionID = sessionID
        self.kind = kind
    }
}
