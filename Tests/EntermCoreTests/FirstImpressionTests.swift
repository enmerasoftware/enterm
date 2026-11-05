import CoreGraphics
@testable import EntermCore
import XCTest

final class FirstImpressionTests: XCTestCase {
    // MARK: Home command line

    private func parse(_ text: String) -> HomeIntent {
        HomeInput.parse(text, home: "/Users/a", isDirectory: { $0 == "/Users/a/iş" || $0 == "/tmp" })
    }

    func testEmptyLineOpensTheDefaultProgram() {
        XCTAssertEqual(parse(""), .open)
        XCTAssertEqual(parse("   "), .open)
    }

    func testAnExistingFolderOpensThere() {
        XCTAssertEqual(parse("~/iş"), .folder("/Users/a/iş"))
        XCTAssertEqual(parse("/tmp"), .folder("/tmp"))
        XCTAssertEqual(parse("  /tmp  "), .folder("/tmp"))
    }

    func testAnythingElseIsACommand() {
        XCTAssertEqual(parse("git status"), .command("git status"))
        XCTAssertEqual(parse("~/yok"), .command("~/yok"))
        XCTAssertEqual(parse("claude"), .command("claude"))
    }

    // MARK: Links

    func testALinkLeavesTheFacingSides() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 300, y: 200, width: 100, height: 100)
        let forward = LinkRoute.points(from: a, to: b)
        XCTAssertEqual(forward.first, CGPoint(x: 100, y: 50))
        XCTAssertEqual(forward.last, CGPoint(x: 300, y: 250))
        let backward = LinkRoute.points(from: b, to: a)
        XCTAssertEqual(backward.first, CGPoint(x: 300, y: 250))
        XCTAssertEqual(backward.last, CGPoint(x: 100, y: 50))
    }

    func testEveryLinkSegmentIsStraight() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        for b in [CGRect(x: 300, y: 200, width: 100, height: 100), CGRect(x: 40, y: 300, width: 100, height: 100), CGRect(x: -300, y: -80, width: 100, height: 100)] {
            let points = LinkRoute.points(from: a, to: b)
            for (p, q) in zip(points, points.dropFirst()) {
                XCTAssertTrue(p.x == q.x || p.y == q.y, "\(p) -> \(q)")
            }
        }
    }

    func testALevelLinkIsOneLine() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 300, y: 0, width: 100, height: 100)
        XCTAssertEqual(LinkRoute.points(from: a, to: b).count, 2)
    }

    func testOverlappingBoxesStillRouteAround() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 40, y: 300, width: 100, height: 100)
        let points = LinkRoute.points(from: a, to: b)
        XCTAssertGreaterThan(points.count, 3)
        XCTAssertEqual(points.first, CGPoint(x: 100, y: 50))
        XCTAssertEqual(points.last, CGPoint(x: 40, y: 350))
    }

    func testDistanceToARoute() {
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]
        XCTAssertEqual(LinkRoute.distance(from: CGPoint(x: 50, y: 10), to: route), 10, accuracy: 0.01)
        XCTAssertEqual(LinkRoute.distance(from: CGPoint(x: 120, y: 50), to: route), 20, accuracy: 0.01)
    }

    // MARK: Rail

    func testWhoNeedsYouComesFirstAndTheRestStayInOrder() {
        let order = RailOrder.sorted([
            (1, SessionStatus.idle), (2, .running), (3, .needsApproval), (4, .idle), (5, .limitReached), (6, .failed),
        ], status: { $0.1 })
        XCTAssertEqual(order.map(\.0), [3, 5, 6, 2, 1, 4])
    }

    // MARK: Motion

    func testMotionStopsForEveryReasonToBeStill() {
        XCTAssertTrue(MotionPolicy.allowed(setting: true, reduceMotion: false, lowPower: false, windowVisible: true))
        XCTAssertFalse(MotionPolicy.allowed(setting: false, reduceMotion: false, lowPower: false, windowVisible: true))
        XCTAssertFalse(MotionPolicy.allowed(setting: true, reduceMotion: true, lowPower: false, windowVisible: true))
        XCTAssertFalse(MotionPolicy.allowed(setting: true, reduceMotion: false, lowPower: true, windowVisible: true))
        XCTAssertFalse(MotionPolicy.allowed(setting: true, reduceMotion: false, lowPower: false, windowVisible: false))
    }

    func testOnlyANewAttentionStateSweepsTheBox() {
        XCTAssertTrue(MotionPolicy.sweeps(from: .running, to: .needsApproval))
        XCTAssertTrue(MotionPolicy.sweeps(from: .idle, to: .limitReached))
        XCTAssertFalse(MotionPolicy.sweeps(from: .needsApproval, to: .needsApproval))
        XCTAssertFalse(MotionPolicy.sweeps(from: .idle, to: .running))
        XCTAssertFalse(MotionPolicy.sweeps(from: nil, to: .needsApproval))
    }

    // MARK: Recent conversations

    func testATranscriptGivesItsTitleAndFolder() {
        let lines = """
        {"type":"mode","sessionId":"abc"}
        {"type":"user","cwd":"/Users/a/iş","sessionId":"abc","message":{"content":"Testleri düzelt"}}
        {"type":"ai-title","aiTitle":"Test düzeltmesi","sessionId":"abc"}
        """
        let found = RecentConversation.parse(text: lines, id: "abc", modified: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(found, RecentConversation(id: "abc", title: "Test düzeltmesi", folder: "/Users/a/iş", modified: Date(timeIntervalSince1970: 5)))
    }

    func testTheLastTitleWinsAndACustomTitleBeatsIt() {
        let lines = """
        {"type":"ai-title","aiTitle":"Eski","sessionId":"abc","cwd":"/x"}
        {"type":"ai-title","aiTitle":"Yeni","sessionId":"abc"}
        """
        XCTAssertEqual(RecentConversation.parse(text: lines, id: "abc", modified: .distantPast)?.title, "Yeni")
        let named = lines + "\n{\"type\":\"custom-title\",\"customTitle\":\"Benim Adım\"}"
        XCTAssertEqual(RecentConversation.parse(text: named, id: "abc", modified: .distantPast)?.title, "Benim Adım")
    }

    func testABrokenOrFolderlessTranscriptIsLeftOut() {
        XCTAssertNil(RecentConversation.parse(text: "{bozuk\n", id: "abc", modified: .distantPast))
        XCTAssertNil(RecentConversation.parse(text: "{\"type\":\"ai-title\",\"aiTitle\":\"X\"}", id: "abc", modified: .distantPast))
    }

    func testNoTitleFallsBackToTheFirstPrompt() {
        let lines = "{\"type\":\"user\",\"cwd\":\"/x\",\"message\":{\"content\":\"Merhaba\\nikinci satır\"}}"
        XCTAssertEqual(RecentConversation.parse(text: lines, id: "abc", modified: .distantPast)?.title, "Merhaba")
    }

    func testGroupsKeepTheNewestFolderFirst() {
        func item(_ id: String, _ folder: String, _ time: TimeInterval) -> RecentConversation {
            RecentConversation(id: id, title: id, folder: folder, modified: Date(timeIntervalSince1970: time))
        }
        let groups = RecentConversation.grouped([item("a", "/eski", 1), item("b", "/yeni", 9), item("c", "/eski", 5), item("d", "/yeni", 7)], limit: 3)
        XCTAssertEqual(groups.map(\.folder), ["/yeni", "/eski"])
        XCTAssertEqual(groups[0].items.map(\.id), ["b", "d"])
        XCTAssertEqual(groups[1].items.map(\.id), ["c"])
    }

    func testScanReadsOnlyTheEndsOfALongFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("proje")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var text = "{\"type\":\"user\",\"cwd\":\"/x\",\"message\":{\"content\":\"Başlangıç\"}}\n"
        text += String(repeating: "{\"type\":\"assistant\",\"pad\":\"\(String(repeating: "a", count: 200))\"}\n", count: 2000)
        text += "{\"type\":\"ai-title\",\"aiTitle\":\"Sondaki Başlık\"}\n"
        try text.write(to: folder.appendingPathComponent("abc.jsonl"), atomically: true, encoding: .utf8)
        let found = RecentConversation.scan(projects: root)
        XCTAssertEqual(found.map(\.title), ["Sondaki Başlık"])
        XCTAssertEqual(found.first?.folder, "/x")
        XCTAssertEqual(found.first?.id, "abc")
    }

    // MARK: Settings

    func testNewSettingsSurviveASave() throws {
        var settings = AppSettings()
        settings.seenWelcome = true
        settings.neon = "strong"
        settings.motion = false
        settings.defaultProgram = "claude"
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(back.seenWelcome)
        XCTAssertEqual(back.neon, "strong")
        XCTAssertFalse(back.motion)
        XCTAssertEqual(back.defaultProgram, "claude")
    }

    func testOldSettingsGetTheNewDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{\"theme\":\"light\"}".utf8))
        XCTAssertEqual(settings.theme, "light")
        XCTAssertFalse(settings.seenWelcome)
        XCTAssertEqual(settings.neon, "soft")
        XCTAssertTrue(settings.motion)
        XCTAssertEqual(settings.defaultProgram, "terminal")
    }
}
