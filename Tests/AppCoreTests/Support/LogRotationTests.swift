import XCTest
@testable import AppCore

final class LogRotationTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("rotation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testOverLimitMovesFileToOldCopy() throws {
        let log = folder.appendingPathComponent("app.log")
        try Data("0123456789".utf8).write(to: log)
        LogRotation.rotateIfNeeded(log, limit: 5)
        let old = folder.appendingPathComponent("app.log.1")
        XCTAssertEqual(try String(contentsOf: old, encoding: .utf8), "0123456789")
        XCTAssertEqual(try Data(contentsOf: log).count, 0)
    }

    func testRotatingTwiceKeepsLatestOldCopy() throws {
        let log = folder.appendingPathComponent("app.log")
        try Data("first-content".utf8).write(to: log)
        LogRotation.rotateIfNeeded(log, limit: 5)
        try Data("second-content".utf8).write(to: log)
        LogRotation.rotateIfNeeded(log, limit: 5)
        let old = folder.appendingPathComponent("app.log.1")
        XCTAssertEqual(try String(contentsOf: old, encoding: .utf8), "second-content")
        XCTAssertEqual(try Data(contentsOf: log).count, 0)
    }

    func testUnderLimitStaysUnchanged() throws {
        let log = folder.appendingPathComponent("app.log")
        try Data("abc".utf8).write(to: log)
        LogRotation.rotateIfNeeded(log, limit: 5)
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), "abc")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("app.log.1").path))
    }

    func testFileIsEmptiedWhenItCannotBeMoved() throws {
        let log = folder.appendingPathComponent("app.log")
        try Data("0123456789".utf8).write(to: log)
        // A folder where the old copy should go makes the move fail.
        let blocker = folder.appendingPathComponent("app.log.1", isDirectory: true)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocker.appendingPathComponent("keep"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        LogRotation.rotateIfNeeded(log, limit: 5)
        XCTAssertEqual(try Data(contentsOf: log).count, 0)
    }
}
