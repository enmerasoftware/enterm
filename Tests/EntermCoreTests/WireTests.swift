@testable import EntermCore
import XCTest

final class WireTests: XCTestCase {
    func testFramesSurviveSplitReads() {
        let first = WireFrame.session(.output, number: 7, bytes: Data("merhaba".utf8)).encoded()
        var message = WireMessage(op: "hello")
        message.version = 1
        let second = message.frame().encoded()
        let stream = first + second
        var decoder = WireDecoder()
        var frames: [WireFrame] = []
        for byte in stream {
            frames += decoder.feed(Data([byte]))
        }
        XCTAssertEqual(frames.count, 2)
        let (number, bytes) = frames[0].splitSession()!
        XCTAssertEqual(number, 7)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "merhaba")
        XCTAssertEqual(WireMessage.decode(frames[1].payload)?.op, "hello")
    }

    func testInternetIsAskInEveryTemplate() {
        for template in PermissionTemplate.allCases {
            XCTAssertEqual(template.card.mode(.internet), .ask, template.title)
        }
    }

    func testDevelopmentTemplateMatchesBrief() {
        let card = PermissionTemplate.development.card
        XCTAssertEqual(card.mode(.editFiles), .allow)
        XCTAssertEqual(card.mode(.deleteFiles), .ask)
        XCTAssertEqual(card.mode(.ssh), .deny)
        XCTAssertEqual(card.mode(.pushDeploy), .deny)
    }

    func testCommandClassifier() {
        XCTAssertEqual(PermissionClassifier.classifyCommand("git push origin main").category, .pushDeploy)
        XCTAssertEqual(PermissionClassifier.classifyCommand("ssh deploy@staging uptime").category, .ssh)
        XCTAssertEqual(PermissionClassifier.classifyCommand("rm -rf build").category, .deleteFiles)
        XCTAssertEqual(PermissionClassifier.classifyCommand("curl https://example.com/a").host, "example.com")
        XCTAssertEqual(PermissionClassifier.classifyCommand("ls -la").category, .command)
    }

    func testRememberedHostIsAllowedOnlyForInternet() {
        var book = PermissionBook()
        book.rememberedHosts = ["example.com"]
        XCTAssertEqual(book.decision(sessionID: "a", category: .internet, host: "example.com"), .allow)
        XCTAssertEqual(book.decision(sessionID: "a", category: .internet, host: "other.com"), .ask)
        XCTAssertEqual(book.decision(sessionID: "a", category: .ssh, host: "example.com"), .deny)
    }
}
