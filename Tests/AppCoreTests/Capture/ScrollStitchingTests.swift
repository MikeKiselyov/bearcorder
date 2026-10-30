import CoreGraphics
import XCTest
@testable import AppCore

final class ScrollStitchingTests: XCTestCase {
    private let width = 128

    /// One row of noisy pixels that depends only on `seed`: the same seed gives the same row, and
    /// different seeds give rows that do not look alike.
    private func noisyRow(seed: Int) -> [UInt8] {
        var state = UInt32(truncatingIfNeeded: seed &* 2_654_435_761 &+ 12_345)
        var row: [UInt8] = []
        for _ in 0..<width {
            state = state &* 1_664_525 &+ 1_013_904_223
            let level = UInt8(truncatingIfNeeded: state >> 24)
            row.append(level)
            row.append(UInt8(truncatingIfNeeded: state >> 16))
            row.append(UInt8(truncatingIfNeeded: state >> 8))
            row.append(255)
        }
        return row
    }

    private func flatRow(level: UInt8) -> [UInt8] {
        var row: [UInt8] = []
        for _ in 0..<width {
            row.append(contentsOf: [level, level, level, 255])
        }
        return row
    }

    private func makeImage(rows: [[UInt8]]) -> CGImage {
        var bytes: [UInt8] = []
        for row in rows {
            bytes.append(contentsOf: row)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(width: width, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        return ScrollStitching.rgba(image, width: image.width, height: image.height) ?? []
    }

    func testStitchesTwoOverlappingFrames() {
        // A 140-row page seen through a 100-row window, scrolled by 40 rows.
        var pageRows: [[UInt8]] = []
        for index in 0..<140 {
            pageRows.append(noisyRow(seed: index))
        }
        let first = makeImage(rows: Array(pageRows[0..<100]))
        let second = makeImage(rows: Array(pageRows[40..<140]))
        let signatures = [ScrollStitching.rowSignatures(first), ScrollStitching.rowSignatures(second)]
        let shift = ScrollStitcher.offset(previous: signatures[0], next: signatures[1])
        XCTAssertEqual(shift, 40)

        let stitched = ScrollStitching.stitch(frames: [first, second], shifts: [40], signatures: signatures)
        XCTAssertEqual(stitched?.height, 140)
        XCTAssertEqual(stitched?.width, width)
        guard let stitched = stitched else { return }
        let page = makeImage(rows: pageRows)
        XCTAssertEqual(pixels(stitched), pixels(page), "the glued image is the page")
        // The bottom rows come from the second frame.
        let bottom = Array(pixels(stitched).suffix(100 * width * 4))
        XCTAssertEqual(bottom, pixels(second))
    }

    func testStitchNeedsAFrame() {
        XCTAssertNil(ScrollStitching.stitch(frames: [], shifts: [], signatures: []))
    }

    func testStickyFooterFound() {
        // Three frames of 150 rows: the top 130 scroll, the bottom 20 are a footer that stays.
        var footerRows: [[UInt8]] = []
        for index in 0..<20 {
            footerRows.append(noisyRow(seed: 9_000 + index))
        }
        var frames: [CGImage] = []
        for frameIndex in 0..<3 {
            var rows: [[UInt8]] = []
            for index in 0..<130 {
                rows.append(noisyRow(seed: frameIndex * 1_000 + index))
            }
            rows.append(contentsOf: footerRows)
            frames.append(makeImage(rows: rows))
        }
        // The 20 equal rows plus the 4 soft-edge rows the function adds on purpose.
        XCTAssertEqual(ScrollStitching.stickyFooterRows(frames), 24)
    }

    func testNoFooterWhenFramesDiffer() {
        var frames: [CGImage] = []
        for frameIndex in 0..<2 {
            var rows: [[UInt8]] = []
            for index in 0..<90 {
                rows.append(noisyRow(seed: frameIndex * 1_000 + index))
            }
            frames.append(makeImage(rows: rows))
        }
        XCTAssertEqual(ScrollStitching.stickyFooterRows(frames), 0)
        XCTAssertEqual(ScrollStitching.stickyFooterRows([frames[0]]), 0, "one frame has nothing to compare")
    }

    func testMostlyEqualFramesAreNotAFooter() {
        let rows = (0..<90).map { index in noisyRow(seed: index) }
        let frame = makeImage(rows: rows)
        XCTAssertEqual(ScrollStitching.stickyFooterRows([frame, frame]), 0, "more than a third equal is not a footer")
    }

    func testRowSignaturesNilForUniformRow() {
        var rows: [[UInt8]] = []
        rows.append(flatRow(level: 200))
        rows.append(noisyRow(seed: 5))
        rows.append(flatRow(level: 10))
        let signatures = ScrollStitching.rowSignatures(makeImage(rows: rows))
        XCTAssertEqual(signatures.count, 3)
        XCTAssertNil(signatures[0])
        XCTAssertNotNil(signatures[1])
        XCTAssertNil(signatures[2])
        XCTAssertEqual(signatures[1]?.count, ScrollStitcher.bins)
    }
}
