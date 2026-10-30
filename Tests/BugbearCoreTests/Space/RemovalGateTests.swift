import BugbearCore
import XCTest

/// Nothing is removed unless the gate allows it: inside the home folder, no links, only the declared names.
final class RemovalGateTests: XCTestCase {
    var home: URL!
    let fileManager = FileManager.default

    override func setUpWithError() throws {
        let base = fileManager.temporaryDirectory.appendingPathComponent("gate-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: home.deletingLastPathComponent())
    }

    @discardableResult
    func makeFolder(_ relativePath: String) throws -> URL {
        let folder = home.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testInsideHomeAllowedFolderPasses() throws {
        let folder = try makeFolder("Projects/app/node_modules")
        XCTAssertNil(RemovalGate.refusal(for: folder, target: .projectFolder(.nodeModules), home: home))
    }

    func testOutsideHomeIsRefused() throws {
        let outside = fileManager.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)/x/node_modules")
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: outside.deletingLastPathComponent().deletingLastPathComponent()) }
        XCTAssertEqual(RemovalGate.refusal(for: outside, target: .projectFolder(.nodeModules), home: home), .outsideHome)
    }

    func testHomeAndTopFoldersAreRefused() throws {
        let top = try makeFolder("Projects")
        XCTAssertEqual(RemovalGate.refusal(for: home, target: .projectFolder(.nodeModules), home: home), .homeOrTopFolder)
        XCTAssertEqual(RemovalGate.refusal(for: top, target: .projectFolder(.nodeModules), home: home), .homeOrTopFolder)
    }

    func testDotDotIsResolvedFirst() throws {
        let folder = try makeFolder("Projects/app/node_modules")
        let climbing = folder.appendingPathComponent("../../..")
        XCTAssertEqual(RemovalGate.refusal(for: climbing, target: .projectFolder(.nodeModules), home: home), .homeOrTopFolder)
    }

    func testLinkInPathIsRefused() throws {
        let app = try makeFolder("Projects/app/node_modules").deletingLastPathComponent()
        let link = home.appendingPathComponent("Projects/link-to-app")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: app)
        let throughLink = link.appendingPathComponent("node_modules")
        XCTAssertEqual(RemovalGate.refusal(for: throughLink, target: .projectFolder(.nodeModules), home: home), .throughLink)

        let real = try makeFolder("Projects/other/real")
        let linkedFolder = home.appendingPathComponent("Projects/other/node_modules")
        try fileManager.createSymbolicLink(at: linkedFolder, withDestinationURL: real)
        XCTAssertEqual(RemovalGate.refusal(for: linkedFolder, target: .projectFolder(.nodeModules), home: home), .throughLink)
    }

    func testWrongNameIsRefused() throws {
        let folder = try makeFolder("Projects/app/src")
        XCTAssertEqual(RemovalGate.refusal(for: folder, target: .projectFolder(.nodeModules), home: home), .notAllowedName)
    }

    func testCacheItemMustBeInsideItsRoot() throws {
        let root = try makeFolder("Library/Caches")
        let item = try makeFolder("Library/Caches/com.x")
        let other = try makeFolder("Documents/a")
        let target = RemovalTarget.cacheItem(allowedRoots: [root])
        XCTAssertNil(RemovalGate.refusal(for: item, target: target, home: home))
        XCTAssertEqual(RemovalGate.refusal(for: root, target: target, home: home), .notInDeclaredCache)
        XCTAssertEqual(RemovalGate.refusal(for: other, target: target, home: home), .notInDeclaredCache)
    }

    func testTrashedItemsOnlyBugbearsOwn() throws {
        let item = try makeFolder(".Trash/node_modules 3")
        let ownTarget = RemovalTarget.trashedByBugbear(trashed: [item.standardizedFileURL.path])
        let foreignTarget = RemovalTarget.trashedByBugbear(trashed: [])
        XCTAssertNil(RemovalGate.refusal(for: item, target: ownTarget, home: home))
        XCTAssertEqual(RemovalGate.refusal(for: item, target: foreignTarget, home: home), .notTrashedByBugbear)
    }

    func testMissingIsRefused() {
        let missing = home.appendingPathComponent("Projects/app/node_modules")
        XCTAssertEqual(RemovalGate.refusal(for: missing, target: .projectFolder(.nodeModules), home: home), .missing)
    }

    func testFolderNamesOfEveryKind() {
        XCTAssertEqual(DependencyKind.nodeModules.folderNames, ["node_modules"])
        XCTAssertEqual(DependencyKind.pythonVenv.folderNames, [".venv", "venv"])
        XCTAssertEqual(DependencyKind.gradleCache.folderNames, [".gradle"])
    }
}
