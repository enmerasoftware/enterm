import Foundation

/// What an agent did, in order and in time, read from the program's own transcript (Claude Code, Codex).
/// The same file the chat view reads; a line that cannot be read is skipped.
public struct TimelineEvent: Codable, Equatable {
    public enum Kind: String, Codable, CaseIterable {
        /// The person asked something.
        case prompt
        /// The agent answered in words.
        case reply
        /// A file was written or changed.
        case edit
        /// A shell command ran.
        case command
        /// Something was read or searched.
        case read
        /// Any other tool.
        case tool
    }

    public var at: Date
    public var kind: Kind
    public var text: String
    public var file: String?

    public init(at: Date, kind: Kind, text: String, file: String? = nil) {
        self.at = at
        self.kind = kind
        self.text = text
        self.file = file
    }
}

public struct Timeline: Equatable {
    public private(set) var events: [TimelineEvent] = []

    public init(events: [TimelineEvent] = []) {
        self.events = events.sorted { $0.at < $1.at }
    }

    public var start: Date? { events.first?.at }
    public var end: Date? { events.last?.at }

    /// Files in the order they were first touched.
    public var files: [String] {
        var seen: [String] = []
        for event in events where event.kind == .edit {
            if let file = event.file, !seen.contains(file) { seen.append(file) }
        }
        return seen
    }

    /// Where each event stands on a track, in seconds, with long pauses (a person away, a slow approval)
    /// shortened to `gap`, so the replay shows work rather than waiting.
    public func compressed(gap: TimeInterval = 20) -> [TimeInterval] {
        var out: [TimeInterval] = []
        var clock: TimeInterval = 0
        var previous: Date?
        for event in events {
            if let previous { clock += min(max(0, event.at.timeIntervalSince(previous)), gap) }
            out.append(clock)
            previous = event.at
        }
        return out
    }

    // MARK: Reading

    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plainStamp = ISO8601DateFormatter()

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return stamp.date(from: text) ?? plainStamp.date(from: text)
    }

    public static func parse(_ text: String) -> Timeline {
        var events: [TimelineEvent] = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let at = date(object["timestamp"]) else { continue }
            if object["isMeta"] as? Bool == true || object["isSidechain"] as? Bool == true { continue }
            switch object["type"] as? String {
            case "user", "assistant": events += claude(object, at: at)
            case "response_item": events += codex(object["payload"] as? [String: Any] ?? [:], at: at)
            default: break
            }
        }
        return Timeline(events: events)
    }

    public static func read(path: String) -> Timeline {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return Timeline() }
        return parse(text)
    }

    private static func clean(_ text: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("<") else { return nil }
        return String(line.prefix(400))
    }

    private static func claude(_ object: [String: Any], at: Date) -> [TimelineEvent] {
        let role: TimelineEvent.Kind = object["type"] as? String == "user" ? .prompt : .reply
        let message = object["message"] as? [String: Any]
        if let text = message?["content"] as? String {
            return clean(text).map { [TimelineEvent(at: at, kind: role, text: $0)] } ?? []
        }
        var out: [TimelineEvent] = []
        for part in message?["content"] as? [[String: Any]] ?? [] {
            switch part["type"] as? String {
            case "text":
                if let text = (part["text"] as? String).flatMap(clean) { out.append(TimelineEvent(at: at, kind: role, text: text)) }
            case "tool_use":
                out.append(tool(name: part["name"] as? String ?? "", input: part["input"] as? [String: Any] ?? [:], at: at))
            default:
                break
            }
        }
        return out
    }

    /// Claude Code's tools by what they do.
    static func tool(name: String, input: [String: Any], at: Date) -> TimelineEvent {
        let file = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) ?? (input["path"] as? String)
        switch name {
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            return TimelineEvent(at: at, kind: .edit, text: name, file: file)
        case "Bash":
            return TimelineEvent(at: at, kind: .command, text: firstLine(input["command"] as? String ?? name))
        case "Read", "Grep", "Glob", "LS", "WebFetch", "WebSearch":
            let what = file ?? (input["pattern"] as? String) ?? (input["query"] as? String) ?? (input["url"] as? String) ?? ""
            return TimelineEvent(at: at, kind: .read, text: what.isEmpty ? name : "\(name) \(firstLine(what))")
        default:
            return TimelineEvent(at: at, kind: .tool, text: ChatParser.toolLine(name: name, input: input))
        }
    }

    private static func codex(_ payload: [String: Any], at: Date) -> [TimelineEvent] {
        switch payload["type"] as? String {
        case "message":
            let role: TimelineEvent.Kind = payload["role"] as? String == "user" ? .prompt : .reply
            return (payload["content"] as? [[String: Any]] ?? []).compactMap { part in
                (part["text"] as? String).flatMap(clean).map { TimelineEvent(at: at, kind: role, text: $0) }
            }
        case "function_call", "custom_tool_call", "local_shell_call":
            let name = payload["name"] as? String ?? "shell"
            let raw = (payload["arguments"] as? String) ?? (payload["input"] as? String) ?? ""
            if name.contains("patch") || raw.contains("*** Begin Patch") {
                return patchedFiles(raw).map { TimelineEvent(at: at, kind: .edit, text: "apply_patch", file: $0) }
                    .nonEmpty ?? [TimelineEvent(at: at, kind: .edit, text: "apply_patch")]
            }
            let arguments = raw.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let command: String
            if let words = arguments?["command"] as? [String] {
                // ["bash", "-lc", "the command"]: the command is the last word.
                command = words.count >= 3 && words[1].hasPrefix("-") ? words.last ?? "" : words.joined(separator: " ")
            } else {
                command = (arguments?["command"] as? String) ?? (arguments?["cmd"] as? String) ?? name
            }
            return [TimelineEvent(at: at, kind: .command, text: firstLine(command))]
        default:
            return []
        }
    }

    /// The files a Codex patch touches.
    static func patchedFiles(_ patch: String) -> [String] {
        patch.components(separatedBy: "\n").compactMap { line in
            for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
    }

    private static func firstLine(_ text: String) -> String {
        String(text.split(separator: "\n").first ?? "").trimmingCharacters(in: .whitespaces)
    }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
