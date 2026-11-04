import EntermCore
import Foundation

/// Which programs this Mac can start. The answer comes from the user's own shell,
/// because the app's PATH is not the one the terminal will have.
final class ToolCatalog: ObservableObject {
    static let shared = ToolCatalog()
    @Published private(set) var presence: [ToolKind: ToolPresence] = [:]
    private var running = false
    private var lastRun = Date.distantPast

    /// Reads the shell at most once in a few seconds. It runs outside the main queue.
    func refresh() {
        guard !running, Date().timeIntervalSince(lastRun) > 5 else { return }
        running = true
        lastRun = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let output = Self.readShell()
            DispatchQueue.main.async {
                self?.running = false
                guard let self, let output else { return }
                self.presence = ToolPresence.parse(output, fileExists: { FileManager.default.isExecutableFile(atPath: $0) })
            }
        }
    }

    func isMissing(_ tool: ToolKind) -> Bool { presence[tool] == .missing }

    /// The command that starts a copy the shell cannot find. Only this one command sees the folder.
    func startCommand(_ tool: ToolKind, command: String) -> String {
        guard case .elsewhere(let path)? = presence[tool] else { return command }
        let folder = (path as NSString).deletingLastPathComponent
        return "PATH=\(NotFoundActions.shellQuote(folder)):\"$PATH\" \(command)"
    }

    /// A short note for a menu row.
    func note(_ tool: ToolKind) -> String {
        switch presence[tool] {
        case .missing?: return "Kurulu Değil"
        case .elsewhere(let path)?: return path.hasPrefix("/Applications/") ? "ChatGPT Uygulamasından Açılır" : "PATH Dışından Açılır"
        default: return ""
        }
    }

    /// The label for a picker: a program that is not installed says so before it is chosen.
    func pickerTitle(_ tool: ToolKind) -> String {
        isMissing(tool) ? "\(tool.title) · Kurulu Değil" : tool.title
    }

    private static func readShell() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let shell = environment["ENTERM_SHELL"] ?? environment["SHELL"] ?? "/bin/zsh"
        guard ["zsh", "bash"].contains(URL(fileURLWithPath: shell).lastPathComponent) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", ToolPresence.probeScript]
        process.environment = environment.filter { $0.key != "ENTERM_STARTUP" }
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // A slow or stuck .zshrc must not leave a process behind. Unknown is treated as present.
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
