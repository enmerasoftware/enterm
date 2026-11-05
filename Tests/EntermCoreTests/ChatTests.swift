import XCTest
@testable import EntermCore

final class ChatTests: XCTestCase {
    func testClaudeTranscriptSkipsWhatThePersonDidNotSee() {
        var parser = ChatParser()
        parser.feed("""
        {"type":"user","message":{"content":"Merhaba"}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"Buyurun"},{"type":"tool_use","name":"Bash","input":{"command":"ls -la\\npwd"}}]}}
        {"type":"user","isMeta":true,"message":{"content":"gizli"}}
        {"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"alt ajan"}]}}
        {"type":"user","message":{"content":"<system-reminder>içerik</system-reminder>"}}
        bozuk satır
        """)
        XCTAssertEqual(parser.items.map(\.role), [.user, .assistant, .tool])
        XCTAssertEqual(parser.items.map(\.text), ["Merhaba", "Buyurun", "Bash ls -la"])
    }

    func testCodexTranscript() {
        var parser = ChatParser()
        parser.feed("""
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"text":"Soru"}]}}
        {"type":"response_item","payload":{"type":"function_call","name":"shell"}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"text":"Yanıt"}]}}
        """)
        XCTAssertEqual(parser.items.map(\.role), [.user, .tool, .assistant])
    }

    func testMarkdownKeepsCodeWhole() {
        let blocks = MarkdownBlock.parse("# Başlık\n\nbir\niki\n\n- madde\n1. sıra\n\n```swift\n# yorum\n\n  girinti\n```\nson")
        XCTAssertEqual(blocks, [.heading("Başlık"), .paragraph("bir iki"), .bullet("madde"), .bullet("1. sıra"),
                                .code("# yorum\n\n  girinti"), .paragraph("son")])
    }

    func testAnOpenCodeBlockIsStillShown() {
        XCTAssertEqual(MarkdownBlock.parse("```\nyarım"), [.code("yarım")])
    }

    func testProcessTreeCountsEverythingASessionStarted() {
        let entries = ProcessTree.parse("""
          100     1  1000 /bin/zsh
          200   100  5000 /usr/local/bin/claude
          300   200  2000 node
          400     1  9000 başka program
        """)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[1].name, "claude")
        let total = ProcessTree.total(root: 100, in: entries)
        XCTAssertEqual(total.rssKB, 8000)
        XCTAssertEqual(total.children, 2)
    }

    func testModelNamesReadAsAPersonWouldSayThem() {
        XCTAssertEqual(ModelName.pretty("claude-sonnet-5-5"), "Sonnet 5.5")
        XCTAssertEqual(ModelName.pretty("claude-opus-5-5[1m]"), "Opus 5.5")
        XCTAssertEqual(ModelName.pretty("gpt-5-codex"), "gpt-5-codex")
    }

    func testTheFreeTemplateLeavesTheDecisionToTheProgram() {
        XCTAssertTrue(PermissionBook().card(for: "x").passThrough)
        XCTAssertFalse(PermissionTemplate.development.card.passThrough)
    }

    func testACardFromAnOlderVersionStillReads() throws {
        let data = Data(#"{"modes":{"ssh":"deny"},"rememberedHosts":[],"sshRules":[]}"#.utf8)
        let card = try JSONDecoder().decode(PermissionCard.self, from: data)
        XCTAssertFalse(card.passThrough)
        XCTAssertEqual(card.mode(.ssh), .deny)
    }
}
