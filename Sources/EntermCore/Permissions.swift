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
    public var sshRules: [SSHHostRule]

    public init(modes: [PermissionCategory: PermissionMode], rememberedHosts: [String] = [], sshRules: [SSHHostRule] = []) {
        self.modes = modes
        self.rememberedHosts = rememberedHosts
        self.sshRules = sshRules
    }

    public func mode(_ category: PermissionCategory) -> PermissionMode {
        modes[category] ?? .ask
    }

    enum CodingKeys: String, CodingKey { case modes, rememberedHosts, sshRules }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: PermissionMode].self, forKey: .modes)
        var modes: [PermissionCategory: PermissionMode] = [:]
        for (key, value) in raw {
            if let category = PermissionCategory(rawValue: key) { modes[category] = value }
        }
        self.modes = modes
        rememberedHosts = try container.decodeIfPresent([String].self, forKey: .rememberedHosts) ?? []
        sshRules = try container.decodeIfPresent([SSHHostRule].self, forKey: .sshRules) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var raw: [String: PermissionMode] = [:]
        for (key, value) in modes { raw[key.rawValue] = value }
        try container.encode(raw, forKey: .modes)
        try container.encode(rememberedHosts, forKey: .rememberedHosts)
        try container.encode(sshRules, forKey: .sshRules)
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
            return (.ssh, command, SSHCommand.host(in: command))
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
        if category == .ssh { return sshDecision(sessionID: sessionID, host: host) }
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

/// One server on a session's SSH list. A server not on the list cannot be reached.
public struct SSHHostRule: Codable, Equatable, Identifiable {
    public var host: String
    public var label: String
    public var mode: PermissionMode
    public var id: String { host }
    public init(host: String, label: String = "", mode: PermissionMode = .ask) {
        self.host = host
        self.label = label
        self.mode = mode
    }
}

public enum SSHCommand {
    /// The destination of an `ssh`, `scp` or `rsync` command, without the user name.
    public static func host(in command: String) -> String? {
        let words = command.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == ";" || $0 == "|" || $0 == "&" }).map(String.init)
        guard let start = words.firstIndex(where: { ["ssh", "scp", "rsync"].contains($0) }) else { return nil }
        let tool = words[start]
        var index = start + 1
        let valueFlags: Set<String> = ["-p", "-P", "-i", "-l", "-o", "-F", "-J", "-L", "-R", "-D", "-e", "-b", "-c", "-m"]
        while index < words.count {
            let word = words[index]
            if word.hasPrefix("-") {
                index += valueFlags.contains(word) ? 2 : 1
                continue
            }
            if tool == "ssh" { return strip(word) }
            if word.contains(":") { return strip(String(word.split(separator: ":")[0])) }
            index += 1
        }
        return nil
    }

    private static func strip(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return cleaned.split(separator: "@").last.map(String.init) ?? cleaned
    }

    /// Hosts named in an OpenSSH config file. Patterns are skipped, keys are never read.
    public static func hosts(fromConfig text: String) -> [String] {
        text.split(separator: "\n").flatMap { line -> [String] in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
            guard parts.count >= 2, parts[0].lowercased() == "host" else { return [] }
            return parts.dropFirst().filter { !$0.contains("*") && !$0.contains("?") }
        }
    }
}

extension PermissionBook {
    /// SSH follows the card first, then the list. An empty list keeps the card's general mode.
    public func sshDecision(sessionID: String, host: String?) -> PermissionMode {
        let card = self.card(for: sessionID)
        if card.mode(.ssh) == .deny { return .deny }
        guard !card.sshRules.isEmpty else { return card.mode(.ssh) }
        guard let host, let rule = card.sshRules.first(where: { $0.host == host }) else { return .deny }
        return rule.mode
    }
}
