import AppCore
import XCTest

/// Marks added in the video editor came out invisible: a few microseconds long when added at the
/// last frame, or dragged off the frame.
final class VideoMarkTests: XCTestCase {
    func testMarkAtThePlayheadLastsItsLength() {
        let kept = TimeSpan(start: 0, end: 180)
        XCTAssertEqual(TimeSpan.mark(at: 20, length: 3, inside: kept), TimeSpan(start: 20, end: 23))
    }

    func testMarkAtTheLastFrameStartsEarlier() {
        // The clip from the bug report: trimmed to 141.36…180, playhead at the very end.
        let kept = TimeSpan(start: 141.36, end: 180)
        let mark = TimeSpan.mark(at: 179.99999, length: 3, inside: kept)
        XCTAssertEqual(mark.end, 180, accuracy: 0.0001)
        XCTAssertEqual(mark.duration, 3, accuracy: 0.0001)
    }

    func testMarkBeforeTheTrimStartsAtTheTrim() {
        let kept = TimeSpan(start: 10, end: 20)
        XCTAssertEqual(TimeSpan.mark(at: 2, length: 3, inside: kept), TimeSpan(start: 10, end: 13))
    }

    func testMarkInAShortClipTakesTheWholeClip() {
        let kept = TimeSpan(start: 5, end: 6)
        XCTAssertEqual(TimeSpan.mark(at: 5.5, length: 3, inside: kept), TimeSpan(start: 5, end: 6))
    }

    func testMoveStopsAtTheEdgeOfTheFrame() {
        let right = MarkMove.keepInside(minX: 0.6, minY: 0.2, maxX: 0.8, maxY: 0.4, dx: 0.9, dy: 0)
        XCTAssertEqual(right.dx, 0.2, accuracy: 0.0001)
        let up = MarkMove.keepInside(minX: 0.1, minY: 0.3, maxX: 0.2, maxY: 0.5, dx: 0, dy: -0.8)
        XCTAssertEqual(up.dy, -0.3, accuracy: 0.0001)
        let inside = MarkMove.keepInside(minX: 0.1, minY: 0.1, maxX: 0.2, maxY: 0.2, dx: 0.05, dy: 0.05)
        XCTAssertEqual(inside.dx, 0.05, accuracy: 0.0001)
        XCTAssertEqual(inside.dy, 0.05, accuracy: 0.0001)
    }
}
