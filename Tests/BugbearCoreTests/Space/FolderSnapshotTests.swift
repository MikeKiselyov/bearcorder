import BugbearCore
import XCTest

/// Before a ticked folder is removed it must still be the folder that was scanned.
final class FolderSnapshotTests: XCTestCase {
    var root: URL!
    let fileManager = FileManager.default
    let longAgo = Date(timeIntervalSince1970: 1_000_000)

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    func makeFolder(_ name: String) throws -> URL {
        let folder = root.appendingPathComponent(name)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func makeFile(_ name: String) throws -> URL {
        let file = root.appendingPathComponent(name)
        try Data("x".utf8).write(to: file)
        return file
    }

    func testSameFolderIsUnchanged() throws {
        let folder = try makeFolder("node_modules")
        let marker = try makeFile("package.json")
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: marker, projectRoot: root, projectChanged: longAgo))
        XCTAssertNil(snapshot.change(now: folder, lastChanged: { _ in self.longAgo }))
    }

    func testDeletedFolderIsGone() throws {
        let folder = try makeFolder("node_modules")
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: nil, projectRoot: nil, projectChanged: nil))
        try fileManager.removeItem(at: folder)
        XCTAssertEqual(snapshot.change(now: folder, lastChanged: { _ in self.longAgo }), .gone)
    }

    func testRecreatedFolderIsReplaced() throws {
        let folder = try makeFolder("node_modules")
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: nil, projectRoot: nil, projectChanged: nil))
        // Keep the old inode taken so the new folder cannot reuse its number.
        let parked = try makeFolder("parked")
        let parkedTarget = parked.appendingPathComponent("old")
        try fileManager.moveItem(at: folder, to: parkedTarget)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        XCTAssertEqual(snapshot.change(now: folder, lastChanged: { _ in self.longAgo }), .replaced)
    }

    func testMarkerRemoved() throws {
        let folder = try makeFolder("node_modules")
        let marker = try makeFile("package.json")
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: marker, projectRoot: nil, projectChanged: nil))
        try fileManager.removeItem(at: marker)
        XCTAssertEqual(snapshot.change(now: folder, lastChanged: { _ in self.longAgo }), .markerGone)
    }

    func testChangedProjectIsSkipped() throws {
        let folder = try makeFolder("node_modules")
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: nil, projectRoot: root, projectChanged: longAgo))
        let later = longAgo.addingTimeInterval(60)
        XCTAssertEqual(snapshot.change(now: folder, lastChanged: { _ in later }), .projectChanged)
    }

    func testCacheItemWithoutProjectIgnoresLastChanged() throws {
        let folder = try makeFolder("cache-item")
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: nil, projectRoot: nil, projectChanged: nil))
        XCTAssertNil(snapshot.change(now: folder, lastChanged: { _ in Date.distantFuture }))
    }

    func testSnapshotOfMissingFolderIsNil() {
        let missing = root.appendingPathComponent("nothing")
        XCTAssertNil(FolderSnapshot.take(of: missing, marker: nil, projectRoot: nil, projectChanged: nil))
    }

    func testLinkIsNotFollowed() throws {
        let real = try makeFolder("real")
        let link = root.appendingPathComponent("link")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: real)
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: link, marker: nil, projectRoot: nil, projectChanged: nil))
        let realSnapshot = try XCTUnwrap(FolderSnapshot.take(of: real, marker: nil, projectRoot: nil, projectChanged: nil))
        XCTAssertNotEqual(snapshot.fileID, realSnapshot.fileID)
    }

    func testModifiedFolderIsReported() throws {
        let folder = try makeFolder("node_modules")
        try fileManager.setAttributes([.modificationDate: longAgo], ofItemAtPath: folder.path)
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: nil, projectRoot: nil, projectChanged: nil))
        try Data("x".utf8).write(to: folder.appendingPathComponent("new.js"))
        try fileManager.setAttributes([.modificationDate: longAgo.addingTimeInterval(500)], ofItemAtPath: folder.path)
        XCTAssertEqual(snapshot.change(now: folder, lastChanged: { _ in self.longAgo }), .modified)
    }

    func testCheckOrderIsGoneReplacedModifiedMarker() throws {
        let folder = try makeFolder("node_modules")
        let marker = try makeFile("package.json")
        try fileManager.setAttributes([.modificationDate: longAgo], ofItemAtPath: folder.path)
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: marker, projectRoot: root, projectChanged: longAgo))
        try fileManager.removeItem(at: marker)
        try fileManager.setAttributes([.modificationDate: longAgo.addingTimeInterval(500)], ofItemAtPath: folder.path)
        let later = longAgo.addingTimeInterval(60)
        XCTAssertEqual(snapshot.change(now: folder, lastChanged: { _ in later }), .modified)
        try fileManager.removeItem(at: folder)
        XCTAssertEqual(snapshot.change(now: folder, lastChanged: { _ in later }), .gone)
    }
}
