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
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/enmerasoftware/enterm-library/issues/new?"))
        XCTAssertTrue(url.absoluteString.contains("template=submit-prompt.yml"))
        XCTAssertTrue(url.absoluteString.contains("prompt=do%20it"))
        let item = LibraryEntry(id: "../evil name", kind: .skill, title: "x", summary: "", text: nil)
        XCTAssertEqual(LibraryShare.folderName(for: item), "evil-name")
    }
}
