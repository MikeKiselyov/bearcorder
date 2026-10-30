import XCTest
@testable import AppCore

final class PixelDiffTests: XCTestCase {
    func image(width: Int, height: Int, fill: UInt8) -> [UInt8] {
        return [UInt8](repeating: fill, count: width * height * 4)
    }

    func paint(_ pixels: inout [UInt8], width: Int, x: Int, y: Int, size: Int, value: UInt8) {
        for row in y..<(y + size) {
            for column in x..<(x + size) {
                let offset = (row * width + column) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
            }
        }
    }

    func testTwoSeparateChanges() {
        let width = 120
        let height = 80
        let before = image(width: width, height: height, fill: 255)
        var after = before
        paint(&after, width: width, x: 5, y: 5, size: 10, value: 0)
        paint(&after, width: width, x: 90, y: 50, size: 8, value: 0)
        let result = PixelDiff.compare(width: width, height: height, first: before, second: after)
        XCTAssertEqual(result.changedPixels, 164)
        XCTAssertEqual(result.regions.count, 2)
        XCTAssertEqual(result.regions[0], PixelDiff.Rect(x: 0, y: 0, width: 24, height: 24))
    }

    func testSmallNoiseIsIgnored() {
        let before = image(width: 20, height: 20, fill: 200)
        let after = image(width: 20, height: 20, fill: 210)
        let result = PixelDiff.compare(width: 20, height: 20, first: before, second: after)
        XCTAssertEqual(result.changedPixels, 0)
        XCTAssertTrue(result.regions.isEmpty)
        XCTAssertEqual(result.changedShare, 0)
    }
}
