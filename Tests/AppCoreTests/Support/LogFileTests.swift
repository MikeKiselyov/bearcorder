import XCTest
@testable import AppCore

final class LogFileTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("log-file-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func text(_ url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testLinesReachTheFileRightAway() throws {
        // The folder is not there yet: the first line makes it.
        let url = folder.appendingPathComponent("Logs/app.log")
        let log = LogFile(url: url, limit: 1_000)
        log.append("first")
        XCTAssertEqual(try text(url), "first\n")
        log.append("second")
        XCTAssertEqual(try text(url), "first\nsecond\n")
    }

    func testLinesGoAfterWhatTheFileHad() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("app.log")
        try Data("earlier run\n".utf8).write(to: url)
        LogFile(url: url, limit: 1_000).append("this run")
        XCTAssertEqual(try text(url), "earlier run\nthis run\n")
    }

    func testPastTheLimitTheFileStartsOver() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("app.log")
        let old = URL(fileURLWithPath: url.path + ".1")
        // What an earlier run left counts towards the limit.
        try Data("12345678\n".utf8).write(to: url)
        let log = LogFile(url: url, limit: 20)
        log.append("abcdefgh")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "18 bytes, under the limit")
        log.append("over")
        XCTAssertEqual(try text(old), "12345678\nabcdefgh\nover\n")
        XCTAssertEqual(try text(url), "")
        log.append("new file")
        XCTAssertEqual(try text(url), "new file\n")
        XCTAssertEqual(try text(old), "12345678\nabcdefgh\nover\n")
    }

    func testDeletedFileIsMadeAgain() throws {
        let url = folder.appendingPathComponent("app.log")
        let log = LogFile(url: url, limit: 1_000)
        log.append("first")
        try FileManager.default.removeItem(at: url)
        log.append("after delete")
        XCTAssertEqual(try text(url), "after delete\n")
        try FileManager.default.removeItem(at: folder)
        log.append("after folder delete")
        XCTAssertEqual(try text(url), "after folder delete\n")
    }
}
