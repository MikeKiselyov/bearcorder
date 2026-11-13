import XCTest
@testable import AppCore

final class ScrollStitcherTests: XCTestCase {
    /// A long "page" of distinct rows; frames are windows into it.
    /// A distinct profile per row: a bright bar whose position and brightness depend on the row.
    static func profile(_ seed: Int) -> [UInt8] {
        var bins = [UInt8](repeating: 20, count: ScrollStitcher.bins)
        bins[seed % ScrollStitcher.bins] = UInt8(100 + seed % 150)
        bins[(seed * 7 + 3) % ScrollStitcher.bins] = UInt8(60 + (seed * 13) % 190)
        return bins
    }

    let page: [[UInt8]?] = {
        var rows: [[UInt8]?] = []
        for index in 0..<500 {
            if index % 17 == 0 {
                rows.append(nil)
            } else {
                rows.append(ScrollStitcherTests.profile(index))
            }
        }
        return rows
    }()

    func frame(at top: Int, height: Int) -> [[UInt8]?] {
        return Array(page[top..<(top + height)])
    }

    func testFindsTheScrollDistance() {
        let first = frame(at: 0, height: 120)
        let second = frame(at: 84, height: 120)
        XCTAssertEqual(ScrollStitcher.offset(previous: first, next: second), 84)
    }

    /// A sticky header and footer with plain padding around their text: the padding is empty in both
    /// frames, and page text that scrolled under it is not a mismatch.
    func testPlainRowsOfAStickyBarAreNotAMismatch() {
        var first = frame(at: 0, height: 160)
        var second = frame(at: 60, height: 160)
        for row in 0..<30 {
            var bar: [UInt8]? = nil
            if row >= 10 && row < 20 {
                bar = ScrollStitcherTests.profile(9_000 + row)
            }
            first[row] = bar
            second[row] = bar
            first[130 + row] = bar
            second[130 + row] = bar
        }
        let best = ScrollStitcher.bestShift(previous: first, next: second)
        XCTAssertEqual(best.shift, 60)
        XCTAssertLessThan(best.error, 1)
    }

    func testStickyHeaderStillWorks() {
        var first = frame(at: 0, height: 120)
        var second = frame(at: 60, height: 120)
        for row in 0..<10 {
            first[row] = ScrollStitcherTests.profile(9_000 + row)
            second[row] = ScrollStitcherTests.profile(9_000 + row)
        }
        XCTAssertEqual(ScrollStitcher.offset(previous: first, next: second), 60)
    }

    func testEndOfPageAndUnrelatedFrames() {
        let first = frame(at: 200, height: 120)
        XCTAssertTrue(ScrollStitcher.isSame(first, first))
        var unrelated: [[UInt8]?] = []
        for index in 0..<120 {
            var bins = [UInt8](repeating: 230, count: ScrollStitcher.bins)
            bins[(index * 5) % ScrollStitcher.bins] = 0
            unrelated.append(bins)
        }
        XCTAssertNil(ScrollStitcher.offset(previous: first, next: unrelated))
    }

    func testSmallRenderingDifferencesStillMatch() {
        let first = frame(at: 0, height: 120)
        var second = frame(at: 50, height: 120)
        // Text re-rendered after a scroll: every bin a little off.
        for row in 0..<second.count {
            guard var bins = second[row] else { continue }
            for index in 0..<bins.count {
                bins[index] = UInt8(min(255, Int(bins[index]) + 3))
            }
            second[row] = bins
        }
        XCTAssertEqual(ScrollStitcher.offset(previous: first, next: second), 50)
    }

    func testRowSignatureSkipsFlatRows() {
        let flat = [UInt8](repeating: 200, count: 400)
        var striped = flat
        // A dark pixel in the middle of the row (pixel 50).
        striped[200] = 0
        striped[201] = 0
        striped[202] = 0
        flat.withUnsafeBufferPointer { buffer in
            XCTAssertNil(ScrollStitcher.rowSignature(buffer, rowStart: 0, width: 100))
        }
        striped.withUnsafeBufferPointer { buffer in
            XCTAssertNotNil(ScrollStitcher.rowSignature(buffer, rowStart: 0, width: 100))
        }
    }

    /// The first and last pixels of a picked area can show the window's edge or the window behind it:
    /// an empty row stays empty with a dark pixel there.
    func testADarkPixelAtTheEdgeLeavesTheRowFlat() {
        var leftEdge = [UInt8](repeating: 200, count: 400)
        leftEdge[4] = 0
        leftEdge[5] = 0
        leftEdge[6] = 0
        var rightEdge = [UInt8](repeating: 200, count: 400)
        rightEdge[392] = 0
        rightEdge[393] = 0
        rightEdge[394] = 0
        leftEdge.withUnsafeBufferPointer { buffer in
            XCTAssertNil(ScrollStitcher.rowSignature(buffer, rowStart: 0, width: 100))
        }
        rightEdge.withUnsafeBufferPointer { buffer in
            XCTAssertNil(ScrollStitcher.rowSignature(buffer, rowStart: 0, width: 100))
        }
    }
}
