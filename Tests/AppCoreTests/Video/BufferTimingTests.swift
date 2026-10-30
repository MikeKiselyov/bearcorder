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
}
