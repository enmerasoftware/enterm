import Foundation

/// Blocking socket helpers shared by the command line tool and the app.
public enum WireSocket {
    public static func connect(path: String = EntermPaths.socket.path) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Foundation.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    @discardableResult
    public static func writeAll(fd: Int32, data: Data) -> Bool {
        var offset = 0
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            while offset < raw.count {
                let written = write(fd, base + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN {
                        var pollFD = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                        _ = poll(&pollFD, 1, 1000)
                        continue
                    }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    /// Sends one message and optionally waits for one JSON reply, up to `timeout` seconds.
    public static func send(_ message: WireMessage, waitForReply: Bool = false, timeout: TimeInterval = 2) -> WireMessage? {
        guard let fd = connect() else { return nil }
        defer { close(fd) }
        guard writeAll(fd: fd, data: message.frame().encoded()) else { return nil }
        guard waitForReply else { return nil }
        var decoder = WireDecoder()
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return nil }
            var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollFD, 1, Int32(min(remaining * 1000, 1000)))
            if ready < 0 && errno != EINTR { return nil }
            if ready <= 0 { continue }
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { return nil }
            for frame in decoder.feed(Data(buffer[0..<count])) where frame.kind == .json {
                if let reply = WireMessage.decode(frame.payload) { return reply }
            }
        }
    }
}
