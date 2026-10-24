import XCTest
@testable import BugbearCore

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
}
