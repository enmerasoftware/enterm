@testable import EntermCore
import XCTest

final class TitleBarDoubleClickTests: XCTestCase {
    func testByDefaultADoubleClickFillsTheScreen() {
        XCTAssertEqual(TitleBarDoubleClick.action(setting: nil, legacyMinimize: false), .zoom)
        XCTAssertEqual(TitleBarDoubleClick.action(setting: "Maximize", legacyMinimize: false), .zoom)
        XCTAssertEqual(TitleBarDoubleClick.action(setting: "Fill", legacyMinimize: false), .zoom)
    }

    func testTheSystemSettingIsFollowed() {
        XCTAssertEqual(TitleBarDoubleClick.action(setting: "Minimize", legacyMinimize: false), .minimize)
        XCTAssertEqual(TitleBarDoubleClick.action(setting: "None", legacyMinimize: false), .none)
    }

    func testTheOldMinimizeSwitchStillCounts() {
        XCTAssertEqual(TitleBarDoubleClick.action(setting: nil, legacyMinimize: true), .minimize)
    }
}
