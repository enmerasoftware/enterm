@testable import EntermCore
import XCTest

final class ProjectPlacementTests: XCTestCase {
    let home = "/Users/a"

    func testASessionInAnotherFolderGetsItsOwnTab() {
        let name = ProjectPlacement.project(folder: "/Users/a/Web/ps5-altyazi", home: home, active: "enmera", activeFolders: ["/Users/a/Web/enmera"], startingFromHome: false)
        XCTAssertEqual(name, "ps5-altyazi")
    }

    func testASessionInTheSameFolderOrBelowStaysInTheTab() {
        XCTAssertEqual(ProjectPlacement.project(folder: "/Users/a/Web/enmera", home: home, active: "enmera", activeFolders: ["/Users/a/Web/enmera"], startingFromHome: false), "enmera")
        XCTAssertEqual(ProjectPlacement.project(folder: "/Users/a/Web/enmera/ekip", home: home, active: "enmera", activeFolders: ["/Users/a/Web/enmera"], startingFromHome: false), "enmera")
    }

    func testAPlainTerminalAtHomeJoinsTheTabOnScreen() {
        XCTAssertEqual(ProjectPlacement.project(folder: home, home: home, active: "enmera", activeFolders: ["/Users/a/Web/enmera"], startingFromHome: false), "enmera")
    }

    func testAHomeTabDoesNotSwallowEveryFolder() {
        let name = ProjectPlacement.project(folder: "/Users/a/Web/enterm", home: home, active: "Ana Klasör", activeFolders: [home], startingFromHome: false)
        XCTAssertEqual(name, "enterm")
    }

    func testStartingFromHomeAlwaysNamesTheFolder() {
        XCTAssertEqual(ProjectPlacement.project(folder: "/Users/a/Web/enmera/ekip", home: home, active: "enmera", activeFolders: ["/Users/a/Web/enmera"], startingFromHome: true), "ekip")
        XCTAssertEqual(ProjectPlacement.project(folder: home, home: home, active: nil, activeFolders: [], startingFromHome: false), "Ana Klasör")
    }
}
