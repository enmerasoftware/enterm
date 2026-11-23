import Foundation

// A race: the same task given to several agents at once, each in its own git worktree off the same commit.
// The person compares what each one did and merges one. Nothing here runs git; it holds the record and the rules.

public struct RaceEntrant: Codable, Equatable, Identifiable {
    public var id: String { branch }
    /// The program's raw value (`ToolKind`), kept as text so the core needs no app types.
    public var tool: String
    public var title: String
    public var branch: String
    public var folder: String
    public var sessionID: String?
    public var startedAt: Date?
    /// The first time the agent stopped working after it had started.
    public var finishedAt: Date?
    public var stat = DiffStat()
    public var tests: TestResult?
    /// The program's transcript, kept for the replay after the box is gone.
    public var transcript: String?

    public init(tool: String, title: String, branch: String, folder: String) {
        self.tool = tool
        self.title = title
        self.branch = branch
        self.folder = folder
    }

    public var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

public enum TestResult: String, Codable, Equatable {
    case running, passed, failed
}

public struct Race: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var task: String
    /// The repository the worktrees branch off, and the commit they start from.
    public var root: String
    public var base: String
    public var testCommand: String?
    public var entrants: [RaceEntrant] = []
    public var createdAt = Date()
    public var winner: String?
    /// Merged or dropped: the worktrees are gone and the race is history.
    public var closed = false

    public init(task: String, root: String, base: String, testCommand: String?) {
        self.task = task
        self.root = root
        self.base = base
        self.testCommand = testCommand
    }

    /// Finishing order. Those still working come after, in the order they started.
    public var standings: [RaceEntrant] {
        entrants.enumerated().sorted { a, b in
            switch (a.element.finishedAt, b.element.finishedAt) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// 1 for the first to finish; nil while still working.
    public func place(of branch: String) -> Int? {
        guard entrants.first(where: { $0.branch == branch })?.finishedAt != nil else { return nil }
        return standings.firstIndex { $0.branch == branch }.map { $0 + 1 }
    }

    public var isFinished: Bool { !entrants.isEmpty && entrants.allSatisfy { $0.finishedAt != nil } }

    /// How far along the track a box's runner stands, 0...1: its changed lines against the leader's.
    /// A finished agent is at the flag. Lines are not quality, only a sign of life; the result page says so.
    public func progress(of branch: String) -> Double {
        guard let entrant = entrants.first(where: { $0.branch == branch }) else { return 0 }
        if entrant.finishedAt != nil { return 1 }
        let lines = entrants.map { $0.stat.insertions + $0.stat.deletions }.max() ?? 0
        guard lines > 0 else { return 0.04 }
        // Short of the flag until it says it is done.
        return 0.04 + 0.86 * Double(entrant.stat.insertions + entrant.stat.deletions) / Double(lines)
    }
}

/// `git diff --shortstat`: "3 files changed, 40 insertions(+), 2 deletions(-)".
public struct DiffStat: Codable, Equatable {
    public var files = 0
    public var insertions = 0
    public var deletions = 0

    public init(files: Int = 0, insertions: Int = 0, deletions: Int = 0) {
        self.files = files
        self.insertions = insertions
        self.deletions = deletions
    }

    public static func parse(_ text: String) -> DiffStat {
        var stat = DiffStat()
        for part in text.split(separator: ",") {
            let words = part.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            guard let number = words.first.flatMap({ Int($0) }), words.count > 1 else { continue }
            let word = words[1]
            if word.hasPrefix("file") { stat.files = number }
            else if word.hasPrefix("insertion") { stat.insertions = number }
            else if word.hasPrefix("deletion") { stat.deletions = number }
        }
        return stat
    }
}

public enum RacePlan {
    /// A branch-safe piece of the task: "Kupon iadesini düzelt" → "kupon-iadesini-duzelt".
    public static func slug(_ task: String, limit: Int = 28) -> String {
        // Dotless ı has no accent to strip, so it is spelled out first.
        let spelled = task.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "I")
        let folded = spelled.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? spelled
        var out = ""
        var dash = false
        for character in folded.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                out.append(character)
                dash = false
            } else if !dash, !out.isEmpty {
                out.append("-")
                dash = true
            }
            if out.count >= limit { break }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "gorev" : out
    }

    /// One branch per program, unique among the branches the repository already has.
    public static func branch(task: String, tool: String, taken: Set<String>) -> String {
        let base = "yaris/\(slug(task))-\(tool)"
        var name = base
        var number = 2
        while taken.contains(name) {
            name = "\(base)-\(number)"
            number += 1
        }
        return name
    }

    /// Next to the repository, like the other worktrees Enterm opens: `<repo>.worktrees/<branch>`.
    public static func folder(root: String, branch: String) -> String {
        let parent = (root as NSString).deletingLastPathComponent
        let name = (root as NSString).lastPathComponent
        return "\(parent)/\(name).worktrees/\(branch.replacingOccurrences(of: "/", with: "-"))"
    }

    /// What the agent is told. The same words for everyone, so the race is fair.
    public static func prompt(task: String) -> String {
        "\(task)\n\nThis folder is a git worktree made for you alone; other agents are doing the same task in their own folders. Work only here. When you are done, commit your work on this branch with a short message and stop."
    }

    /// The project's own test command, from the files at its root. Nil when there is no obvious one.
    public static func testCommand(files: Set<String>) -> String? {
        if files.contains("Package.swift") { return "swift test" }
        if files.contains("Cargo.toml") { return "cargo test" }
        if files.contains("go.mod") { return "go test ./..." }
        if files.contains("package.json") {
            if files.contains("pnpm-lock.yaml") { return "pnpm test" }
            if files.contains("yarn.lock") { return "yarn test" }
            if files.contains("bun.lockb") || files.contains("bun.lock") { return "bun test" }
            return "npm test"
        }
        if files.contains("pyproject.toml") || files.contains("pytest.ini") || files.contains("setup.py") { return "python3 -m pytest" }
        if files.contains("Gemfile") { return "bundle exec rake test" }
        if files.contains("Makefile") { return "make test" }
        return nil
    }
}

public struct RaceBook: Codable, Equatable {
    public var races: [Race] = []
    public init() {}

    public static var file: URL { EntermPaths.support.appendingPathComponent("races.json") }
    public static func load() -> RaceBook { JSONStore.load(RaceBook.self, from: file) ?? RaceBook() }
    public func save() { JSONStore.save(self, to: Self.file) }

    /// The race a session runs in, if it is still open.
    public func race(of sessionID: String) -> Race? {
        races.first { !$0.closed && $0.entrants.contains { $0.sessionID == sessionID } }
    }
}
