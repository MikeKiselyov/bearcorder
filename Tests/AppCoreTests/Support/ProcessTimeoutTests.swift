import XCTest
@testable import AppCore

final class ProcessTimeoutTests: XCTestCase {
    func testSlowProcessIsStoppedAfterTimeout() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        let started = Date()
        let finished = try ProcessTimeout.run(process, seconds: 0.5)
        XCTAssertFalse(finished)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testQuickProcessFinishes() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let finished = try ProcessTimeout.run(process, seconds: 5)
        XCTAssertTrue(finished)
    }

    func testProcessIgnoringTerminateIsKilled() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; sleep 30"]
        let started = Date()
        let finished = try ProcessTimeout.run(process, seconds: 0.5)
        XCTAssertFalse(finished)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }
}
