import Foundation

// The Library: prompts, race tasks and skill packs people share, kept in one public repository
// (the library/ folder of enmerasoftware/enterm) whose index.json the app reads. Nothing in it runs by itself:
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
    /// Where the item comes from when it is not Enterm's own Library: "community" (or "community-reviewed").
    public var source: String?
    /// Its page there.
    public var link: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, summary, text, test, programs, tags, author, path, skill, votes, source, link
        case titleTR = "title_tr", summaryTR = "summary_tr"
    }

    public init(id: String, kind: Kind, title: String, summary: String, text: String?, programs: [String] = [], tags: [String] = [],
                author: String = "", titleTR: String? = nil, summaryTR: String? = nil, test: String? = nil, path: String? = nil,
                skill: SkillSource? = nil, votes: Int = 0, source: String? = nil, link: String? = nil) {
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
        self.source = source
        self.link = link
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
        source = try c.decodeIfPresent(String.self, forKey: .source)
        link = try c.decodeIfPresent(String.self, forKey: .link)
    }



    /// The title and summary in the language on screen.
    public func title(turkish: Bool) -> String { turkish ? (titleTR ?? title) : title }
    public func summary(turkish: Bool) -> String { turkish ? (summaryTR ?? summary) : summary }

    /// Where people read it, or open the files of a skill pack before adding it.
    public var webURL: URL? {
        if let link { return URL(string: link) }
        if let skill { return URL(string: "https://github.com/\(skill.repo)/tree/\(skill.ref)/\(skill.path)") }
        guard let path else { return nil }
        return URL(string: "\(LibraryIndex.repositoryURL)/blob/main/library/\(path)")
    }
}

public struct LibraryIndex: Codable, Equatable {
    public var version: Int
    public var generated: String?
    public var items: [LibraryEntry]

    public static let repository = "enmerasoftware/enterm"
    public static let repositoryURL = "https://github.com/\(repository)"
    public static let indexURL = URL(string: "https://raw.githubusercontent.com/\(repository)/main/library/index.json")!
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
    /// Saved community items, kept whole: they are not in the index, may be removed later and must work offline.
    public var kept: [LibraryEntry] = []
    /// Community items this Mac liked, and the ones it shared (so it can take them back).
    public var liked: Set<String> = []
    public var mine: Set<String> = []

    public init() {}

    enum CodingKeys: String, CodingKey { case saved, installedSkills, kept, liked, mine }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        saved = try c.decodeIfPresent([String].self, forKey: .saved) ?? []
        installedSkills = try c.decodeIfPresent([String: Date].self, forKey: .installedSkills) ?? [:]
        kept = try c.decodeIfPresent([LibraryEntry].self, forKey: .kept) ?? []
        liked = try c.decodeIfPresent(Set<String>.self, forKey: .liked) ?? []
        mine = try c.decodeIfPresent(Set<String>.self, forKey: .mine) ?? []
    }

    public static var file: URL { EntermPaths.support.appendingPathComponent("library-shelf.json") }
    public static func load() -> LibraryShelf { JSONStore.load(LibraryShelf.self, from: file) ?? LibraryShelf() }
    public func save() { JSONStore.save(self, to: Self.file) }

    public mutating func toggle(_ id: String) {
        if let index = saved.firstIndex(of: id) { saved.remove(at: index) } else { saved.insert(id, at: 0) }
    }

    /// Saves or unsaves an item; one from outside the index is kept whole.
    public mutating func toggle(_ item: LibraryEntry) {
        toggle(item.id)
        kept.removeAll { $0.id == item.id }
        if item.isCommunity, saved.contains(item.id) { kept.insert(item, at: 0) }
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

/// The community shelf of the Library: prompts and race tasks people share from Enterm, published at once by
/// Enterm's server (enterm.enmeraapps.com) after automatic checks, before anyone reviews them. Likes and reports go
/// there too, with a random id for this Mac; the server keeps only a one-way hash of it.
public enum CommunityLibrary {
    public static let source = "community"

    /// The server; ENTERM_LIBRARY_SERVER points a test copy at a local one.
    public static var server: URL {
        if let value = ProcessInfo.processInfo.environment["ENTERM_LIBRARY_SERVER"], let url = URL(string: value) { return url }
        return URL(string: "https://enterm.enmeraapps.com")!
    }

    public static var listURL: URL { server.appendingPathComponent("api/library/community") }
    public static var votesURL: URL { server.appendingPathComponent("api/library/votes") }
    public static func endpoint(_ name: String) -> URL { server.appendingPathComponent("api/library/\(name)") }

    /// A random id for this Mac, made once. It says nothing about the person; it only lets one like count once.
    public static var deviceID: String {
        let file = EntermPaths.support.appendingPathComponent("library-device")
        if let saved = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), saved.count >= 32 { return saved }
        let fresh = UUID().uuidString + UUID().uuidString
        try? FileManager.default.createDirectory(at: EntermPaths.support, withIntermediateDirectories: true)
        try? fresh.write(to: file, atomically: true, encoding: .utf8)
        return fresh
    }

    public static func parse(_ data: Data) -> [LibraryEntry]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = object["items"] as? [[String: Any]] else { return nil }
        return raw.compactMap(entry)
    }

    public static func entry(_ p: [String: Any]) -> LibraryEntry? {
        guard let id = p["id"] as? String, id.hasPrefix("c-"),
              let kind = (p["kind"] as? String).flatMap(LibraryEntry.Kind.init(rawValue:)), kind != .skill,
              let title = p["title"] as? String, !title.isEmpty, let text = p["text"] as? String, !text.isEmpty else { return nil }
        let reviewed = p["reviewed"] as? Bool ?? false
        return LibraryEntry(id: id, kind: kind, title: title, summary: p["summary"] as? String ?? "", text: text,
                            programs: p["programs"] as? [String] ?? [], tags: p["tags"] as? [String] ?? [],
                            author: p["author"] as? String ?? "", test: (p["test"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                            votes: p["votes"] as? Int ?? 0, source: reviewed ? "community-reviewed" : source,
                            link: server.appendingPathComponent("library").absoluteString + "#\(id)")
    }

    public static func parseVotes(_ data: Data) -> [String: Int]? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["votes"] as? [String: Int]
    }

    /// What a share sends. The server checks everything again; these limits only spare a round trip.
    public struct Submission: Codable, Equatable {
        public var kind: LibraryEntry.Kind
        public var title: String
        public var summary: String
        public var text: String
        public var test: String?
        public var programs: [String]
        public var tags: [String]
        public var author: String
        public var lang: String
        public var device: String

        public init(kind: LibraryEntry.Kind, title: String, summary: String, text: String, test: String?, programs: [String],
                    tags: [String], author: String, lang: String, device: String) {
            self.kind = kind
            self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.test = test.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            self.programs = programs
            self.tags = tags
            self.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lang = lang
            self.device = device
        }

        /// The first thing to fix, in Turkish (the app shows it through L), or nil when it can be sent.
        public var problem: String? {
            if title.count < 3 || title.count > 60 { return "Başlık 3 ile 60 karakter arasında olmalı." }
            if summary.count < 10 || summary.count > 200 { return "Özet 10 ile 200 karakter arasında olmalı." }
            if text.count < 80 { return "İstem en az 80 karakter olmalı." }
            if text.count > 8000 { return "İstem en fazla 8000 karakter olabilir." }
            if programs.isEmpty { return "En az bir program seçin." }
            if kind == .race {
                if (test ?? "").isEmpty { return "Yarış görevi bir test komutu ister." }
                if programs.filter({ ["claude", "codex", "gemini"].contains($0) }).count < 2 { return "Yarış görevi en az iki yarışabilen program ister (Claude Code, Codex, Gemini)." }
            }
            if author.count > 40 { return "Ad en fazla 40 karakter olabilir." }
            return nil
        }
    }
}

public extension LibraryEntry {
    /// Shared by someone through Enterm and published without review (or reviewed later).
    var isCommunity: Bool { source == CommunityLibrary.source || source == "community-reviewed" }
    var isReviewedCommunity: Bool { source == "community-reviewed" }
}

/// `${name}` and `${name:default}` in a prompt: blanks the person fills in before it is sent.
public enum PromptVariables {
    public struct Variable: Equatable, Hashable {
        public let name: String
        public let fallback: String
    }

    private static let pattern = try! NSRegularExpression(pattern: #"\$\{([^{}:\n]{1,40})(?::([^{}\n]*))?\}"#)

    /// Each blank once, in the order it first appears.
    public static func find(in text: String) -> [Variable] {
        var seen = Set<String>()
        var out: [Variable] = []
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = text[nameRange].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            let fallback = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            out.append(Variable(name: name, fallback: fallback))
        }
        return out
    }

    /// The text with every blank filled: the value given, else its default; a blank with neither stays as it is.
    public static func fill(_ text: String, with values: [String: String]) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var result = ""
        var last = text.startIndex
        for match in pattern.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<whole.lowerBound]
            let name = text[nameRange].trimmingCharacters(in: .whitespaces)
            let fallback = Range(match.range(at: 2), in: text).map { String(text[$0]) }
            let given = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            result += !given.isEmpty ? given : (fallback ?? String(text[whole]))
            last = whole.upperBound
        }
        return result + text[last...]
    }
}
