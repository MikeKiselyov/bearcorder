import XCTest
@testable import AppCore

final class PauseTimelineTests: XCTestCase {
    private func durations(_ ranges: [(start: Double, end: Double)]) -> [Double] {
        var result: [Double] = []
        for range in ranges {
            result.append(range.end - range.start)
        }
        return result
    }

    func testNoPauseKeepsEverything() {
        let timeline = PauseTimeline(startTime: 100)
        XCTAssertEqual(timeline.elapsed(now: 110), 10)
        XCTAssertEqual(durations(timeline.keptRanges(until: 110)), [10])
    }

    func testSeveralPausesAreCutOut() {
        var timeline = PauseTimeline(startTime: 100)
        timeline.pause(at: 103)
        timeline.resume(at: 107)
        timeline.pause(at: 110)
        timeline.resume(at: 111)
        let ranges = timeline.keptRanges(until: 115)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges[0].start, 100)
        XCTAssertEqual(ranges[1].start, 107)
        XCTAssertEqual(ranges[2].start, 111)
        XCTAssertEqual(durations(ranges), [3, 3, 4])
        XCTAssertEqual(timeline.elapsed(now: 115), 10)
    }

    // Stop pressed while paused: nothing after the pause is kept, and the time does not grow.
    func testStopWhilePaused() {
        var timeline = PauseTimeline(startTime: 100)
        timeline.pause(at: 105)
        XCTAssertTrue(timeline.isPaused)
        XCTAssertEqual(durations(timeline.keptRanges(until: 130)), [5])
        XCTAssertEqual(timeline.elapsed(now: 130), 5)
        XCTAssertEqual(timeline.elapsed(now: 200), 5)
    }

    func testPauseRightAtTheStartKeepsNoEmptyRange() {
        var timeline = PauseTimeline(startTime: 100)
        timeline.pause(at: 100)
        timeline.resume(at: 104)
        XCTAssertEqual(durations(timeline.keptRanges(until: 106)), [2])
    }

    func testDoublePauseOrResumeChangesNothing() {
        var timeline = PauseTimeline(startTime: 100)
        timeline.resume(at: 101)
        XCTAssertTrue(timeline.pauses.isEmpty)
        timeline.pause(at: 102)
        timeline.pause(at: 103)
        XCTAssertEqual(timeline.pauses.count, 1)
        XCTAssertEqual(timeline.pauses[0].start, 102)
        timeline.resume(at: 104)
        timeline.resume(at: 105)
        XCTAssertEqual(timeline.pauses[0].end, 104)
        XCTAssertFalse(timeline.isPaused)
    }
}
