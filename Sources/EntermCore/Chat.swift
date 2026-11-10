import Foundation

/// One line of a conversation as the chat view shows it.
public struct ChatItem: Equatable, Identifiable {
    public enum Role: Equatable { case user, assistant, tool }
    public let id: Int
    public let role: Role
    public let text: String
    public init(id: Int, role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// Reads the transcripts of Claude Code and Codex. Their format is theirs and may change:
/// a line that cannot be read is skipped, it never fails.
public struct ChatParser {
    public private(set) var items: [ChatItem] = []
    private var next = 0

    public init() {}

    public mutating func feed(_ text: String) {
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if object["isMeta"] as? Bool == true || object["isSidechain"] as? Bool == true { continue }
            switch object["type"] as? String {
            case "user": readClaude(object, role: .user)
            case "assistant": readClaude(object, role: .assistant)
            case "response_item": readCodex(object["payload"] as? [String: Any] ?? [:])
            default: break
            }
        }
    }

    private mutating func add(_ role: ChatItem.Role, _ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        items.append(ChatItem(id: next, role: role, text: clean))
        next += 1
    }

    private mutating func readClaude(_ object: [String: Any], role: ChatItem.Role) {
        let message = object["message"] as? [String: Any]
        if let text = message?["content"] as? String {
            if !text.hasPrefix("<") { add(role, text) }
            return
        }
        for part in message?["content"] as? [[String: Any]] ?? [] {
            switch part["type"] as? String {
            case "text":
                if let text = part["text"] as? String, !text.hasPrefix("<") { add(role, text) }
            case "tool_use":
                add(.tool, Self.toolLine(name: part["name"] as? String ?? "", input: part["input"] as? [String: Any] ?? [:]))
            default:
                break
            }
        }
    }

    private mutating func readCodex(_ payload: [String: Any]) {
        switch payload["type"] as? String {
        case "message":
            let role: ChatItem.Role = payload["role"] as? String == "user" ? .user : .assistant
            for part in payload["content"] as? [[String: Any]] ?? [] {
                if let text = part["text"] as? String, !text.hasPrefix("<") { add(role, text) }
            }
        case "function_call", "local_shell_call":
            add(.tool, payload["name"] as? String ?? "Komut")
        default:
            break
        }
    }

    /// The tool and the one thing worth reading about it.
    static func toolLine(name: String, input: [String: Any]) -> String {
        for key in ["command", "file_path", "path", "pattern", "query", "url", "description"] {
            if let value = input[key] as? String, !value.isEmpty { return "\(name) \(value.split(separator: "\n").first ?? "")" }
        }
        return name
    }
}

/// The few shapes of Markdown a program's answer uses.
public enum MarkdownBlock: Equatable {
    case heading(String)
    case paragraph(String)
    case bullet(String)
    case code(String)

    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var code: [String]?
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("#") {
                flush()
                blocks.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " ", !line[..<dot].isEmpty {
                flush()
                blocks.append(.bullet(line))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        return blocks
    }
}

/// How much memory a session really holds: the program and everything it started.
public enum ProcessTree {
    public struct Entry: Equatable {
        public let pid: Int32
        public let parent: Int32
        public let rssKB: Int
        public let name: String
        public init(pid: Int32, parent: Int32, rssKB: Int, name: String) {
            self.pid = pid
            self.parent = parent
            self.rssKB = rssKB
            self.name = name
        }
    }

    /// Reads `ps -axo pid=,ppid=,rss=,comm=`.
    public static func parse(_ text: String) -> [Entry] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let parent = Int32(parts[1]), let rss = Int(parts[2]) else { return nil }
            return Entry(pid: pid, parent: parent, rssKB: rss, name: URL(fileURLWithPath: String(parts[3])).lastPathComponent)
        }
    }

    /// The memory of a process and all its descendants, and how many descendants there are.
    public static func total(root: Int32, in entries: [Entry]) -> (rssKB: Int, children: Int) {
        var children: [Int32: [Entry]] = [:]
        var own = 0
        for entry in entries {
            children[entry.parent, default: []].append(entry)
            if entry.pid == root { own = entry.rssKB }
        }
        var total = own, count = 0
        var stack = children[root] ?? []
        while let entry = stack.popLast() {
            total += entry.rssKB
            count += 1
            stack += children[entry.pid] ?? []
        }
        return (total, count)
    }
}

/// Reads a transcript a piece at a time for the phone: the end of a long one first, then only what was added.
public enum TranscriptReader {
    /// A first read starts this far from the end; later ones send at most this much.
    public static let window: Int64 = 400_000

    /// `from` nil starts near the end. A file that got shorter was replaced, so the read starts over and says so.
    public static func read(path: String, from: Int64?) -> (text: String, offset: Int64, reset: Bool) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return ("", from ?? 0, false) }
        defer { try? handle.close() }
        let size = Int64((try? handle.seekToEnd()) ?? 0)
        var reset = false
        var start: Int64
        if let from, from <= size {
            start = from
        } else {
            reset = from != nil
            start = max(0, size - window)
        }
        let fresh = start > 0 && (from == nil || reset)
        try? handle.seek(toOffset: UInt64(start))
        guard var data = try? handle.read(upToCount: Int(min(window, size - start))), !data.isEmpty else {
            return ("", start, reset)
        }
        // Starting inside a line: that part is skipped.
        if fresh, let first = data.firstIndex(of: UInt8(ascii: "\n")) {
            start += Int64(data.distance(from: data.startIndex, to: first) + 1)
            data = data[data.index(after: first)...]
        }
        guard let last = data.lastIndex(of: UInt8(ascii: "\n")) else { return ("", start, reset) }
        let complete = data[data.startIndex...last]
        return (String(decoding: complete, as: UTF8.self), start + Int64(complete.count), reset)
    }
}
