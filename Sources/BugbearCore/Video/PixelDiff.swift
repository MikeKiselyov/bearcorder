import Foundation

/// Where two same-size RGBA images differ: the share of changed pixels and boxes around the changes.
public enum PixelDiff {
    public struct Result: Equatable {
        public var changedPixels: Int
        public var totalPixels: Int
        /// Boxes around changed areas, in pixels, origin top-left.
        public var regions: [Rect]

        public var changedShare: Double {
            if totalPixels == 0 { return 0 }
            return Double(changedPixels) / Double(totalPixels)
        }
    }

    public struct Rect: Equatable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int

        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// `first` and `second` are RGBA, 4 bytes per pixel, rows of `width` pixels.
    /// A pixel counts as changed when any channel differs by more than `tolerance` (ignores JPEG noise).
    /// Changes are grouped on a grid of `cell` pixels so a changed word becomes one box, not dozens.
    public static func compare(width: Int, height: Int, first: [UInt8], second: [UInt8], tolerance: Int = 24, cell: Int = 12) -> Result {
        let total = width * height
        if first.count < total * 4 || second.count < total * 4 || width == 0 || height == 0 {
            return Result(changedPixels: 0, totalPixels: total, regions: [])
        }
        let columns = (width + cell - 1) / cell
        let rows = (height + cell - 1) / cell
        var marked = [Bool](repeating: false, count: columns * rows)
        var changed = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                var different = false
                for channel in 0..<3 {
                    let delta = abs(Int(first[offset + channel]) - Int(second[offset + channel]))
                    if delta > tolerance {
                        different = true
                    }
                }
                if different {
                    changed += 1
                    marked[(y / cell) * columns + (x / cell)] = true
                }
            }
        }
        let regions = groupCells(marked, columns: columns, rows: rows, cell: cell, width: width, height: height)
        return Result(changedPixels: changed, totalPixels: total, regions: regions)
    }

    /// Joins touching marked cells (including diagonals) into bounding boxes.
    static func groupCells(_ marked: [Bool], columns: Int, rows: Int, cell: Int, width: Int, height: Int) -> [Rect] {
        var visited = [Bool](repeating: false, count: marked.count)
        var regions: [Rect] = []
        for start in 0..<marked.count where marked[start] && !visited[start] {
            var stack = [start]
            visited[start] = true
            var minColumn = columns
            var maxColumn = 0
            var minRow = rows
            var maxRow = 0
            while let index = stack.popLast() {
                let column = index % columns
                let row = index / columns
                minColumn = min(minColumn, column)
                maxColumn = max(maxColumn, column)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nextColumn = column + dx
                        let nextRow = row + dy
                        if nextColumn < 0 || nextRow < 0 || nextColumn >= columns || nextRow >= rows { continue }
                        let next = nextRow * columns + nextColumn
                        if marked[next] && !visited[next] {
                            visited[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            let x = minColumn * cell
            let y = minRow * cell
            let right = min(width, (maxColumn + 1) * cell)
            let bottom = min(height, (maxRow + 1) * cell)
            regions.append(Rect(x: x, y: y, width: right - x, height: bottom - y))
        }
        return regions
    }
}
