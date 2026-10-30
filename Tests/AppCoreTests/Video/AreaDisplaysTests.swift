import AppCore
import CoreGraphics
import XCTest

/// Only the displays a recorded area touches run at native resolution; the rule is the one
/// `AreaComposition.plan` uses to put a display in the clip.
final class AreaDisplaysTests: XCTestCase {
    /// A Retina laptop on the left, a monitor on the right whose top sits 200 pt higher.
    let frames = [
        CGRect(x: 0, y: 0, width: 1512, height: 982),
        CGRect(x: 1512, y: -18, width: 1920, height: 1200),
    ]

    func testOneDisplay() {
        let area = CGRect(x: 100, y: 200, width: 640, height: 360)
        XCTAssertEqual(AreaDisplays.touched(area: area, frames: frames), [0])
    }

    func testNativeDisplaysForAreaAcrossTwo() {
        let area = CGRect(x: 1312, y: 300, width: 400, height: 300)
        XCTAssertEqual(AreaDisplays.touched(area: area, frames: frames), [0, 1])
    }

    func testOnePixelOverlapCounts() {
        // One point over the seam onto the monitor.
        let area = CGRect(x: 1000, y: 300, width: 513, height: 300)
        XCTAssertEqual(AreaDisplays.touched(area: area, frames: frames), [0, 1])
    }

    func testNoneOutside() {
        let area = CGRect(x: 5000, y: 300, width: 400, height: 300)
        XCTAssertEqual(AreaDisplays.touched(area: area, frames: frames), [])
    }

    func testEmptyFrameIsSkipped() {
        let area = CGRect(x: 100, y: 200, width: 640, height: 360)
        XCTAssertEqual(AreaDisplays.touched(area: area, frames: [CGRect(x: 0, y: 0, width: 0, height: 900), frames[0]]), [1])
    }

    func testMovedAreaUpgradesOnlyNewDisplays() {
        XCTAssertEqual(AreaDisplays.toUpgrade(touched: [1, 2], native: [1], recording: true), [2])
        XCTAssertEqual(AreaDisplays.toUpgrade(touched: [1], native: [1], recording: true), [], "already native: nothing to do")
    }

    func testMovedAreaNeverDowngrades() {
        // The area left display 1: it is not in the result, and nothing says to take it back.
        XCTAssertEqual(AreaDisplays.toUpgrade(touched: [2], native: [1, 2], recording: true), [])
    }

    func testNothingWithoutARecording() {
        XCTAssertEqual(AreaDisplays.toUpgrade(touched: [1, 2], native: [], recording: false), [])
    }

    func testSameDisplaysAsTheComposition() throws {
        let area = CGRect(x: 1312, y: 300, width: 400, height: 300)
        var sources: [AreaComposition.Source] = []
        for frame in frames {
            sources.append(AreaComposition.Source(frame: frame, pixels: CGSize(width: frame.width * 2, height: frame.height * 2)))
        }
        let plan = try XCTUnwrap(AreaComposition.plan(area: area, sources: sources))
        var planned: [Int] = []
        for placement in plan.placements {
            planned.append(placement.index)
        }
        XCTAssertEqual(AreaDisplays.touched(area: area, frames: frames), planned)
    }
}
