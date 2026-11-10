@testable import EntermCore
import XCTest

final class SkillPacksTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("skillpacks-\(UUID().uuidString)", isDirectory: true)
        try makePack("video", skills: ["subtitles": "Add subtitles. Use when asked."])
        try makePack("code", skills: ["debug": "\"Find the cause: then fix.\"", "review": "Review a diff."])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makePack(_ name: String, skills: [String: String]) throws {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        try #"{"name":"\#(name)","description":"\#(name) pack"}"#.write(to: folder.appendingPathComponent(".claude-plugin/plugin.json"), atomically: true, encoding: .utf8)
        for (skill, description) in skills {
            let dir = folder.appendingPathComponent("skills/\(skill)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\nname: \(skill)\ndescription: \(description)\n---\n\n# Body\nname: not this\n".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
    }

    func testPacksAreReadInTheirOrderWithTheirSkills() {
        let packs = SkillPack.packs(in: root)
        XCTAssertEqual(packs.map(\.id), ["code", "video"])
        XCTAssertEqual(packs[0].skills.map(\.name), ["debug", "review"])
        XCTAssertEqual(packs[0].skills[0].description, "Find the cause: then fix.")
        XCTAssertEqual(packs[1].skills[0].command(pack: "video"), "/video:subtitles")
    }

    func testOnlyTheFrontMatterCounts() {
        XCTAssertEqual(SkillPack.frontMatter("---\nname: a\n---\nname: b\n")["name"], "a")
        XCTAssertTrue(SkillPack.frontMatter("name: a\n").isEmpty)
    }

    func testOnlyPacksThatAreOnBecomeArguments() {
        let arguments = SkillPack.pluginArguments(enabled: ["video", "gone"], root: root)
        XCTAssertEqual(arguments, ["--plugin-dir", root.appendingPathComponent("video", isDirectory: true).path])
        XCTAssertEqual(SkillPack.pluginArguments(enabled: [], root: root), [])
        XCTAssertEqual(SkillPack.pluginArguments(enabled: ["video"], root: nil), [])
    }

    func testANamedFolderWins() {
        XCTAssertEqual(SkillPack.root(executable: "/nowhere/enterm", environment: ["ENTERM_SKILLS_DIR": root.path])?.path, root.path)
        XCTAssertNil(SkillPack.root(executable: "/nowhere/enterm", environment: [:]))
    }
}
