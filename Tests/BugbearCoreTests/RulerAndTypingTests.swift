import XCTest
@testable import BugbearCore

final class RulerDragTests: XCTestCase {
    // Dragging from 2 s to 5 s away from the playhead selects 2-5 s; the seek on the first
    // move must not turn the rest of the drag into a scrub.
    func testDragAwayFromThePlayheadSelects() {
        var drag = RulerDrag()
        let scale = 10.0
        XCTAssertEqual(drag.changed(startX: 20, x: 20, playheadX: 80, scale: scale), .seek(2))
        // The playhead is now at the start of the drag.
        XCTAssertEqual(drag.changed(startX: 20, x: 35, playheadX: 20, scale: scale), .select(start: 2, end: 3.5))
        XCTAssertEqual(drag.changed(startX: 20, x: 50, playheadX: 20, scale: scale), .select(start: 2, end: 5))
        XCTAssertFalse(drag.ended(startX: 20, x: 50))
        XCTAssertNil(drag.mode)
    }

    func testDragFromThePlayheadScrubs() {
        var drag = RulerDrag()
        XCTAssertEqual(drag.changed(startX: 84, x: 84, playheadX: 80, scale: 10), .seek(8.4))
        XCTAssertEqual(drag.changed(startX: 84, x: 120, playheadX: 84, scale: 10), .seek(12))
        XCTAssertTrue(drag.ended(startX: 84, x: 120))
    }

    func testAClickSeeksAndClearsTheSelection() {
        var drag = RulerDrag()
        XCTAssertEqual(drag.changed(startX: 50, x: 51, playheadX: 0, scale: 10), .seek(5.1))
        XCTAssertTrue(drag.ended(startX: 50, x: 51))
    }

    func testEachDragDecidesAgain() {
        var drag = RulerDrag()
        _ = drag.changed(startX: 80, x: 90, playheadX: 80, scale: 10)
        _ = drag.ended(startX: 80, x: 90)
        XCTAssertEqual(drag.changed(startX: 20, x: 40, playheadX: 90, scale: 10), .select(start: 2, end: 4))
    }
}

final class TypingRunsTests: XCTestCase {
    func testKeysCloseTogetherAreOneRunThatKeepsItsStart() {
        var runs = TypingRuns()
        let first = runs.typed(at: 10)
        XCTAssertTrue(first.isNew)
        let second = runs.typed(at: 11)
        let third = runs.typed(at: 12.2)
        XCTAssertFalse(second.isNew)
        XCTAssertFalse(third.isNew)
        XCTAssertEqual(third.run.id, first.run.id)
        XCTAssertEqual(third.run.start, 10)
    }

    func testAPauseStartsANewRun() {
        var runs = TypingRuns()
        let first = runs.typed(at: 10)
        let later = runs.typed(at: 10 + TypingRuns.pause + 0.1)
        XCTAssertTrue(later.isNew)
        XCTAssertNotEqual(later.run.id, first.run.id)
    }

    // Tab or a click between two fields: the next keys are a new run even right away.
    func testAnInterruptionEndsTheRun() {
        var runs = TypingRuns()
        let first = runs.typed(at: 10)
        XCTAssertEqual(runs.interrupted()?.id, first.run.id)
        XCTAssertNil(runs.interrupted())
        let next = runs.typed(at: 10.2)
        XCTAssertTrue(next.isNew)
        XCTAssertNotEqual(next.run.id, first.run.id)
    }
}
