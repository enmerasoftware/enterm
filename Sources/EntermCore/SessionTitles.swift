import Foundation

/// A session's title as the program itself wrote it. No model is called: Claude Code keeps its own title lines
/// in the transcript, Codex keeps thread names in `session_index.jsonl`.
public enum SessionTitles {
    /// The last `custom-title` (the person's) or else the last `ai-title` (the program's) in the transcript's tail.
    public static func claude(transcript text: String) -> String? {
        var custom: String?, ai: String?
        for line in text.split(separator: "\n") where line.contains("-title\"") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "custom-title": custom = (object["customTitle"] as? String) ?? custom
            case "ai-title": ai = (object["aiTitle"] as? String) ?? ai
            default: break
            }
        }
        return clean(custom ?? ai)
    }

    /// The last name given to this thread.
    public static func codex(index text: String, thread: String) -> String? {
        var found: String?
        for line in text.split(separator: "\n") where line.contains(thread) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["id"] as? String == thread, let name = object["thread_name"] as? String else { continue }
            found = name
        }
        return clean(found)
    }

    /// Reads only the end of a long file: titles are rewritten as the conversation goes on.
    public static func tail(of path: String, bytes: Int = 512 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        let data = handle.readDataToEndOfFile()
        return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }

    public static func clean(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title.count > 48 ? String(title.prefix(47)) + "…" : title
    }
}

/// A Claude Code loop in words: from CronCreate, ScheduleWakeup and CronDelete as they pass the tool hook.
public enum LoopText {
    public struct Loop: Equatable {
        public var summary: String
        public var next: Date?
    }

    /// Nil means the loop ended.
    public static func from(tool: String, input: [String: Any], now: Date = Date()) -> Loop?? {
        switch tool {
        case "CronCreate":
            let cron = input["cron"] as? String ?? ""
            let recurring = input["recurring"] as? Bool ?? true
            return .some(Loop(summary: recurring ? describe(cron: cron) : "Bir kez · \(cron)", next: next(cron: cron, after: now)))
        case "ScheduleWakeup":
            if input["stop"] as? Bool == true { return .some(nil) }
            let seconds = (input["delaySeconds"] as? NSNumber)?.doubleValue ?? 0
            guard seconds > 0 else { return nil }
            return .some(Loop(summary: "Kendi Temposunda · \(minutes(seconds))", next: now.addingTimeInterval(seconds)))
        case "CronDelete":
            return .some(nil)
        default:
            return nil
        }
    }

    /// The common shapes in words; anything else as written.
    public static func describe(cron: String) -> String {
        let f = cron.split(separator: " ").map(String.init)
        guard f.count == 5 else { return cron }
        if f[0].hasPrefix("*/"), f[1...].allSatisfy({ $0 == "*" }), let n = Int(f[0].dropFirst(2)) { return "Her \(n) Dk" }
        if f[0] == "*", f[1...].allSatisfy({ $0 == "*" }) { return "Her Dakika" }
        if Int(f[0]) != nil, f[1] == "*", f[2...].allSatisfy({ $0 == "*" }) { return "Saatte Bir" }
        if Int(f[0]) != nil, f[1].hasPrefix("*/"), let n = Int(f[1].dropFirst(2)), f[2...].allSatisfy({ $0 == "*" }) { return "Her \(n) Saat" }
        if let m = Int(f[0]), let h = Int(f[1]), f[2...].allSatisfy({ $0 == "*" }) { return String(format: "Her Gün %02d:%02d", h, m) }
        return cron
    }

    /// The next run for the shapes `describe` knows by minute; nil otherwise.
    public static func next(cron: String, after now: Date) -> Date? {
        let f = cron.split(separator: " ").map(String.init)
        guard f.count == 5, f[1...].allSatisfy({ $0 == "*" }) else { return nil }
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        // The start of this minute.
        let start = now.addingTimeInterval(-Double(calendar.component(.second, from: now)))
        if f[0].hasPrefix("*/"), let n = Int(f[0].dropFirst(2)), n > 0 {
            return calendar.date(byAdding: .minute, value: n - minute % n, to: start)
        }
        if let m = Int(f[0]) {
            let ahead = m > minute ? m - minute : 60 - minute + m
            return calendar.date(byAdding: .minute, value: ahead, to: start)
        }
        return nil
    }

    static func minutes(_ seconds: Double) -> String {
        seconds < 3600 ? "\(Int((seconds / 60).rounded())) Dk Sonra" : String(format: "%.1f Saat Sonra", seconds / 3600)
    }
}
