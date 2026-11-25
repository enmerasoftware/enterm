import XCTest
@testable import EntermCore

final class LibraryTests: XCTestCase {
    let sample = """
    {"version":1,"generated":"2026-11-25","items":[
     {"id":"review-branch","kind":"prompt","title":"Review this branch","summary":"A senior review.","title_tr":"Bu dalı incele","summary_tr":null,"text":"Review the diff.","test":null,"programs":["claude","codex"],"tags":["review"],"author":"enmerasoftware","path":"prompts/review-branch.md","skill":null,"votes":3},
     {"id":"flaky","kind":"race","title":"Fix flaky tests","summary":"Make them pass.","text":"Fix them.","test":"npm test","programs":[],"tags":["testing"],"author":"a","path":"prompts/flaky.md","skill":null,"votes":9},
     {"id":"ai-design-check","kind":"skill","title":"AI design check","summary":"Rules and a fix skill.","text":null,"programs":["claude"],"tags":["design"],"author":"enmerasoftware","path":null,"skill":{"repo":"enmerasoftware/ai-design-check","path":"plugin","ref":"main"},"votes":0},
     {"id":"future","kind":"workflow","title":"A kind this version does not know"},
     {"id":"broken","kind":"prompt"}
    ]}
    """

    func testParseKeepsGoodItemsAndDropsUnknown() {
        let index = LibraryIndex.parse(Data(sample.utf8))
        XCTAssertEqual(index?.items.map(\.id), ["review-branch", "flaky", "ai-design-check"])
        XCTAssertEqual(index?.items[0].title(turkish: true), "Bu dalı incele")
        XCTAssertEqual(index?.items[0].summary(turkish: true), "A senior review.")
        XCTAssertEqual(index?.items[2].webURL?.absoluteString, "https://github.com/enmerasoftware/ai-design-check/tree/main/plugin")
        XCTAssertNil(LibraryIndex.parse(Data("not json".utf8)))
    }

    func testFilter() throws {
        let index = try XCTUnwrap(LibraryIndex.parse(Data(sample.utf8)))
        XCTAssertEqual(index.filter(query: "").map(\.id), ["flaky", "review-branch", "ai-design-check"])
        XCTAssertEqual(index.filter(query: "dalı").map(\.id), ["review-branch"])
        XCTAssertEqual(index.filter(query: "", kind: .race).map(\.id), ["flaky"])
        XCTAssertEqual(index.filter(query: "", tag: "design").map(\.id), ["ai-design-check"])
        // An item for every program shows for any program.
        XCTAssertEqual(index.filter(query: "", program: "gemini").map(\.id), ["flaky"])
        XCTAssertEqual(index.filter(query: "", saved: ["review-branch"]).map(\.id), ["review-branch"])
        XCTAssertEqual(index.tags.first, "design")
    }

    func testShelfAndShare() throws {
        var shelf = LibraryShelf()
        shelf.toggle("a"); shelf.toggle("b"); shelf.toggle("a")
        XCTAssertEqual(shelf.saved, ["b"])
        let url = try XCTUnwrap(LibraryShare.issueURL(title: "T", summary: "S", text: "do it", kind: .prompt, programs: ["claude"]))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/enmerasoftware/enterm/issues/new?"))
        XCTAssertTrue(url.absoluteString.contains("template=submit-prompt.yml"))
        XCTAssertTrue(url.absoluteString.contains("prompt=do%20it"))
        let item = LibraryEntry(id: "../evil name", kind: .skill, title: "x", summary: "", text: nil)
        XCTAssertEqual(LibraryShare.folderName(for: item), "evil-name")
    }

    func testCommunityItemsParseAndKeepOnlyWhatTheShelfAllows() throws {
        let json = """
        {"items":[
          {"id":"c-0a1b2c3d","kind":"race","title":"Fix the flaky test","summary":"Makes the flaky test pass every time.","text":"Find why ${test:the login test} fails one run in ten and fix the cause.","test":"npm test","programs":["claude","codex"],"tags":["testing"],"author":"Ada","lang":"en","created":"2026-11-25T10:00:00Z","reviewed":false,"votes":4},
          {"id":"c-ffffffff","kind":"prompt","title":"Reviewed","summary":"s","text":"t","reviewed":true},
          {"id":"review-a-diff","kind":"prompt","title":"Not community","text":"t"},
          {"id":"c-12345678","kind":"skill","title":"No skills here","text":"t"}
        ]}
        """
        let items = try XCTUnwrap(CommunityLibrary.parse(Data(json.utf8)))
        XCTAssertEqual(items.map(\.id), ["c-0a1b2c3d", "c-ffffffff"])
        XCTAssertTrue(items[0].isCommunity && !items[0].isReviewedCommunity)
        XCTAssertTrue(items[1].isReviewedCommunity)
        XCTAssertEqual(items[0].test, "npm test")
        XCTAssertEqual(items[0].votes, 4)
        XCTAssertTrue(items[0].webURL?.absoluteString.hasSuffix("/library#c-0a1b2c3d") ?? false)
        XCTAssertEqual(CommunityLibrary.parseVotes(Data(#"{"votes":{"a":2}}"#.utf8)), ["a": 2])
    }

    func testSubmissionProblems() {
        let text = String(repeating: "Review the diff and list correctness bugs. ", count: 3)
        func make(_ kind: LibraryEntry.Kind = .prompt, title: String = "Review the diff", test: String? = nil, programs: [String] = ["claude"]) -> CommunityLibrary.Submission {
            CommunityLibrary.Submission(kind: kind, title: title, summary: "Finds bugs in the diff.", text: text, test: test, programs: programs, tags: [], author: "", lang: "en", device: "x")
        }
        XCTAssertNil(make().problem)
        XCTAssertNotNil(make(title: "  ").problem)
        XCTAssertNotNil(make(programs: []).problem)
        XCTAssertNotNil(make(.race, programs: ["claude", "codex"]).problem, "a race needs a test")
        XCTAssertNotNil(make(.race, test: "npm test", programs: ["claude", "cursor"]).problem, "a race needs two racing programs")
        XCTAssertNil(make(.race, test: "npm test", programs: ["claude", "codex"]).problem)
        XCTAssertNil(make(test: "   ").test)
    }

    func testPromptVariables() {
        let text = "Fix ${bug} in ${file:main.swift}, then test ${bug}. Keep ${not closed"
        XCTAssertEqual(PromptVariables.find(in: text), [.init(name: "bug", fallback: ""), .init(name: "file", fallback: "main.swift")])
        XCTAssertEqual(PromptVariables.fill(text, with: ["bug": "the crash"]), "Fix the crash in main.swift, then test the crash. Keep ${not closed")
        XCTAssertEqual(PromptVariables.fill("Hi ${name}", with: [:]), "Hi ${name}")
        XCTAssertEqual(PromptVariables.fill("Cost: $5 and ${x:1}", with: [:]), "Cost: $5 and 1")
    }

    func testShelfKeepsSavedCommunityItemsAndReadsOldFiles() throws {
        var shelf = LibraryShelf()
        let item = LibraryEntry(id: "c-00000001", kind: .prompt, title: "T", summary: "S", text: "x", source: CommunityLibrary.source)
        shelf.toggle(item)
        XCTAssertEqual(shelf.kept.map(\.id), ["c-00000001"])
        shelf.toggle(item)
        XCTAssertTrue(shelf.kept.isEmpty && shelf.saved.isEmpty)
        let old = try JSONDecoder().decode(LibraryShelf.self, from: Data(#"{"saved":["a"],"installedSkills":{}}"#.utf8))
        XCTAssertEqual(old.saved, ["a"])
        XCTAssertTrue(old.liked.isEmpty && old.mine.isEmpty)
    }
}
