import AppCore
import XCTest

/// The watchdog pings the main queue; an answer later than the threshold is a stall worth a log line.
final class MainThreadStallTests: XCTestCase {
    private let second: UInt64 = 1_000_000_000

    func testQuickAnswerIsNoStall() {
        XCTAssertNil(MainThreadStall.logLine(pingedAt: 5 * second, answeredAt: 5 * second + 2_000_000))
        XCTAssertNil(MainThreadStall.logLine(pingedAt: 5 * second, answeredAt: 6 * second), "exactly the threshold")
    }

    func testLateAnswerIsOneLineWithItsLength() {
        // The line the test scripts look for (scripts/test/lib/run-log.sh).
        XCTAssertEqual(MainThreadStall.logLine(pingedAt: 5 * second, answeredAt: 9 * second + 12_000_000), "main thread stalled 4012 ms")
    }

    func testThresholdCanBeSet() {
        XCTAssertEqual(MainThreadStall.logLine(pingedAt: 0, answeredAt: 400_000_000, threshold: 300_000_000), "main thread stalled 400 ms")
        XCTAssertNil(MainThreadStall.logLine(pingedAt: 0, answeredAt: 200_000_000, threshold: 300_000_000))
    }

    func testAnswerBeforeThePingIsNoStall() {
        XCTAssertNil(MainThreadStall.logLine(pingedAt: 9 * second, answeredAt: 5 * second))
    }
}
