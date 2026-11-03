import EntermCore
import Foundation

/// Reads Codex's limits through its documented app-server, as a short-lived helper. It never starts a model turn.
/// The server is marked experimental, so any failure simply means "not known".
enum CodexLimits {
    static func executable() -> String? {
        let home = NSHomeDirectory()
        let candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
            + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex",
               "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func read(account: Account, done: @escaping (LimitSnapshot?) -> Void) {
        guard let path = executable() else {
            done(nil)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let result = query(path: path, codexHome: account.configDir)
            DispatchQueue.main.async { done(result) }
        }
    }

    private static func query(path: String, codexHome: String?) -> LimitSnapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        var env = ProcessInfo.processInfo.environment
        if let codexHome { env["CODEX_HOME"] = codexHome }
        process.environment = env
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        defer { if process.isRunning { process.terminate() } }
        func send(_ object: [String: Any]) {
            guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
            data.append(0x0a)
            try? input.fileHandleForWriting.write(contentsOf: data)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var snapshot: LimitSnapshot?
        var buffer = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                semaphore.signal()
                return
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0a) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? Int else { continue }
                if id == 0 {
                    send(["method": "initialized", "params": [:]])
                    send(["method": "account/rateLimits/read", "id": 1])
                } else if id == 1 {
                    let result = object["result"] as? [String: Any]
                    snapshot = parse(result)
                    semaphore.signal()
                }
            }
        }
        send(["method": "initialize", "id": 0, "params": ["clientInfo": ["name": "enterm", "title": "Enterm", "version": EntermVersion.current]]])
        _ = semaphore.wait(timeout: .now() + 8)
        output.fileHandleForReading.readabilityHandler = nil
        return snapshot
    }

    static func parse(_ result: [String: Any]?) -> LimitSnapshot? {
        guard let limits = result?["rateLimits"] as? [String: Any] else { return nil }
        var five: LimitWindow?
        var week: LimitWindow?
        for key in ["primary", "secondary"] {
            guard let window = limits[key] as? [String: Any], let used = (window["usedPercent"] as? NSNumber)?.doubleValue else { continue }
            let resets = (window["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let value = LimitWindow(usedPercent: used, resetsAt: resets)
            if ((window["windowDurationMins"] as? NSNumber)?.intValue ?? 0) >= 1440 { week = value } else { five = value }
        }
        guard five != nil || week != nil else { return nil }
        return LimitSnapshot(fiveHour: five, sevenDay: week, seenAt: Date())
    }
}
