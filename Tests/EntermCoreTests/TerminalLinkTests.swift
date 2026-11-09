@testable import EntermCore
import XCTest

final class TerminalLinkTests: XCTestCase {
    private func target(_ text: String) -> TerminalLink.Target? {
        TerminalLink.target(text, cwd: "/work/app", home: "/Users/a")
    }

    func testWebAddressStaysAnAddress() {
        XCTAssertEqual(target("https://example.com/a?b=1"), .web(URL(string: "https://example.com/a?b=1")!))
    }

    func testHomeAndRelativePathsResolve() {
        XCTAssertEqual(target("~/Projeler/x.md"), .path("/Users/a/Projeler/x.md"))
        XCTAssertEqual(target("scripts/run.sh"), .path("/work/app/scripts/run.sh"))
        XCTAssertEqual(target("./a/../b.txt"), .path("/work/app/b.txt"))
    }

    func testLineNumbersAreNotPartOfThePath() {
        XCTAssertEqual(target("/a/b.swift:12:5"), .path("/a/b.swift"))
    }

    func testOtherSchemesDoNothing() {
        XCTAssertNil(target("ssh://host/x"))
    }

    func testRelativePathNeedsAFolder() {
        XCTAssertNil(TerminalLink.target("a/b.txt", cwd: nil, home: "/Users/a"))
    }

    func testFindsThePathUnderTheClick() {
        let line = "Dosya: build/release-d9f2a54/Enterm.app, açın."
        XCTAssertEqual(TerminalLink.find(in: line, at: 12), "build/release-d9f2a54/Enterm.app")
        XCTAssertNil(TerminalLink.find(in: line, at: 2))
        XCTAssertNil(TerminalLink.find(in: line, at: 43))
    }

    func testFindsAnAddressWithoutClosingPunctuation() {
        let line = "Bakın: https://github.com/enmerasoftware/enterm."
        XCTAssertEqual(TerminalLink.find(in: line, at: 20), "https://github.com/enmerasoftware/enterm")
    }

    func testAddressIsNotReadAsAPath() {
        XCTAssertEqual(TerminalLink.find(in: "x https://a.co/b/c y", at: 12), "https://a.co/b/c")
    }

    func testHomeFolderPathAfterABacktick() {
        XCTAssertEqual(TerminalLink.find(in: "`~/Projeler/Web`", at: 5), "~/Projeler/Web")
    }
}
