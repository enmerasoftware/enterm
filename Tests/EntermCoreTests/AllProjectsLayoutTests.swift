import CoreGraphics
@testable import EntermCore
import XCTest

final class AllProjectsLayoutTests: XCTestCase {
    let area = CGSize(width: 1200, height: 760)

    private func checkTidy(_ clusters: [AllProjectsLayout.Cluster], file: StaticString = #filePath, line: UInt = #line) {
        let bounds = CGRect(origin: .zero, size: area)
        let boxes = clusters.flatMap(\.boxes)
        for cluster in clusters {
            XCTAssertTrue(bounds.contains(cluster.frame), "\(cluster.name) leaves the window", file: file, line: line)
            for box in cluster.boxes {
                XCTAssertTrue(cluster.frame.contains(box), "a box of \(cluster.name) leaves its frame", file: file, line: line)
            }
            for other in clusters where other.name != cluster.name {
                XCTAssertFalse(cluster.frame.intersects(other.frame), "\(cluster.name) covers \(other.name)", file: file, line: line)
            }
        }
        for (i, a) in boxes.enumerated() {
            for b in boxes[(i + 1)...] { XCTAssertFalse(a.intersects(b), "boxes overlap", file: file, line: line) }
        }
    }

    func testTwoAreasStandSideBySideInTheirOrder() {
        let clusters = AllProjectsLayout.clusters([("enmera", 1), ("ps5-altyazi", 1)], in: area)
        XCTAssertEqual(clusters.map(\.name), ["enmera", "ps5-altyazi"])
        XCTAssertLessThan(clusters[0].frame.maxX, clusters[1].frame.minX)
        XCTAssertEqual(clusters[0].boxes[0].size, clusters[1].boxes[0].size)
        checkTidy(clusters)
    }

    func testThreeBoxesOfOneAreaShareTwoColumns() {
        let clusters = AllProjectsLayout.clusters([("enmera", 3), ("ps5-altyazi", 1)], in: area)
        let xs = Set(clusters[0].boxes.map(\.minX))
        XCTAssertEqual(xs.count, 2)
        checkTidy(clusters)
    }

    func testManyAreasWrapInsteadOfGettingThin() {
        let clusters = AllProjectsLayout.clusters((1...6).map { ("alan\($0)", 1) }, in: area)
        XCTAssertEqual(clusters.count, 6)
        let box = clusters[0].boxes[0]
        XCTAssertGreaterThan(box.width, box.height * 0.8)
        checkTidy(clusters)
    }

    func testMixedAreasNeverOverlap() {
        for counts in [[1, 2, 3], [4, 1], [2, 2, 2, 2], [6, 1, 1], [1, 1, 1, 1, 1, 1, 1, 1, 1]] {
            checkTidy(AllProjectsLayout.clusters(counts.enumerated().map { ("p\($0.offset)", $0.element) }, in: area))
        }
    }

    func testAnAreaWithNothingOpenIsLeftOut() {
        XCTAssertEqual(AllProjectsLayout.clusters([("bos", 0), ("enmera", 1)], in: area).map(\.name), ["enmera"])
    }
}
