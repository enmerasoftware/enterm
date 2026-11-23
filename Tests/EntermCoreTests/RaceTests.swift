import XCTest
@testable import EntermCore

final class RaceTests: XCTestCase {
    func testShortstat() {
        XCTAssertEqual(DiffStat.parse(" 3 files changed, 40 insertions(+), 2 deletions(-)\n"), DiffStat(files: 3, insertions: 40, deletions: 2))
        XCTAssertEqual(DiffStat.parse(" 1 file changed, 1 insertion(+)"), DiffStat(files: 1, insertions: 1, deletions: 0))
        XCTAssertEqual(DiffStat.parse(""), DiffStat())
    }

    func testSlugAndBranch() {
        XCTAssertEqual(RacePlan.slug("Kupon iadesini düzelt!"), "kupon-iadesini-duzelt")
        XCTAssertEqual(RacePlan.slug("   "), "gorev")
        XCTAssertLessThanOrEqual(RacePlan.slug(String(repeating: "uzun kelime ", count: 10)).count, 28)
        XCTAssertEqual(RacePlan.branch(task: "Giriş sayfası", tool: "claude", taken: []), "yaris/giris-sayfasi-claude")
        XCTAssertEqual(RacePlan.branch(task: "Giriş sayfası", tool: "claude", taken: ["yaris/giris-sayfasi-claude"]), "yaris/giris-sayfasi-claude-2")
        XCTAssertEqual(RacePlan.folder(root: "/p/app", branch: "yaris/x-codex"), "/p/app.worktrees/yaris-x-codex")
    }

    func testTestCommand() {
        XCTAssertEqual(RacePlan.testCommand(files: ["Package.swift"]), "swift test")
        XCTAssertEqual(RacePlan.testCommand(files: ["package.json", "pnpm-lock.yaml"]), "pnpm test")
        XCTAssertNil(RacePlan.testCommand(files: ["README.md"]))
    }

    func testStandingsAndProgress() {
        var race = Race(task: "t", root: "/r", base: "abc", testCommand: nil)
        race.entrants = [
            RaceEntrant(tool: "claude", title: "Claude Code", branch: "a", folder: "/a"),
            RaceEntrant(tool: "codex", title: "Codex", branch: "b", folder: "/b"),
            RaceEntrant(tool: "gemini", title: "Gemini", branch: "c", folder: "/c"),
        ]
        let now = Date()
        race.entrants[1].finishedAt = now
        race.entrants[2].finishedAt = now.addingTimeInterval(-5)
        race.entrants[0].stat = DiffStat(files: 1, insertions: 10, deletions: 0)
        XCTAssertEqual(race.standings.map(\.branch), ["c", "b", "a"])
        XCTAssertEqual(race.place(of: "c"), 1)
        XCTAssertNil(race.place(of: "a"))
        XCTAssertEqual(race.progress(of: "b"), 1)
        XCTAssertEqual(race.progress(of: "a"), 0.9, accuracy: 0.001)
        XCTAssertFalse(race.isFinished)
    }
}
