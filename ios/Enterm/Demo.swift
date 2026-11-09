import EntermCore
import Foundation

/// What someone sees before pairing, and what App Review can open without a Mac.
extension PhoneModel {
    static let demoTerminal = "\u{1b}[32m●\u{1b}[0m Tek kutulu projelerde çerçeveyi kaldırıyorum.\r\n\r\n  Read Workspace.swift\r\n  Edit CanvasView.swift\r\n  \u{1b}[32m+14\u{1b}[0m \u{1b}[31m-6\u{1b}[0m\r\n\r\n✻ Çalışıyor… (42s)\r\n\r\n❯ "

    func startDemo() {
        func session(_ number: UInt32, _ name: String, _ tool: ToolKind, _ folder: String, _ status: SessionStatus, _ activity: String?) -> SessionInfo {
            var info = SessionInfo(id: "demo-\(number)", number: number, name: name, tool: tool, cwd: "/Users/demo/Projeler/\(folder)", status: status, startedAt: Date())
            info.lastActivity = activity
            return info
        }
        var waiting = session(1, "Mağaza", .claude, "magaza", .needsApproval, "git push origin main")
        waiting.pendingApproval = ApprovalRequest(id: "demo-approval", sessionID: "demo-1", tool: "Bash", summary: "git push origin main", category: .pushDeploy, requestedAt: Date())
        var working = session(2, "Web Sitesi", .claude, "site", .running, "Edit Workspace.swift")
        working.model = "Opus 5.5"
        working.effort = "medium"
        beginDemo(sessions: [waiting, working, session(3, "Mobil", .codex, "mobil", .idle, "Testler geçti"), session(4, "Terminal", .terminal, "site", .idle, nil)])
    }

    static func demoAnswer<T: Decodable>(_ call: PhoneCall, as type: T.Type) -> Result<T, PhoneProblem> {
        guard call.name == "options" else { return .failure(PhoneProblem(message: "Bu Bölüm Bilgisayar Bağlanınca Açılır")) }
        let limit = LimitSnapshot(fiveHour: LimitWindow(usedPercent: 27, resetsAt: Date().addingTimeInterval(9000)),
                                  sevenDay: LimitWindow(usedPercent: 41, resetsAt: Date().addingTimeInterval(4 * 86400)), seenAt: Date())
        let options = PhoneOptions(accounts: [PhoneAccount(id: "system-claude", tool: .claude, name: "Bu Bilgisayar", isAPIKey: false, sessions: 2, limit: limit)],
                                   folders: [], notes: [:], plan: ModelPlan())
        guard let data = try? JSONEncoder().encode(options), let value = try? JSONDecoder().decode(T.self, from: data) else {
            return .failure(PhoneProblem(message: "Örnek Veri Okunamadı"))
        }
        return .success(value)
    }
}
