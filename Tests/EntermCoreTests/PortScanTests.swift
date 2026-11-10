@testable import EntermCore
import XCTest

final class PortScanTests: XCTestCase {
    func testPortsOfTheWholeTreeAndNothingElse() {
        let parents = PortScan.parents("  100     1\n  200   100\n  300   200\n  400     1\n")
        let listening = PortScan.listening("p300\nn*:3000\nn[::1]:3000\np400\nn127.0.0.1:5432\np200\nn127.0.0.1:5173\n")
        XCTAssertEqual(PortScan.ports(root: 100, parents: parents, listening: listening), [3000, 5173])
        XCTAssertEqual(PortScan.ports(root: 400, parents: parents, listening: listening), [5432])
        XCTAssertNil(PortScan.ports(root: 999, parents: parents, listening: listening))
    }

    func testAMalformedLineIsSkipped() {
        XCTAssertEqual(PortScan.listening("pabc\nn*:80\np5\nnno-port\nn*:8080\n"), [5: [8080]])
    }
}
