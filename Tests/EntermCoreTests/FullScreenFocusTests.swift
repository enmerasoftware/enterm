@testable import EntermCore
import XCTest

final class FullScreenFocusTests: XCTestCase {
    func testPickingAnotherSessionInFullScreenShowsIt() {
        XCTAssertEqual(FullScreenFocus.shown(current: 4, focusing: 1, visible: [1, 4]), 1)
    }

    func testWithoutFullScreenNothingIsForcedOnScreen() {
        XCTAssertNil(FullScreenFocus.shown(current: nil, focusing: 1, visible: [1, 4]))
    }

    func testASessionFromAnotherTabDoesNotReplaceTheFullScreenBox() {
        XCTAssertEqual(FullScreenFocus.shown(current: 4, focusing: 9, visible: [1, 4]), 4)
    }

    func testClearingFocusKeepsTheFullScreenBox() {
        XCTAssertEqual(FullScreenFocus.shown(current: 4, focusing: nil, visible: [1, 4]), 4)
    }
}
