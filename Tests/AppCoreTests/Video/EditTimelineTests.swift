import XCTest
@testable import AppCore

final class EditTimelineTests: XCTestCase {
    private func makeMap(_ timeline: EditTimeline) -> TimeMap {
        return TimeMap(pieces: timeline.pieces())
    }

    // MARK: TimeSpan

    func testTimeSpanSwapsReversedBounds() {
        let span = TimeSpan(start: 8, end: 3)
        XCTAssertEqual(span.start, 3)
        XCTAssertEqual(span.end, 8)
        XCTAssertEqual(span.duration, 5)
    }

    func testTimeSpanContainsStartButNotEnd() {
        let span = TimeSpan(start: 2, end: 4)
        XCTAssertTrue(span.contains(2))
        XCTAssertTrue(span.contains(3.99))
        XCTAssertFalse(span.contains(4))
        XCTAssertFalse(span.contains(1.99))
    }

    // MARK: MarkMove

    func testKeepInsideStopsAtTheLeftEdge() {
        let shift = MarkMove.keepInside(minX: 0.1, minY: 0.2, maxX: 0.3, maxY: 0.4, dx: -0.5, dy: -0.5)
        XCTAssertEqual(shift.dx, -0.1, accuracy: 0.0001)
        XCTAssertEqual(shift.dy, -0.2, accuracy: 0.0001)
    }

    func testKeepInsideStopsAtTheBottomEdge() {
        let shift = MarkMove.keepInside(minX: 0.6, minY: 0.5, maxX: 0.9, maxY: 0.8, dx: 0.5, dy: 0.5)
        XCTAssertEqual(shift.dx, 0.1, accuracy: 0.0001)
        XCTAssertEqual(shift.dy, 0.2, accuracy: 0.0001)
    }

    // MARK: Pieces

    func testNoEditsIsOnePieceWithEqualTimes() {
        let timeline = EditTimeline(sourceDuration: 10)
        let pieces = timeline.pieces()
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].sourceStart, 0)
        XCTAssertEqual(pieces[0].outputStart, 0)
        XCTAssertEqual(pieces[0].outputDuration, 10)
        XCTAssertFalse(pieces[0].isFreeze)
    }

    func testTrimAloneShortensTheOutput() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.trim = TimeSpan(start: 2, end: 8)
        XCTAssertEqual(timeline.outputDuration, 6, accuracy: 0.0001)
        XCTAssertTrue(timeline.hasEdits)
    }

    func testSpeedPieceScalesOutputDuration() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.speeds = [SpeedEdit(span: TimeSpan(start: 2, end: 6), factor: 2)]
        // 2 + 4 at double speed (2) + 4.
        XCTAssertEqual(timeline.outputDuration, 8, accuracy: 0.0001)
    }

    func testLaterSpeedEditWinsWhenTheyOverlap() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.speeds = [
            SpeedEdit(span: TimeSpan(start: 0, end: 10), factor: 2),
            SpeedEdit(span: TimeSpan(start: 4, end: 6), factor: 0.5),
        ]
        // 0..4 at 2x (2) + 4..6 at 0.5x (4) + 6..10 at 2x (2).
        XCTAssertEqual(timeline.outputDuration, 8, accuracy: 0.0001)
    }

    func testFreezeInsideAClipAddsItsDuration() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.freezes = [FreezeEdit(at: 4, duration: 2)]
        XCTAssertEqual(timeline.outputDuration, 12, accuracy: 0.0001)
        let freezePieces = timeline.pieces().filter { piece in piece.isFreeze }
        XCTAssertEqual(freezePieces.count, 1)
        XCTAssertEqual(freezePieces[0].outputStart, 4, accuracy: 0.0001)
    }

    func testFreezeWithZeroDurationIsIgnored() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.freezes = [FreezeEdit(at: 4, duration: 0)]
        XCTAssertEqual(timeline.pieces().filter { piece in piece.isFreeze }.count, 0)
        XCTAssertEqual(timeline.outputDuration, 10, accuracy: 0.0001)
    }

    func testFreezeInsideACutIsIgnored() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.cuts = [TimeSpan(start: 3, end: 6)]
        timeline.freezes = [FreezeEdit(at: 4, duration: 2)]
        XCTAssertEqual(timeline.pieces().filter { piece in piece.isFreeze }.count, 0)
        XCTAssertEqual(timeline.outputDuration, 7, accuracy: 0.0001)
    }

    func testFreezeAtTheEndShowsTheLastFrame() {
        var timeline = EditTimeline(sourceDuration: 10, frameDuration: 0.1)
        timeline.freezes = [FreezeEdit(at: 10, duration: 1)]
        let freeze = timeline.pieces().last
        XCTAssertEqual(freeze?.isFreeze, true)
        XCTAssertEqual(freeze?.sourceStart ?? 0, 9.9, accuracy: 0.0001)
    }

    func testHasEditsIgnoresATinyTrim() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.trim = TimeSpan(start: 0.0005, end: 10)
        XCTAssertFalse(timeline.hasEdits)
    }

    func testEverythingCutLeavesNoPieces() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.cuts = [TimeSpan(start: 0, end: 10)]
        XCTAssertTrue(timeline.pieces().isEmpty)
        XCTAssertEqual(timeline.outputDuration, 0)
    }

    // MARK: TimeMap

    func testRoundTripOutsideCutsWithCutsAndSpeed() {
        var timeline = EditTimeline(sourceDuration: 20)
        timeline.cuts = [TimeSpan(start: 5, end: 8)]
        timeline.speeds = [SpeedEdit(span: TimeSpan(start: 12, end: 16), factor: 2)]
        let map = makeMap(timeline)
        let sourceTimes: [Double] = [0, 1.5, 4.9, 8, 10, 12, 13.5, 15.9, 17, 19.5]
        for sourceTime in sourceTimes {
            let outputTime = map.outputTime(forSource: sourceTime)
            let back = map.sourceTime(forOutput: outputTime)
            XCTAssertEqual(back, sourceTime, accuracy: 0.0001, "source \(sourceTime)")
        }
    }

    func testCutTimeMapsToTheOutputWhereTheCutWas() {
        var timeline = EditTimeline(sourceDuration: 20)
        timeline.cuts = [TimeSpan(start: 5, end: 8)]
        let map = makeMap(timeline)
        // The cut start and the middle of the cut both land on output 5, where the next piece starts.
        XCTAssertEqual(map.outputTime(forSource: 6), 5, accuracy: 0.0001)
        XCTAssertEqual(map.outputTime(forSource: 5), 5, accuracy: 0.0001)
    }

    func testSpeedScalesOutputTimeInsideThePiece() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.speeds = [SpeedEdit(span: TimeSpan(start: 2, end: 6), factor: 2)]
        let map = makeMap(timeline)
        // Source 4 is 2 seconds into a 2x piece: 1 second of output after the piece start at 2.
        XCTAssertEqual(map.outputTime(forSource: 4), 3, accuracy: 0.0001)
        XCTAssertEqual(map.sourceTime(forOutput: 3), 4, accuracy: 0.0001)
        XCTAssertEqual(map.outputTime(forSource: 7), 7 - 2, accuracy: 0.0001)
    }

    func testSourceTimeDuringFreezeIsTheFrozenFrame() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.freezes = [FreezeEdit(at: 4, duration: 2)]
        let map = makeMap(timeline)
        XCTAssertEqual(map.sourceTime(forOutput: 5), 4, accuracy: 0.0001)
    }

    func testSourceTimeBeyondTheEndIsTheEndOfTheLastPiece() {
        let map = makeMap(EditTimeline(sourceDuration: 10))
        XCTAssertEqual(map.sourceTime(forOutput: 99), 10, accuracy: 0.0001)
    }

    func testSourceTimeBeforeTheStartIsTheFirstPieceStart() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.trim = TimeSpan(start: 3, end: 10)
        let map = makeMap(timeline)
        XCTAssertEqual(map.sourceTime(forOutput: -1), 3, accuracy: 0.0001)
    }

    func testEmptyMapReturnsTheTimeUnchanged() {
        let map = TimeMap(pieces: [])
        XCTAssertEqual(map.sourceTime(forOutput: 4), 4)
        XCTAssertEqual(map.outputTime(forSource: 4), 4)
    }

    func testSourceAfterTheLastPieceMapsToTheOutputEnd() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.trim = TimeSpan(start: 0, end: 6)
        let map = makeMap(timeline)
        XCTAssertEqual(map.outputTime(forSource: 9), 6, accuracy: 0.0001)
    }

    func testIsVisibleIsFalseInsideACutAndOutsideTheTrim() {
        var timeline = EditTimeline(sourceDuration: 20)
        timeline.trim = TimeSpan(start: 2, end: 18)
        timeline.cuts = [TimeSpan(start: 8, end: 12)]
        let map = makeMap(timeline)
        XCTAssertFalse(map.isVisible(source: 10))
        XCTAssertFalse(map.isVisible(source: 1))
        XCTAssertFalse(map.isVisible(source: 19))
        XCTAssertTrue(map.isVisible(source: 5))
        XCTAssertTrue(map.isVisible(source: 14))
        // Deliberate: the end of a piece counts as visible, so the exact start of a cut (8) is
        // still visible as the last instant of the piece before it.
        XCTAssertTrue(map.isVisible(source: 8))
    }
}
