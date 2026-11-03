import EntermCore
import Foundation

/// The app's connection to the session service. All callbacks run on the main queue.
final class ServiceConnection {
    var onMessage: ((WireMessage) -> Void)?
    var onOutput: ((UInt32, Data, Bool) -> Void)?
    var onDisconnect: (() -> Void)?

    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var decoder = WireDecoder()
    private var requests: [String: (WireMessage) -> Void] = [:]

    var isConnected: Bool { fd >= 0 }

    /// Starts the service when it is not running. The service keeps running after the app quits.
    func connect(completion: @escaping (Bool) -> Void) {
        attempt(retries: 40, launched: false, completion: completion)
    }

    private func attempt(retries: Int, launched: Bool, completion: @escaping (Bool) -> Void) {
        if let socket = WireSocket.connect() {
            adopt(socket)
            completion(true)
            return
        }
        guard retries > 0 else {
            completion(false)
            return
        }
        if !launched { launchService() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.attempt(retries: retries - 1, launched: true, completion: completion)
        }
    }

    private func launchService() {
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable.deletingLastPathComponent().appendingPathComponent("entermd")
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func adopt(_ socket: Int32) {
        fd = socket
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: .main)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.resume()
        self.source = source
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(fd, &buffer, buffer.count)
        if count <= 0 {
            if count < 0 && (errno == EAGAIN || errno == EINTR) { return }
            source?.cancel()
            source = nil
            close(fd)
            fd = -1
            onDisconnect?()
            return
        }
        for frame in decoder.feed(Data(buffer[0..<count])) {
            switch frame.kind {
            case .json:
                guard let message = WireMessage.decode(frame.payload) else { continue }
                if let id = message.id, let handler = requests.removeValue(forKey: id) {
                    handler(message)
                } else {
                    onMessage?(message)
                }
            case .output, .replay:
                if let (number, bytes) = frame.splitSession() {
                    onOutput?(number, bytes, frame.kind == .replay)
                }
            case .input:
                break
            }
        }
    }

    func send(_ message: WireMessage) {
        guard fd >= 0 else { return }
        WireSocket.writeAll(fd: fd, data: message.frame().encoded())
    }

    func request(_ message: WireMessage, reply: @escaping (WireMessage) -> Void) {
        var message = message
        let id = UUID().uuidString
        message.id = id
        requests[id] = reply
        send(message)
    }

    func sendInput(number: UInt32, bytes: Data) {
        guard fd >= 0 else { return }
        WireSocket.writeAll(fd: fd, data: WireFrame.session(.input, number: number, bytes: bytes).encoded())
    }
}
