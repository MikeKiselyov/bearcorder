import XCTest
@testable import AppCore

final class DiskUsageTests: XCTestCase {
    func testFolderSizesAddUpAlongThePath() {
        let tree = DiskTree(rootName: "home")
        tree.addFile(components: ["Library", "Caches", "a.db"], bytes: 300)
        tree.addFile(components: ["Library", "Logs", "b.log"], bytes: 100)
        tree.addFile(components: ["Movies", "c.mov"], bytes: 1000)
        tree.addFile(components: ["note.txt"], bytes: 5)

        XCTAssertEqual(tree.root.bytes, 1405)
        XCTAssertEqual(tree.root.fileCount, 4)
        XCTAssertEqual(tree.node(at: ["Library"])?.bytes, 400)
        XCTAssertEqual(tree.node(at: ["Library", "Caches"])?.bytes, 300)
        XCTAssertNil(tree.node(at: ["Library", "Caches", "a.db"]), "files are not nodes")
    }

    func testChildrenAreBiggestFirst() {
        let tree = DiskTree(rootName: "home")
        tree.addFile(components: ["Small", "x"], bytes: 10)
        tree.addFile(components: ["Big", "y"], bytes: 900)
        tree.addFile(components: ["Middle", "z"], bytes: 50)
        var names: [String] = []
        for child in tree.root.children {
            names.append(child.name)
        }
        XCTAssertEqual(names, ["Big", "Middle", "Small"])
    }

    func testDeepFilesCountTowardTheDeepestKeptFolder() {
        let tree = DiskTree(rootName: "home", maxDepth: 2)
        tree.addFile(components: ["a", "b", "c", "d", "file"], bytes: 70)
        XCTAssertEqual(tree.node(at: ["a", "b"])?.bytes, 70)
        XCTAssertNil(tree.node(at: ["a", "b", "c"]))
    }

    func testTopFilesKeepsTheBiggestInOrder() {
        var top = TopFiles(limit: 3, minimumBytes: 10)
        top.consider(path: "/tiny", bytes: 5)
        top.consider(path: "/a", bytes: 100)
        top.consider(path: "/b", bytes: 300)
        top.consider(path: "/c", bytes: 200)
        top.consider(path: "/d", bytes: 50)
        top.consider(path: "/e", bytes: 400)
        var paths: [String] = []
        for file in top.files {
            paths.append(file.path)
        }
        XCTAssertEqual(paths, ["/e", "/b", "/c"])
    }

    /// "Move to Trash" in Largest files moves only the file the scan saw: same path, same file.
    func testLargestFileIsMovedOnlyWhenStillTheSameFile() throws {
        let files = FileManager.default
        let base = files.temporaryDirectory.appendingPathComponent("top-\(UUID().uuidString)")
        defer { try? files.removeItem(at: base) }
        try files.createDirectory(at: base, withIntermediateDirectories: true)
        let movie = base.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 1000).write(to: movie)
        let seen = TopFiles.File(path: movie.path, bytes: 1000, fileID: try XCTUnwrap(TopFiles.fileID(of: movie.path)))
        XCTAssertTrue(TopFiles.isStillTheSame(seen))

        // Another file under the same name since the scan.
        try files.removeItem(at: movie)
        try Data(repeating: 2, count: 1000).write(to: base.appendingPathComponent("other.mov"))
        try Data(repeating: 3, count: 1000).write(to: movie)
        XCTAssertFalse(TopFiles.isStillTheSame(seen))

        // A link in its place.
        try files.removeItem(at: movie)
        try files.createSymbolicLink(at: movie, withDestinationURL: base.appendingPathComponent("other.mov"))
        XCTAssertFalse(TopFiles.isStillTheSame(seen))

        try files.removeItem(at: movie)
        XCTAssertFalse(TopFiles.isStillTheSame(seen))
        XCTAssertFalse(TopFiles.isStillTheSame(TopFiles.File(path: base.appendingPathComponent("other.mov").path, bytes: 1000)))
    }

    /// Files inside an app or a library package are part of it: never offered on their own.
    func testFilesInsidePackagesAreLeftOut() throws {
        let files = FileManager.default
        let base = files.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        defer { try? files.removeItem(at: base) }
        let inApp = base.appendingPathComponent("Applications/Big.app/Contents/Resources/model.bin")
        let inPhotos = base.appendingPathComponent("Pictures/Photos Library.photoslibrary/originals/A/img.heic")
        let inBundle = base.appendingPathComponent("Library/Plugins/Thing.bundle/Contents/data")
        let plain = base.appendingPathComponent("Movies/holiday.mov")
        for file in [inApp, inPhotos, inBundle, plain] {
            try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 100).write(to: file)
        }
        XCTAssertTrue(TopFiles.isInsidePackage(inApp.path))
        XCTAssertTrue(TopFiles.isInsidePackage(inPhotos.path))
        XCTAssertTrue(TopFiles.isInsidePackage(inBundle.path))
        // Virtual machines and disk bundles, also when the app that makes them is not installed.
        for bundle in ["Linux.utm", "Windows 11.pvm", "Ubuntu.vmwarevm", "Backup.sparsebundle"] {
            let inside = base.appendingPathComponent("VMs/\(bundle)/Data/disk.img")
            try files.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 100).write(to: inside)
            XCTAssertTrue(TopFiles.isInsidePackage(inside.path), bundle)
        }
        XCTAssertFalse(TopFiles.isInsidePackage(plain.path))
        let seen = TopFiles.File(path: inApp.path, bytes: 100, fileID: try XCTUnwrap(TopFiles.fileID(of: inApp.path)))
        XCTAssertFalse(TopFiles.isStillTheSame(seen), "a file inside a package is never moved")
    }

}
