import BugbearCore
import XCTest

/// A cache category is a list: one item per direct child, with its size and a snapshot.
final class CacheItemsTests: XCTestCase {
    var root: URL!
    let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("cache-items-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    /// A child folder holding one file of `size` bytes (0 = no file).
    @discardableResult
    func makeChild(_ name: String, size: Int = 0, in parent: URL? = nil) throws -> URL {
        let folder = (parent ?? root).appendingPathComponent(name)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if size > 0 {
            try Data(repeating: 1, count: size).write(to: folder.appendingPathComponent("data"))
        }
        return folder
    }

    func plainName(_ url: URL) -> String {
        return url.lastPathComponent
    }

    func testOneItemPerChild() throws {
        try makeChild("small", size: 1_000)
        try makeChild("big", size: 200_000)
        try makeChild("middle", size: 50_000)
        let items = CacheItems.children(of: [root], keep: [], nameFor: plainName)
        XCTAssertEqual(items.map { item in item.name }, ["big", "middle", "small"])
        XCTAssertTrue(items[0].bytes > items[1].bytes)
        XCTAssertTrue(items[1].bytes > items[2].bytes)
        XCTAssertEqual(items[0].url.lastPathComponent, "big")
        XCTAssertNil(items[0].snapshot.marker)
        XCTAssertNil(items[0].snapshot.projectRoot)
    }

    func testChildrenOfSeveralFolders() throws {
        let first = try makeChild("first")
        let second = try makeChild("second")
        try makeChild("a", size: 10_000, in: first)
        try makeChild("b", size: 20_000, in: second)
        let items = CacheItems.children(of: [first, second], keep: [], nameFor: plainName)
        XCTAssertEqual(items.map { item in item.name }, ["b", "a"])
    }

    func testKeptAndAppleChildrenSkipped() throws {
        try makeChild("real", size: 10_000)
        let kept = try makeChild("kept", size: 10_000)
        try makeChild("com.apple.thing", size: 10_000)
        let items = CacheItems.children(of: [root], keep: [kept.standardizedFileURL.path], nameFor: plainName)
        XCTAssertEqual(items.map { item in item.name }, ["real"])
    }

    func testLinksSkipped() throws {
        let target = try makeChild("target", size: 10_000)
        let outside = fileManager.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: outside) }
        try fileManager.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        let items = CacheItems.children(of: [root], keep: [], nameFor: plainName)
        XCTAssertEqual(items.map { item in item.name }, ["target"])
        XCTAssertEqual(items[0].url.lastPathComponent, target.lastPathComponent)
    }

    func testEmptyChildrenSkipped() throws {
        try makeChild("empty")
        try makeChild("full", size: 10_000)
        let items = CacheItems.children(of: [root], keep: [], nameFor: plainName)
        XCTAssertEqual(items.map { item in item.name }, ["full"])
    }

    func testNameComesFromCallback() throws {
        try makeChild("com.example.app", size: 10_000)
        let items = CacheItems.children(of: [root], keep: []) { url in "App for \(url.lastPathComponent)" }
        XCTAssertEqual(items.map { item in item.name }, ["App for com.example.app"])
    }

    func testMissingFolderGivesNoItems() {
        let missing = root.appendingPathComponent("nope")
        XCTAssertEqual(CacheItems.children(of: [missing], keep: [], nameFor: plainName), [])
    }

    func testPlainFileChildCounts() throws {
        try Data(repeating: 1, count: 20_000).write(to: root.appendingPathComponent("blob.bin"))
        let items = CacheItems.children(of: [root], keep: [], nameFor: plainName)
        XCTAssertEqual(items.map { item in item.name }, ["blob.bin"])
        XCTAssertTrue(items[0].bytes >= 20_000)
    }
}
