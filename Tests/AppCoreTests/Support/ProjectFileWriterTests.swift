import AppCore
import XCTest

/// Editors save their project through this writer: off the main thread, whole files only, the last
/// edit written on close and quit, and a failed write reported instead of swallowed.
final class ProjectFileWriterTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    private func text(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func testFlushWritesTheLastScheduledData() {
        let url = folder.appendingPathComponent("project.json")
        let writer = ProjectFileWriter(url: url, delay: 5, onFailure: { _ in })
        writer.schedule(Data("A".utf8))
        writer.schedule(Data("B".utf8))
        writer.flush()
        XCTAssertEqual(text(at: url), "B")
    }

    func testScheduledDataIsWrittenAfterTheDelayWithoutFlush() {
        let url = folder.appendingPathComponent("project.json")
        let writer = ProjectFileWriter(url: url, delay: 0.05, onFailure: { _ in })
        writer.schedule(Data("A".utf8))
        let deadline = Date().addingTimeInterval(1)
        while text(at: url) == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(text(at: url), "A")
        withExtendedLifetime(writer) {}
    }

    func testFlushWithNothingPendingLeavesTheFileAlone() throws {
        let url = folder.appendingPathComponent("project.json")
        try Data("old".utf8).write(to: url)
        let writer = ProjectFileWriter(url: url, delay: 0.05, onFailure: { _ in })
        writer.flush()
        XCTAssertEqual(text(at: url), "old")

        writer.schedule(Data("new".utf8))
        writer.flush()
        try Data("changed elsewhere".utf8).write(to: url)
        writer.flush()
        XCTAssertEqual(text(at: url), "changed elsewhere", "the data was written once, not again")
    }

    func testAMissingFolderReportsTheFailure() throws {
        let other = folder.appendingPathComponent("other.json")
        try Data("keep".utf8).write(to: other)
        let url = folder.appendingPathComponent("missing/project.json")
        let failures = FailureCounter()
        let writer = ProjectFileWriter(url: url, delay: 5, onFailure: { _ in failures.add() })
        writer.schedule(Data("A".utf8))
        writer.flush()
        XCTAssertEqual(failures.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(text(at: other), "keep")
    }

    func testAGoodFileStaysWhenALaterWriteFails() throws {
        let url = folder.appendingPathComponent("project.json")
        let failures = FailureCounter()
        let writer = ProjectFileWriter(url: url, delay: 5, onFailure: { _ in failures.add() })
        writer.schedule(Data("good".utf8))
        writer.flush()
        XCTAssertEqual(failures.count, 0)

        // A read-only folder: an atomic write cannot create its temporary file or replace the old one.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        writer.schedule(Data("half".utf8))
        writer.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(text(at: url), "good")
    }

    func testASuccessfulWriteIsReported() throws {
        let url = folder.appendingPathComponent("project.json")
        let successes = FailureCounter()
        let failures = FailureCounter()
        let writer = ProjectFileWriter(url: url, delay: 5, onFailure: { _ in failures.add() }, onSuccess: { successes.add() })
        writer.flush()
        XCTAssertEqual(successes.count, 0, "nothing was written")
        writer.schedule(Data("A".utf8))
        writer.flush()
        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(failures.count, 0)
    }

    func testFlushAllWritesEveryLiveWriter() {
        let first = folder.appendingPathComponent("first.json")
        let second = folder.appendingPathComponent("second.json")
        let firstWriter = ProjectFileWriter(url: first, delay: 5, onFailure: { _ in })
        let secondWriter = ProjectFileWriter(url: second, delay: 5, onFailure: { _ in })
        firstWriter.schedule(Data("one".utf8))
        secondWriter.schedule(Data("two".utf8))
        ProjectFileWriter.flushAll()
        XCTAssertEqual(text(at: first), "one")
        XCTAssertEqual(text(at: second), "two")
    }
}

/// Counts failures reported from the writer's queue.
private final class FailureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func add() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
