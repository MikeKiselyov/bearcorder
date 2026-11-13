import XCTest
@testable import AppCore

final class BufferTimingTests: XCTestCase {
    func testHeartbeatRunsOnceASecond() {
        XCTAssertEqual(BufferTiming.heartbeatInterval, 1.0)
        XCTAssertEqual(BufferTiming.heartbeatIdleThreshold, 0.95)
    }

    func testRepeatsAfterOneSecondStill() {
        XCTAssertFalse(BufferTiming.shouldRepeat(now: 100.94, lastFrame: 100))
        XCTAssertTrue(BufferTiming.shouldRepeat(now: 100.95, lastFrame: 100))
        XCTAssertTrue(BufferTiming.shouldRepeat(now: 102, lastFrame: 100))
    }

    func testPrunesOnFinishedSegment() {
        XCTAssertTrue(BufferTiming.shouldPrune(now: 100.1, lastPrune: 100, segmentFinished: true))
    }

    func testPrunesAtMostOncePerSecond() {
        XCTAssertFalse(BufferTiming.shouldPrune(now: 100.5, lastPrune: 100, segmentFinished: false))
        XCTAssertTrue(BufferTiming.shouldPrune(now: 101.0, lastPrune: 100, segmentFinished: false))
        XCTAssertTrue(BufferTiming.shouldPrune(now: 105, lastPrune: 100, segmentFinished: false))
    }

    func testCatchUpOnlyWhenBehind() {
        XCTAssertNil(BufferTiming.catchUpTime(now: 100.03, lastFrame: 100))
        XCTAssertNil(BufferTiming.catchUpTime(now: 100, lastFrame: 100))
        XCTAssertEqual(BufferTiming.catchUpTime(now: 100.8, lastFrame: 100), 100.8)
    }

    func testCoveredSecondsGrowUpToTheWindow() {
        XCTAssertEqual(BufferTiming.coveredSeconds(now: 100, firstSegmentStart: nil, retention: 180), 0)
        XCTAssertEqual(BufferTiming.coveredSeconds(now: 100, firstSegmentStart: 60, retention: 180), 40)
        XCTAssertEqual(BufferTiming.coveredSeconds(now: 500, firstSegmentStart: 60, retention: 180), 180)
        // A first frame stamped a moment ahead of the clock is not a negative time.
        XCTAssertEqual(BufferTiming.coveredSeconds(now: 100, firstSegmentStart: 100.2, retention: 180), 0)
    }

    func testActivityCountsFramesPerBucketOldestFirst() {
        // A 40 s window in 4 buckets of 10 s at now = 100: [60, 70) [70, 80) [80, 90) [90, 100].
        let frameTimes: [Double] = [61, 62, 63, 64, 85, 86, 95]
        let activity = BufferTiming.activity(frameTimes: frameTimes, now: 100, window: 40, buckets: 4)
        XCTAssertEqual(activity, [1, 0, 0.5, 0.25])
    }

    func testActivityLeavesOutFramesOutsideTheWindow() {
        // Older than the window, and ahead of the clock.
        let activity = BufferTiming.activity(frameTimes: [10, 59.9, 100.5], now: 100, window: 40, buckets: 4)
        XCTAssertEqual(activity, [0, 0, 0, 0])
        XCTAssertEqual(BufferTiming.activity(frameTimes: [], now: 100, window: 40, buckets: 16).count, 16)
    }
}
