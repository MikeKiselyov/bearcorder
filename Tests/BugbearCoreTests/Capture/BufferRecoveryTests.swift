import BugbearCore
import XCTest

/// Issue #17: the displays went away, the one try to restart the buffer 2 s later found no
/// display, and the buffer stayed on "Buffer error" even after the displays were back.
final class BufferRecoveryTests: XCTestCase {
    func testNothingWaitsAtFirst() {
        var recovery = BufferRecovery()
        XCTAssertFalse(recovery.isWaiting)
        XCTAssertNil(recovery.nextDelay())
    }

    func testAFailedTryKeepsWaiting() {
        var recovery = BufferRecovery()
        recovery.bufferLost()
        XCTAssertEqual(recovery.nextDelay(), 2)
        // The try found no display: the buffer is lost again, and the next try comes later.
        recovery.bufferLost()
        XCTAssertTrue(recovery.isWaiting)
        XCTAssertEqual(recovery.nextDelay(), 5)
    }

    func testTriesSlowDownAndNeverStop() {
        var recovery = BufferRecovery()
        recovery.bufferLost()
        var delays: [Double] = []
        for _ in 0..<8 {
            if let delay = recovery.nextDelay() {
                delays.append(delay)
            }
        }
        XCTAssertEqual(delays, [2, 5, 15, 30, 60, 60, 60, 60])
        XCTAssertTrue(recovery.isWaiting)
    }

    func testNoDisplayKeepsTryingOtherErrorsGiveUp() {
        var recovery = BufferRecovery()
        recovery.bufferLost()
        for _ in 0..<10 {
            _ = recovery.nextDelay()
        }
        XCTAssertTrue(recovery.keepsTrying(afterNoDisplay: true))
        XCTAssertFalse(recovery.keepsTrying(afterNoDisplay: false))

        var fresh = BufferRecovery()
        fresh.bufferLost()
        _ = fresh.nextDelay()
        XCTAssertTrue(fresh.keepsTrying(afterNoDisplay: false))
        _ = fresh.nextDelay()
        _ = fresh.nextDelay()
        XCTAssertFalse(fresh.keepsTrying(afterNoDisplay: false))
    }

    func testAStartOrPauseEndsTheWait() {
        var recovery = BufferRecovery()
        recovery.bufferLost()
        _ = recovery.nextDelay()
        _ = recovery.nextDelay()
        recovery.ended()
        XCTAssertFalse(recovery.isWaiting)
        XCTAssertNil(recovery.nextDelay())
        // A later loss starts from the quick tries again.
        recovery.bufferLost()
        XCTAssertEqual(recovery.nextDelay(), 2)
    }
}
