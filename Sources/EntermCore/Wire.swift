import Foundation

/// Paths shared by the app, the session service and the command line tool.
public enum EntermPaths {
    public static var support: URL {
        if let override = ProcessInfo.processInfo.environment["ENTERM_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Enterm", isDirectory: true)
    }
    /// Socket paths have a 104 byte limit, so the socket lives in a short per-user directory.
    public static var socket: URL {
        if let override = ProcessInfo.processInfo.environment["ENTERM_SOCKET"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: "/tmp/enterm-\(getuid())/entermd.sock")
    }
    public static var sessionsFile: URL { support.appendingPathComponent("sessions.json") }
    public static var scrollbackDir: URL { support.appendingPathComponent("scrollback", isDirectory: true) }
    public static var stateFile: URL { support.appendingPathComponent("state.json") }
    public static var settingsFile: URL { support.appendingPathComponent("settings.json") }
    public static var boardFile: URL { support.appendingPathComponent("board.json") }
    public static var teamFile: URL { support.appendingPathComponent("team.json") }
    public static var linksFile: URL { support.appendingPathComponent("links.json") }
    public static var permissionsFile: URL { support.appendingPathComponent("permissions.json") }
    public static var accountsFile: URL { support.appendingPathComponent("accounts.json") }
    public static var accountsDir: URL { support.appendingPathComponent("accounts", isDirectory: true) }
    public static var mailDir: URL { support.appendingPathComponent("mail", isDirectory: true) }
    public static var hooksDir: URL { support.appendingPathComponent("hooks", isDirectory: true) }

    public static func ensureDirectories() {
        let fm = FileManager.default
        for dir in [support, scrollbackDir, accountsDir, mailDir, hooksDir, socket.deletingLastPathComponent()] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }
    }
}

/// A message on the local socket. One frame is `[u32 length][u8 kind][payload]`, big endian.
public enum WireKind: UInt8 {
    case json = 0
    /// Payload: `[u32 session number][bytes]`.
    case output = 1
    /// Payload: `[u32 session number][bytes]`.
    case input = 2
    /// Payload: `[u32 session number][bytes]`, past output sent when a client attaches.
    case replay = 3
}

public struct WireFrame {
    public var kind: WireKind
    public var payload: Data
    public init(kind: WireKind, payload: Data) {
        self.kind = kind
        self.payload = payload
    }

    public func encoded() -> Data {
        var out = Data(capacity: payload.count + 5)
        var length = UInt32(payload.count + 1).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(kind.rawValue)
        out.append(payload)
        return out
    }

    public static func session(_ kind: WireKind, number: UInt32, bytes: Data) -> WireFrame {
        var payload = Data(capacity: bytes.count + 4)
        var value = number.bigEndian
        withUnsafeBytes(of: &value) { payload.append(contentsOf: $0) }
        payload.append(bytes)
        return WireFrame(kind: kind, payload: payload)
    }

    public func splitSession() -> (UInt32, Data)? {
        guard payload.count >= 4 else { return nil }
        let start = payload.startIndex
        let number = payload[start..<start + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return (number, Data(payload[(start + 4)...]))
    }
}

/// Reassembles frames from a byte stream.
public struct WireDecoder {
    private var buffer = Data()
    public init() {}

    public mutating func feed(_ data: Data) -> [WireFrame] {
        buffer.append(data)
        var frames: [WireFrame] = []
        var offset = buffer.startIndex
        while buffer.endIndex - offset >= 4 {
            let length = buffer[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard length >= 1, length < 64 * 1024 * 1024 else {
                buffer.removeAll()
                return frames
            }
            guard buffer.endIndex - offset >= 4 + length else { break }
            let kindByte = buffer[offset + 4]
            let payload = Data(buffer[(offset + 5)..<(offset + 4 + length)])
            if let kind = WireKind(rawValue: kindByte) {
                frames.append(WireFrame(kind: kind, payload: payload))
            }
            offset += 4 + length
        }
        if offset > buffer.startIndex {
            buffer = Data(buffer[offset...])
        }
        return frames
    }
}

/// Control messages. Requests and events share one flat shape to keep the protocol readable from any language.
public struct WireMessage: Codable {
    public var op: String
    public var id: String?
    public var number: UInt32?
    public var spec: SessionSpec?
    public var sessions: [SessionInfo]?
    public var session: SessionInfo?
    public var rows: Int?
    public var cols: Int?
    public var event: AgentEvent?
    public var text: String?
    public var error: String?
    public var version: Int?
    public var decision: String?
    public var limit: Int?
    /// Where a read of a file left off, so the next read sends only what is new.
    public var offset: Int64?

    public init(op: String) { self.op = op }

    public func frame() -> WireFrame {
        let encoder = JSONEncoder()
        return WireFrame(kind: .json, payload: (try? encoder.encode(self)) ?? Data())
    }
    public static func decode(_ data: Data) -> WireMessage? {
        try? JSONDecoder().decode(WireMessage.self, from: data)
    }
    public static let protocolVersion = 1
}
