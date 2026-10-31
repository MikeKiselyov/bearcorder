import AppCore
import XCTest

/// Old buffer segments are deleted as they leave the window. A segment that failed to finish is never
/// used for a clip, so it goes at once.
final class SegmentPruningTests: XCTestCase {
    func testAFinishedSegmentThatLeftTheWindowIsRemoved() {
        XCTAssertTrue(SegmentPruning.shouldRemove(state: .finished, end: 10, keepFrom: 20))
    }

    func testAFinishedSegmentInsideTheWindowStays() {
        XCTAssertFalse(SegmentPruning.shouldRemove(state: .finished, end: 20, keepFrom: 20))
        XCTAssertFalse(SegmentPruning.shouldRemove(state: .finished, end: 30, keepFrom: 20))
    }

    func testAnOpenSegmentStaysEvenWhenOld() {
        XCTAssertFalse(SegmentPruning.shouldRemove(state: .open, end: 10, keepFrom: 20))
    }

    func testAFailedSegmentIsRemovedWhenOld() {
        XCTAssertTrue(SegmentPruning.shouldRemove(state: .failed, end: 10, keepFrom: 20))
    }

    func testAFailedSegmentIsRemovedWhenRecent() {
        XCTAssertTrue(SegmentPruning.shouldRemove(state: .failed, end: 30, keepFrom: 20))
    }
}
