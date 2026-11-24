import Foundation

// The Library: prompts, race tasks and skill packs people share, kept in one public repository
// (enmerasoftware/enterm-library) whose index.json the app reads. Nothing in it runs by itself:
// a prompt is shown before it starts a session, a skill pack's files before they are added.

public struct LibraryEntry: Codable, Equatable, Identifiable, Hashable {
    public enum Kind: String, Codable, CaseIterable {
        case prompt, race, skill
    }

    /// Where a skill pack lives: a folder in Claude Code plugin form inside a GitHub repository.
    public struct SkillSource: Codable, Equatable, Hashable {
        public var repo: String
        public var path: String
        public var ref: String
        public init(repo: String, path: String, ref: String) {
            self.repo = repo
            self.path = path
            self.ref = ref
        }
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var summary: String
    public var titleTR: String?
    public var summaryTR: String?
    /// The prompt itself; nil for a skill pack.
    public var text: String?
    /// A race task's suggested test command.
    public var test: String?
    public var programs: [String]
    public var tags: [String]
    public var author: String
    public var path: String?
    public var skill: SkillSource?
    public var votes: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, title, summary, text, test, programs, tags, author, path, skill, votes
        case titleTR = "title_tr", summaryTR = "summary_tr"
    }

    public init(id: String, kind: Kind, title: String, summary: String, text: String?, programs: [String] = [], tags: [String] = [],
                author: String = "", titleTR: String? = nil, summaryTR: String? = nil, test: String? = nil, path: String? = nil,
                skill: SkillSource? = nil, votes: Int = 0) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.text = text
        self.programs = programs
        self.tags = tags
        self.author = author
        self.titleTR = titleTR
        self.summaryTR = summaryTR
        self.test = test
        self.path = path
        self.skill = skill
        self.votes = votes
    }

    /// A field that is missing or of an unknown kind leaves the item out, never the whole index.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text)
        test = try c.decodeIfPresent(String.self, forKey: .test)
        programs = try c.decodeIfPresent([String].self, forKey: .programs) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        titleTR = try c.decodeIfPresent(String.self, forKey: .titleTR)
        summaryTR = try c.decodeIfPresent(String.self, forKey: .summaryTR)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        skill = try c.decodeIfPresent(SkillSource.self, forKey: .skill)
        votes = try c.decodeIfPresent(Int.self, forKey: .votes) ?? 0
    }

    /// The title and summary in the language on screen.
    public func title(turkish: Bool) -> String { turkish ? (titleTR ?? title) : title }
    public func summary(turkish: Bool) -> String { turkish ? (summaryTR ?? summary) : summary }

    /// Where people read it, or open the files of a skill pack before adding it.
    public var webURL: URL? {
        if let skill { return URL(string: "https://github.com/\(skill.repo)/tree/\(skill.ref)/\(skill.path)") }
        guard let path else { return nil }
        return URL(string: "\(LibraryIndex.repositoryURL)/blob/main/\(path)")
    }
}

public struct LibraryIndex: Codable, Equatable {
    public var version: Int
    public var generated: String?
    public var items: [LibraryEntry]

    public static let repository = "enmerasoftware/enterm-library"
    public static let repositoryURL = "https://github.com/\(repository)"
    public static let indexURL = URL(string: "https://raw.githubusercontent.com/\(repository)/main/index.json")!
    /// The last index read, so the Library opens at once and works offline.
    public static var cacheFile: URL { EntermPaths.support.appendingPathComponent("library.json") }

    public init(version: Int = 1, generated: String? = nil, items: [LibraryEntry] = []) {
        self.version = version
        self.generated = generated
        self.items = items
    }

    /// Items that do not decode are dropped one by one, so a new field or kind never empties the Library.
    public static func parse(_ data: Data) -> LibraryIndex? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let raw = object["items"] as? [Any] ?? []
        let items = raw.compactMap { entry -> LibraryEntry? in
            guard let piece = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? JSONDecoder().decode(LibraryEntry.self, from: piece)
        }
        return LibraryIndex(version: object["version"] as? Int ?? 1, generated: object["generated"] as? String, items: items)
    }

    /// Every word of the search must appear in the title, summary, tags, programs or text, in either language.
    public func filter(query: String, kind: LibraryEntry.Kind? = nil, tag: String? = nil, program: String? = nil, saved: Set<String>? = nil) -> [LibraryEntry] {
        let words = query.lowercased(with: Locale(identifier: "tr_TR")).split(separator: " ").map(String.init)
        return items.filter { item in
            if let kind, item.kind != kind { return false }
            if let tag, !item.tags.contains(tag) { return false }
            if let program, !item.programs.isEmpty, !item.programs.contains(program) { return false }
            if let saved, !saved.contains(item.id) { return false }
            guard !words.isEmpty else { return true }
            let haystack = [item.title, item.summary, item.titleTR ?? "", item.summaryTR ?? "", item.text ?? "",
                            item.tags.joined(separator: " "), item.programs.joined(separator: " "), item.author]
                .joined(separator: " ").lowercased(with: Locale(identifier: "tr_TR"))
            return words.allSatisfy { haystack.contains($0) }
        }
        .sorted { ($0.votes, $1.title) > ($1.votes, $0.title) }
    }

    /// The tags in use, most used first.
    public var tags: [String] {
        var counts: [String: Int] = [:]
        for item in items { for tag in item.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }
}

/// What the person saved from the Library, and the prompts they wrote themselves. Kept on this Mac.
public struct LibraryShelf: Codable, Equatable {
    public var saved: [String] = []
    /// When each skill pack was added, by item id: the Library page says "added" and can remove it.
    public var installedSkills: [String: Date] = [:]

    public init() {}

    public static var file: URL { EntermPaths.support.appendingPathComponent("library-shelf.json") }
    public static func load() -> LibraryShelf { JSONStore.load(LibraryShelf.self, from: file) ?? LibraryShelf() }
    public func save() { JSONStore.save(self, to: Self.file) }

    public mutating func toggle(_ id: String) {
        if let index = saved.firstIndex(of: id) { saved.remove(at: index) } else { saved.insert(id, at: 0) }
    }
}

public enum LibraryShare {
    /// The Library's "submit a prompt" issue form, prefilled: the person reads it on GitHub before sending.
    /// Fields are filled by their ids; GitHub cannot tick checkboxes from a link, so the programs go into "tried".
    public static func issueURL(title: String, summary: String, text: String, kind: LibraryEntry.Kind, programs: [String], test: String? = nil) -> URL? {
        var components = URLComponents(string: "\(LibraryIndex.repositoryURL)/issues/new")
        var items = [
            URLQueryItem(name: "template", value: "submit-prompt.yml"),
            URLQueryItem(name: "title", value: "Prompt: \(title)"),
            URLQueryItem(name: "summary", value: summary),
            URLQueryItem(name: "kind", value: kind == .race ? "race" : "prompt"),
            URLQueryItem(name: "prompt", value: text),
            URLQueryItem(name: "tried", value: programs.isEmpty ? "" : "Works with: \(programs.joined(separator: ", ")). Shared from Enterm."),
        ]
        if let test, !test.isEmpty { items.append(URLQueryItem(name: "test", value: test)) }
        components?.queryItems = items
        return components?.url
    }

    /// The folder name a skill pack gets on this Mac: its id, safe for a path.
    public static func folderName(for item: LibraryEntry) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let name = item.id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(name).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
