import CoreGraphics
import Foundation

/// Every work area on one surface: each area is a labelled frame holding its own boxes, and the
/// frames share the window so that everything is in view at once. Measures run top-down.
public enum AllProjectsLayout {
    public struct Cluster: Equatable {
        public var name: String
        /// Where the outline is drawn. Its label sits on the top line.
        public var frame: CGRect
        public var boxes: [CGRect]
    }

    static let margin: CGFloat = 16
    /// Between two frames, room for the next label too.
    static let between: CGFloat = 24
    static let gap: CGFloat = 12
    static let side: CGFloat = 12
    /// Below the top line: half the label and a little air.
    static let top: CGFloat = 20
    static let bottom: CGFloat = 12

    static func grid(_ count: Int) -> (columns: Int, rows: Int) {
        let columns = count <= 2 ? count : (count <= 4 ? 2 : 3)
        return (columns, Int(ceil(Double(count) / Double(columns))))
    }

    public static func clusters(_ areas: [(name: String, count: Int)], in area: CGSize) -> [Cluster] {
        let areas = areas.filter { $0.count > 0 }
        guard !areas.isEmpty, area.width > 2 * margin, area.height > 2 * margin else { return [] }
        let width = area.width - 2 * margin, height = area.height - 2 * margin

        // Try every number of rows and keep the one that gives the largest boxes.
        var best: (score: CGFloat, rows: [[Int]], box: CGSize)?
        for rowCount in 1...areas.count {
            let perRow = Int(ceil(Double(areas.count) / Double(rowCount)))
            let rows = stride(from: 0, to: areas.count, by: perRow).map { Array($0..<min($0 + perRow, areas.count)) }
            var boxWidth = CGFloat.infinity
            var boxRows = 0, gapRows: CGFloat = 0
            for row in rows {
                let grids = row.map { grid(areas[$0].count) }
                let columns = grids.reduce(0) { $0 + $1.columns }
                let fixed = CGFloat(row.count - 1) * between + CGFloat(row.count) * 2 * side
                    + grids.reduce(0) { $0 + CGFloat($1.columns - 1) * gap }
                boxWidth = min(boxWidth, (width - fixed) / CGFloat(columns))
                let tallest = grids.map(\.rows).max() ?? 1
                boxRows += tallest
                gapRows += CGFloat(tallest - 1) * gap
            }
            let fixedHeight = CGFloat(rows.count - 1) * between + CGFloat(rows.count) * (top + bottom) + gapRows
            let boxHeight = (height - fixedHeight) / CGFloat(boxRows)
            guard boxWidth > 0, boxHeight > 0 else { continue }
            // A terminal reads best wide: a tall box counts only up to 1.6 times its height.
            let score = min(boxWidth, boxHeight * 1.6)
            if best == nil || score > best!.score { best = (score, rows, CGSize(width: boxWidth, height: boxHeight)) }
        }
        guard let best else { return [] }
        let box = best.box

        func size(_ index: Int) -> CGSize {
            let g = grid(areas[index].count)
            return CGSize(width: CGFloat(g.columns) * box.width + CGFloat(g.columns - 1) * gap + 2 * side,
                          height: CGFloat(g.rows) * box.height + CGFloat(g.rows - 1) * gap + top + bottom)
        }
        let rowHeights = best.rows.map { $0.map { size($0).height }.max() ?? 0 }
        let total = rowHeights.reduce(0, +) + CGFloat(best.rows.count - 1) * between
        var y = margin + max(0, (height - total) / 2)
        var result: [Cluster] = []
        for (rowIndex, row) in best.rows.enumerated() {
            let rowWidth = row.reduce(0) { $0 + size($1).width } + CGFloat(row.count - 1) * between
            var x = margin + max(0, (width - rowWidth) / 2)
            for index in row {
                let frameSize = size(index)
                let frame = CGRect(origin: CGPoint(x: x, y: y), size: frameSize)
                let g = grid(areas[index].count)
                let boxes = (0..<areas[index].count).map { n -> CGRect in
                    let column = n % g.columns, line = n / g.columns
                    return CGRect(x: frame.minX + side + CGFloat(column) * (box.width + gap),
                                  y: frame.minY + top + CGFloat(line) * (box.height + gap),
                                  width: box.width, height: box.height)
                }
                result.append(Cluster(name: areas[index].name, frame: frame, boxes: boxes))
                x += frameSize.width + between
            }
            y += rowHeights[rowIndex] + between
        }
        return result
    }
}
