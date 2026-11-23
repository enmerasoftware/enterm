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
        var waiting = session(1, L("Mağaza"), .claude, "magaza", .needsApproval, "git push origin main")
        waiting.pendingApproval = ApprovalRequest(id: "demo-approval", sessionID: "demo-1", tool: "Bash", summary: "git push origin main", category: .pushDeploy, requestedAt: Date())
        var working = session(2, L("Web Sitesi"), .claude, "site", .running, "Edit Workspace.swift")
        working.model = "Opus 5.5"
        working.effort = "medium"
        beginDemo(sessions: [waiting, working, session(3, L("Mobil"), .codex, "mobil", .idle, L("Testler geçti")), session(4, "Terminal", .terminal, "site", .idle, nil)])
    }

    static func demoAnswer<T: Decodable>(_ call: PhoneCall, as type: T.Type) -> Result<T, PhoneProblem> {
        if call.name == "races" {
            // One race just finished, so the demo shows medals and the winner button.
            var race = Race(task: L("Giriş sayfasına şifre sıfırlama ekle"), root: "/Users/demo/Projeler/magaza", base: "a1b2c3d", testCommand: "swift test")
            var first = RaceEntrant(tool: "codex", title: "Codex", branch: "yaris/sifre-codex", folder: "")
            first.startedAt = Date().addingTimeInterval(-260)
            first.finishedAt = Date().addingTimeInterval(-40)
            first.stat = DiffStat(files: 4, insertions: 132, deletions: 9)
            first.tests = .passed
            var second = RaceEntrant(tool: "claude", title: "Claude Code", branch: "yaris/sifre-claude", folder: "")
            second.startedAt = first.startedAt
            second.finishedAt = Date().addingTimeInterval(-12)
            second.stat = DiffStat(files: 6, insertions: 188, deletions: 21)
            second.tests = .passed
            race.entrants = [second, first]
            guard let data = try? JSONEncoder().encode([race]), let value = try? JSONDecoder().decode(T.self, from: data) else {
                return .failure(PhoneProblem(message: "Örnek Veri Okunamadı"))
            }
            return .success(value)
        }
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
