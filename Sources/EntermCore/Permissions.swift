import Foundation

public enum PermissionCategory: String, Codable, CaseIterable, Identifiable {
    case editFiles
    case deleteFiles
    case ssh
    case internet
    case delegate
    case pushDeploy
    case command

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .editFiles: return "Dosya Düzenleme"
        case .deleteFiles: return "Silme"
        case .ssh: return "SSH"
        case .internet: return "İnternet"
        case .delegate: return "Başka Ajana İş Verme"
        case .pushDeploy: return "Push Ve Deploy"
        case .command: return "Komut Çalıştırma"
        }
    }
}

public enum PermissionMode: String, Codable, CaseIterable, Identifiable {
    case allow
    case ask
    case deny

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .allow: return "İzinli"
        case .ask: return "Sorarak"
        case .deny: return "Kapalı"
        }
    }
}

public struct PermissionCard: Codable, Equatable {
    public var modes: [PermissionCategory: PermissionMode]
    public var rememberedHosts: [String]
    public var sshHosts: [String]

    public init(modes: [PermissionCategory: PermissionMode], rememberedHosts: [String] = [], sshHosts: [String] = []) {
        self.modes = modes
        self.rememberedHosts = rememberedHosts
        self.sshHosts = sshHosts
    }

    public func mode(_ category: PermissionCategory) -> PermissionMode {
        modes[category] ?? .ask
    }

    enum CodingKeys: String, CodingKey { case modes, rememberedHosts, sshHosts }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: PermissionMode].self, forKey: .modes)
        var modes: [PermissionCategory: PermissionMode] = [:]
        for (key, value) in raw {
            if let category = PermissionCategory(rawValue: key) { modes[category] = value }
        }
        self.modes = modes
        rememberedHosts = try container.decodeIfPresent([String].self, forKey: .rememberedHosts) ?? []
        sshHosts = try container.decodeIfPresent([String].self, forKey: .sshHosts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var raw: [String: PermissionMode] = [:]
        for (key, value) in modes { raw[key.rawValue] = value }
        try container.encode(raw, forKey: .modes)
        try container.encode(rememberedHosts, forKey: .rememberedHosts)
        try container.encode(sshHosts, forKey: .sshHosts)
    }
}

/// Four ready-made templates. Internet is `ask` in all of them, the rule is single.
public enum PermissionTemplate: String, Codable, CaseIterable, Identifiable {
    case readOnly
    case development
    case manager
    case serverCare

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .readOnly: return "Salt Okuma"
        case .development: return "Geliştirme"
        case .manager: return "Yönetici"
        case .serverCare: return "Sunucu Bakımı"
        }
    }
    public var card: PermissionCard {
        switch self {
        case .readOnly:
            return PermissionCard(modes: [.editFiles: .deny, .deleteFiles: .deny, .ssh: .deny, .internet: .ask,
                                          .delegate: .deny, .pushDeploy: .deny, .command: .ask])
        case .development:
            return PermissionCard(modes: [.editFiles: .allow, .deleteFiles: .ask, .ssh: .deny, .internet: .ask,
                                          .delegate: .allow, .pushDeploy: .deny, .command: .ask])
        case .manager:
            return PermissionCard(modes: [.editFiles: .deny, .deleteFiles: .deny, .ssh: .deny, .internet: .ask,
                                          .delegate: .allow, .pushDeploy: .deny, .command: .ask])
        case .serverCare:
            return PermissionCard(modes: [.editFiles: .ask, .deleteFiles: .ask, .ssh: .ask, .internet: .ask,
                                          .delegate: .deny, .pushDeploy: .ask, .command: .ask])
        }
    }
}

/// Maps a program's tool call to a permission category. Conservative: unknown tools are `.command`.
public enum PermissionClassifier {
    public static func classify(tool: String, input: [String: Any]) -> (category: PermissionCategory, summary: String, host: String?) {
        let name = tool.lowercased()
        if name == "edit" || name == "write" || name == "multiedit" || name == "notebookedit" || name == "apply_patch" {
            let path = input["file_path"] as? String ?? input["path"] as? String ?? ""
            return (.editFiles, path.isEmpty ? tool : "\(tool): \(path)", nil)
        }
        if name == "webfetch" || name == "websearch" {
            let target = input["url"] as? String ?? input["query"] as? String ?? ""
            return (.internet, target.isEmpty ? tool : "\(tool): \(target)", hostOf(target))
        }
        if name == "bash" || name == "shell" || name == "exec_command" || name == "run_command" {
            let command = input["command"] as? String ?? (input["command"] as? [String])?.joined(separator: " ") ?? ""
            return classifyCommand(command)
        }
        let flat = input.keys.sorted().compactMap { key -> String? in
            guard let value = input[key] as? String else { return nil }
            return "\(key): \(value)"
        }.joined(separator: " · ")
        return (.command, flat.isEmpty ? tool : "\(tool): \(flat)", nil)
    }

    public static func classifyCommand(_ command: String) -> (category: PermissionCategory, summary: String, host: String?) {
        let words = command.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == ";" || $0 == "|" || $0 == "&" }).map(String.init)
        if words.contains("ssh") || words.contains("scp") || words.contains("rsync") {
            return (.ssh, command, nil)
        }
        let joined = " " + words.joined(separator: " ") + " "
        if joined.contains(" git push ") || joined.contains(" deploy") || joined.contains(" gh release ")
            || joined.contains(" npm publish ") {
            return (.pushDeploy, command, nil)
        }
        if words.contains("rm") || words.contains("rmdir") || joined.contains(" git clean ")
            || joined.contains(" git reset --hard ") {
            return (.deleteFiles, command, nil)
        }
        if words.contains("curl") || words.contains("wget") {
            let url = words.first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
            return (.internet, command, url.flatMap(hostOf))
        }
        return (.command, command, nil)
    }

    public static func hostOf(_ text: String) -> String? {
        URLComponents(string: text)?.host
    }
}

public struct PermissionBook: Codable {
    /// Keyed by session id. Sessions without an entry use the default template.
    public var cards: [String: PermissionCard]
    public var defaultTemplate: PermissionTemplate
    public var rememberedHosts: [String]

    public init(cards: [String: PermissionCard] = [:], defaultTemplate: PermissionTemplate = .development, rememberedHosts: [String] = []) {
        self.cards = cards
        self.defaultTemplate = defaultTemplate
        self.rememberedHosts = rememberedHosts
    }

    public func card(for sessionID: String) -> PermissionCard {
        cards[sessionID] ?? defaultTemplate.card
    }

    /// The decision for one request. A remembered internet host is allowed for all sessions.
    public func decision(sessionID: String, category: PermissionCategory, host: String?) -> PermissionMode {
        if category == .internet, let host, rememberedHosts.contains(host) { return .allow }
        return card(for: sessionID).mode(category)
    }

    public static func load() -> PermissionBook {
        JSONStore.load(PermissionBook.self, from: EntermPaths.permissionsFile) ?? PermissionBook()
    }
    public func save() {
        JSONStore.save(self, to: EntermPaths.permissionsFile)
    }
}

/// Small JSON files with 0600 permissions, written atomically.
public enum JSONStore {
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
    public static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
