import Foundation

/// A question the phone asks the window on the Mac. Accounts, links and Git live there,
/// so the phone uses the same code the Mac's own screens use.
public struct PhoneCall: Codable {
    public var name: String
    public var number: UInt32?
    public var args: [String: String]

    public init(_ name: String, number: UInt32? = nil, args: [String: String] = [:]) {
        self.name = name
        self.number = number
        self.args = args
    }
}

public struct PhoneAccount: Codable, Identifiable, Equatable {
    public var id: String
    public var tool: ToolKind
    public var name: String
    public var isAPIKey: Bool
    public var sessions: Int
    public var limit: LimitSnapshot?

    public init(id: String, tool: ToolKind, name: String, isAPIKey: Bool, sessions: Int, limit: LimitSnapshot?) {
        self.id = id
        self.tool = tool
        self.name = name
        self.isAPIKey = isAPIKey
        self.sessions = sessions
        self.limit = limit
    }
}

public struct PhoneOptions: Codable, Equatable {
    public var accounts: [PhoneAccount]
    public var folders: [String]
    public var notes: [String: String]
    public var plan: ModelPlan

    public init(accounts: [PhoneAccount], folders: [String], notes: [String: String], plan: ModelPlan) {
        self.accounts = accounts
        self.folders = folders
        self.notes = notes
        self.plan = plan
    }
}

/// What starting something led to.
public struct PhoneStart: Codable, Equatable {
    public var number: UInt32?
    public var queued: Bool
    /// The program is not on the Mac: the command that installs it, to show before anything runs.
    public var missingTool: ToolKind?

    public init(number: UInt32? = nil, queued: Bool = false, missingTool: ToolKind? = nil) {
        self.number = number
        self.queued = queued
        self.missingTool = missingTool
    }
}

/// The card shown when a program is not found.
public struct PhoneFoundCard: Codable, Equatable {
    public var title: String
    public var command: String
    public var note: String
    public var button: String

    public init(title: String, command: String, note: String, button: String) {
        self.title = title
        self.command = command
        self.note = note
        self.button = button
    }
}

public struct PhoneChoice: Codable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var note: String

    public init(id: Int, title: String, note: String) {
        self.id = id
        self.title = title
        self.note = note
    }
}

public struct PhoneChangedFile: Codable, Equatable, Identifiable {
    public var path: String
    public var added: Int
    public var removed: Int
    public var isNew: Bool
    public var id: String { path }

    public init(path: String, added: Int, removed: Int, isNew: Bool) {
        self.path = path
        self.added = added
        self.removed = removed
        self.isNew = isNew
    }
}

public struct PhoneChanges: Codable, Equatable {
    public var isRepository: Bool
    public var branch: String
    public var files: [PhoneChangedFile]

    public init(isRepository: Bool, branch: String, files: [PhoneChangedFile]) {
        self.isRepository = isRepository
        self.branch = branch
        self.files = files
    }
}

public struct PhoneBrowser: Codable, Equatable {
    public var isOpen: Bool
    public var address: String
    public var agent: String?
    public var lastStep: String?
    public var userHasControl: Bool
    public var failure: String?
    /// JPEG, small on purpose: a picture a second at most, only while the screen is open.
    public var image: Data?

    public init(isOpen: Bool, address: String, agent: String?, lastStep: String?, userHasControl: Bool, failure: String?, image: Data?) {
        self.isOpen = isOpen
        self.address = address
        self.agent = agent
        self.lastStep = lastStep
        self.userHasControl = userHasControl
        self.failure = failure
        self.image = image
    }
}

public struct PhoneLink: Codable, Equatable, Identifiable {
    public var id: String
    public var fromName: String
    public var toName: String
    public var permission: LinkPermission
    public var bothWays: Bool

    public init(id: String, fromName: String, toName: String, permission: LinkPermission, bothWays: Bool) {
        self.id = id
        self.fromName = fromName
        self.toName = toName
        self.permission = permission
        self.bothWays = bothWays
    }
}

public struct PhonePower: Codable, Equatable {
    public var settings: PowerSettings
    public var effectiveSessions: Int
    public var enterm: String
    public var agents: String

    public init(settings: PowerSettings, effectiveSessions: Int, enterm: String, agents: String) {
        self.settings = settings
        self.effectiveSessions = effectiveSessions
        self.enterm = enterm
        self.agents = agents
    }
}

public struct PhoneNothing: Codable, Equatable {
    public init() {}
}

/// Lifts `~` and turns the whole of a program's usage into a token line per model. Pure, so it can be tested.
public enum PhoneCost {
    public struct Line: Equatable, Identifiable {
        public var id: String { name }
        public var name: String
        public var tokens: Int
    }

    public static func byModel(_ sessions: [SessionInfo]) -> [Line] {
        var totals: [String: Int] = [:]
        for info in sessions where info.tool != .terminal {
            let name = info.model ?? info.tool.title
            totals[name, default: 0] += info.contextTokens ?? 0
        }
        return totals.map { Line(name: $0.key, tokens: $0.value) }.sorted { $0.tokens > $1.tokens }
    }

    public static func short(_ tokens: Int) -> String {
        tokens >= 1000 ? String(format: "%.1fk", Double(tokens) / 1000) : "\(tokens)"
    }
}
