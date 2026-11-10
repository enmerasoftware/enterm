@testable import EntermCore
import XCTest

final class EntermURLTests: XCTestCase {
    func testOpenNeedsAPath() {
        XCTAssertEqual(EntermURL.parse(URL(string: "enterm://open?path=~/a%20b&program=codex&task=testleri%20yaz")!),
                       .open(path: "~/a b", program: "codex", name: nil, task: "testleri yaz"))
        XCTAssertNil(EntermURL.parse(URL(string: "enterm://open?program=claude")!))
    }

    func testOtherAddresses() {
        XCTAssertEqual(EntermURL.parse(URL(string: "enterm://session/Arayüz")!), .session("Arayüz"))
        XCTAssertEqual(EntermURL.parse(URL(string: "enterm://settings/skills")!), .settings("skills"))
        XCTAssertEqual(EntermURL.parse(URL(string: "enterm://board")!), .page("board"))
        XCTAssertNil(EntermURL.parse(URL(string: "https://open?path=/")!))
        XCTAssertNil(EntermURL.parse(URL(string: "enterm://delete")!))
    }
}
