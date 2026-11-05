import CoreGraphics
import Foundation

/// What a line typed on the home screen means.
public enum HomeIntent: Equatable {
    /// Nothing typed: the default program opens.
    case open
    case folder(String)
    case command(String)
}

public enum HomeInput {
    public static func parse(_ text: String, home: String, isDirectory: (String) -> Bool) -> HomeIntent {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return .open }
        if line.hasPrefix("/") || line.hasPrefix("~") {
            let path = line.hasPrefix("~") ? home + line.dropFirst() : line
            if isDirectory(path) { return .folder(path) }
        }
        return .command(line)
    }
}

/// The Enter line: links run straight and turn at right angles, like the key they are named after.
public enum LinkRoute {
    static let stub: CGFloat = 20

    public static func points(from a: CGRect, to b: CGRect) -> [CGPoint] {
        if b.minX >= a.maxX { return facing(CGPoint(x: a.maxX, y: a.midY), CGPoint(x: b.minX, y: b.midY)) }
        if a.minX >= b.maxX { return facing(CGPoint(x: a.minX, y: a.midY), CGPoint(x: b.maxX, y: b.midY)) }
        // One above the other: leave to the right, pass between them, come in from the left.
        let start = CGPoint(x: a.maxX, y: a.midY)
        let end = CGPoint(x: b.minX, y: b.midY)
        let between = a.midY < b.midY ? (a.maxY + b.minY) / 2 : (a.minY + b.maxY) / 2
        return [start, CGPoint(x: start.x + stub, y: start.y), CGPoint(x: start.x + stub, y: between),
                CGPoint(x: end.x - stub, y: between), CGPoint(x: end.x - stub, y: end.y), end]
    }

    private static func facing(_ start: CGPoint, _ end: CGPoint) -> [CGPoint] {
        if start.y == end.y { return [start, end] }
        let middle = (start.x + end.x) / 2
        return [start, CGPoint(x: middle, y: start.y), CGPoint(x: middle, y: end.y), end]
    }

    public static func distance(from point: CGPoint, to route: [CGPoint]) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for (p, q) in zip(route, route.dropFirst()) {
            let dx = q.x - p.x, dy = q.y - p.y
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((point.x - p.x) * dx + (point.y - p.y) * dy) / length))
            best = min(best, hypot(point.x - (p.x + t * dx), point.y - (p.y + t * dy)))
        }
        return best
    }
}

/// Whoever needs the person comes first. Within a rank, sessions keep their order so nothing jumps around.
public enum RailOrder {
    public static func sorted<T>(_ items: [T], status: (T) -> SessionStatus) -> [T] {
        items.enumerated().sorted { left, right in
            let a = rank(status(left.element)), b = rank(status(right.element))
            return a == b ? left.offset < right.offset : a < b
        }.map(\.element)
    }

    private static func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .needsApproval: return 0
        case .limitReached: return 1
        case .failed, .notFound: return 2
        case .running, .starting: return 3
        default: return 4
        }
    }
}

/// Motion runs only when something happens, and never when there is a reason to be still.
public enum MotionPolicy {
    public static func allowed(setting: Bool, reduceMotion: Bool, lowPower: Bool, windowVisible: Bool) -> Bool {
        setting && !reduceMotion && !lowPower && windowVisible
    }

    public static func sweeps(from previous: SessionStatus?, to current: SessionStatus) -> Bool {
        guard let previous, previous != current else { return false }
        return current == .needsApproval || current == .limitReached || current == .failed
    }
}

/// A past Claude Code conversation, read from the program's own files. Nothing is written there.
public struct RecentConversation: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let folder: String
    public let modified: Date

    public init(id: String, title: String, folder: String, modified: Date) {
        self.id = id
        self.title = title
        self.folder = folder
        self.modified = modified
    }

    public struct Group: Equatable {
        public let folder: String
        public let items: [RecentConversation]
    }

    /// The file's format is the program's own and may change: what cannot be read is left out, it never fails.
    public static func parse(text: String, id: String, modified: Date) -> RecentConversation? {
        var folder: String?
        var aiTitle: String?
        var customTitle: String?
        var firstPrompt: String?
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if folder == nil, let cwd = object["cwd"] as? String, !cwd.isEmpty { folder = cwd }
            if let title = object["customTitle"] as? String, !title.isEmpty { customTitle = title }
            if let title = object["aiTitle"] as? String, !title.isEmpty { aiTitle = title }
            if firstPrompt == nil, object["type"] as? String == "user", let message = object["message"] as? [String: Any] {
                firstPrompt = promptLine(message["content"])
            }
        }
        guard let folder, let title = customTitle ?? aiTitle ?? firstPrompt else { return nil }
        return RecentConversation(id: id, title: title, folder: folder, modified: modified)
    }

    private static func promptLine(_ content: Any?) -> String? {
        var text = content as? String
        if text == nil, let parts = content as? [[String: Any]] {
            text = parts.first { $0["type"] as? String == "text" }?["text"] as? String
        }
        guard let line = text?.split(separator: "\n").first.map(String.init), !line.hasPrefix("<") else { return nil }
        return line
    }

    public static func grouped(_ items: [RecentConversation], limit: Int) -> [Group] {
        var order: [String] = []
        var groups: [String: [RecentConversation]] = [:]
        for item in items.sorted(by: { $0.modified > $1.modified }).prefix(limit) {
            if groups[item.folder] == nil { order.append(item.folder) }
            groups[item.folder, default: []].append(item)
        }
        return order.map { Group(folder: $0, items: groups[$0] ?? []) }
    }

    /// Reads only the start and the end of the newest files, so a long conversation costs the same as a short one.
    public static func scan(projects: URL, newest: Int = 16, bytes: Int = 48 * 1024) -> [RecentConversation] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        var files: [(url: URL, date: Date)] = []
        for folder in (try? manager.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            for file in (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? [] where file.pathExtension == "jsonl" {
                files.append((file, (try? file.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast))
            }
        }
        return files.sorted { $0.date > $1.date }.prefix(newest).compactMap { file in
            guard let handle = try? FileHandle(forReadingFrom: file.url) else { return nil }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            var data = Data()
            try? handle.seek(toOffset: 0)
            data.append((try? handle.read(upToCount: bytes)) ?? Data())
            if size > UInt64(bytes) {
                try? handle.seek(toOffset: max(UInt64(bytes), size - UInt64(bytes)))
                data.append(Data("\n".utf8))
                data.append((try? handle.read(upToCount: bytes)) ?? Data())
            }
            return parse(text: String(decoding: data, as: UTF8.self), id: file.url.deletingPathExtension().lastPathComponent, modified: file.date)
        }
    }
}
