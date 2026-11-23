import XCTest
@testable import EntermCore

final class TimelineTests: XCTestCase {
    func testClaudeTranscript() {
        let text = """
        {"type":"user","timestamp":"2026-11-23T10:00:00.000Z","message":{"role":"user","content":"Add a login page"}}
        {"type":"assistant","timestamp":"2026-11-23T10:00:05.000Z","message":{"content":[{"type":"text","text":"On it."},{"type":"tool_use","name":"Read","input":{"file_path":"/p/App.swift"}}]}}
        {"type":"assistant","timestamp":"2026-11-23T10:00:09.500Z","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/p/Login.swift","content":"x"}}]}}
        {"type":"assistant","timestamp":"2026-11-23T10:05:00Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test\\necho done"}}]}}
        {"type":"user","timestamp":"2026-11-23T10:05:01Z","isMeta":true,"message":{"content":"<meta>"}}
        not json
        """
        let timeline = Timeline.parse(text)
        XCTAssertEqual(timeline.events.map(\.kind), [.prompt, .reply, .read, .edit, .command])
        XCTAssertEqual(timeline.events[3].file, "/p/Login.swift")
        XCTAssertEqual(timeline.events[4].text, "swift test")
        XCTAssertEqual(timeline.files, ["/p/Login.swift"])
        // The 4.5 minute pause counts as 20 seconds.
        XCTAssertEqual(timeline.compressed(), [0, 5, 5, 9.5, 29.5])
    }

    func testCodexTranscript() {
        let text = """
        {"timestamp":"2026-11-23T10:00:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Fix the bug"}]}}
        {"timestamp":"2026-11-23T10:00:02.000Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\\"command\\":[\\"bash\\",\\"-lc\\",\\"rg TODO\\"]}"}}
        {"timestamp":"2026-11-23T10:00:04.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch\\n*** Update File: src/a.rs\\n*** Add File: src/b.rs\\n*** End Patch"}}
        """
        let timeline = Timeline.parse(text)
        XCTAssertEqual(timeline.events.map(\.kind), [.prompt, .command, .edit, .edit])
        XCTAssertEqual(timeline.events[1].text, "rg TODO")
        XCTAssertEqual(timeline.files, ["src/a.rs", "src/b.rs"])
    }
}
