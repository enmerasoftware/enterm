@testable import EntermCore
import XCTest

final class SessionTitlesTests: XCTestCase {
    func testThePersonsTitleWinsOverTheProgramsAndTheLastOneCounts() {
        let text = """
        {"type":"ai-title","aiTitle":"Eski başlık","sessionId":"a"}
        {"type":"user","message":"merhaba"}
        {"type":"ai-title","aiTitle":"TestFlight gönderimi","sessionId":"a"}
        """
        XCTAssertEqual(SessionTitles.claude(transcript: text), "TestFlight gönderimi")
        XCTAssertEqual(SessionTitles.claude(transcript: text + "\n{\"type\":\"custom-title\",\"customTitle\":\"Searvia\"}"), "Searvia")
        XCTAssertNil(SessionTitles.claude(transcript: "{\"type\":\"user\"}"))
    }

    func testCodexTakesTheLastNameOfThatThread() {
        let index = """
        {"id":"t1","thread_name":"İlk ad","updated_at":"2026-08-18T11:06:10Z"}
        {"id":"t2","thread_name":"Başka","updated_at":"2026-08-18T11:07:10Z"}
        {"id":"t1","thread_name":"GRDB geçişi","updated_at":"2026-08-18T12:06:10Z"}
        """
        XCTAssertEqual(SessionTitles.codex(index: index, thread: "t1"), "GRDB geçişi")
        XCTAssertNil(SessionTitles.codex(index: index, thread: "t9"))
    }

    func testALongTitleIsShortened() {
        XCTAssertEqual(SessionTitles.clean(String(repeating: "a", count: 60))?.count, 48)
    }

    func testLoopsInWords() {
        XCTAssertEqual(LoopText.describe(cron: "*/30 * * * *"), "Her 30 Dk")
        XCTAssertEqual(LoopText.describe(cron: "0 */2 * * *"), "Her 2 Saat")
        XCTAssertEqual(LoopText.describe(cron: "15 9 * * *"), "Her Gün 09:15")
        XCTAssertEqual(LoopText.describe(cron: "0 9 * * 1"), "0 9 * * 1")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(LoopText.from(tool: "ScheduleWakeup", input: ["delaySeconds": 1200], now: now),
                       .some(LoopText.Loop(summary: "Kendi Temposunda · 20 Dk Sonra", next: now.addingTimeInterval(1200))))
        XCTAssertEqual(LoopText.from(tool: "CronDelete", input: [:], now: now), .some(nil))
        XCTAssertNil(LoopText.from(tool: "Bash", input: [:], now: now) as LoopText.Loop??)
    }

    func testNextRunOfAnEveryNMinutesLoop() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 10; parts.hour = 10; parts.minute = 7; parts.second = 30
        let now = Calendar.current.date(from: parts)!
        let next = LoopText.next(cron: "*/5 * * * *", after: now)!
        XCTAssertEqual(Calendar.current.component(.minute, from: next), 10)
        XCTAssertEqual(Calendar.current.component(.second, from: next), 0)
    }
}
