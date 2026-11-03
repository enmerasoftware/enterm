import Foundation

/// A program Enterm can start. Enterm never modifies these programs.
public enum ToolKind: String, Codable, CaseIterable {
    case terminal
    case claude
    case codex
    case antigravity

    public var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        }
    }
    public var command: String? {
        switch self {
        case .terminal: return nil
        case .claude: return "claude"
        case .codex: return "codex"
        case .antigravity: return "agy"
        }
    }
    public static func fromCommand(_ name: String) -> ToolKind? {
        allCases.first { $0.command == name }
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
        case .exited: return "Bitti"
        }
    }
    public var symbol: String {
        switch self {
        case .starting, .idle, .unknown: return "○"
        case .running: return "●"
        case .needsApproval: return "◆"
        case .limitReached: return "■"
        case .failed: return "✕"
        case .queued: return "◷"
        case .exited: return "○"
        }
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
    public var costUSD: Double?
    public var subagents: [SubagentInfo]?
    public var lastActivity: String?
    public var hooksTrusted: Bool?

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
    public var costUSD: Double?
    public var agentID: String?
    public var agentType: String?
    public var errorKind: String?

    public init(sessionID: String, kind: String) {
        self.sessionID = sessionID
        self.kind = kind
    }
}
