import AppCore
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

    func testTrashedItemsOnlyTheAppsOwn() throws {
        let item = try makeFolder(".Trash/node_modules 3")
        let ownTarget = RemovalTarget.trashedByApp(trashed: [item.standardizedFileURL.path])
        let foreignTarget = RemovalTarget.trashedByApp(trashed: [])
        XCTAssertNil(RemovalGate.refusal(for: item, target: ownTarget, home: home))
        XCTAssertEqual(RemovalGate.refusal(for: item, target: foreignTarget, home: home), .notTrashedByApp)
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

    /// A dependency folder that is its own repository (a .git folder or file) is refused.
    func testProjectFolderWithItsOwnRepositoryIsRefused() throws {
        let cloned = try makeFolder("Projects/app/node_modules")
        try makeFolder("Projects/app/node_modules/.git")
        XCTAssertEqual(RemovalGate.refusal(for: cloned, target: .projectFolder(.nodeModules), home: home), .ownRepository)
        let worktree = try makeFolder("Projects/rs/target")
        try "gitdir: /elsewhere".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(RemovalGate.refusal(for: worktree, target: .projectFolder(.cargoTarget), home: home), .ownRepository)
    }

    /// Project folders never come from ~/Library, in any case.
    func testProjectFolderInLibraryIsRefused() throws {
        let inLibrary = try makeFolder("Library/Mobile Documents/app/node_modules")
        XCTAssertEqual(RemovalGate.refusal(for: inLibrary, target: .projectFolder(.nodeModules), home: home), .inLibrary)
        let lowercase = home.appendingPathComponent("library/Mobile Documents/app/node_modules")
        XCTAssertEqual(RemovalGate.refusal(for: lowercase, target: .projectFolder(.nodeModules), home: home), .inLibrary)
        // Cache items live in ~/Library and stay allowed there.
        let cache = try makeFolder("Library/Caches/com.example.app")
        XCTAssertNil(RemovalGate.refusal(for: cache, target: .cacheItem(allowedRoots: [home.appendingPathComponent("Library/Caches")]), home: home))
    }


    /// The path recorded as checked must be the home's real path plus the path below it: a folder
    /// swapped for a link before it is recorded is not taken as checked.
    func testCheckedRealPathIsTheHomesPlusTheRelativePath() throws {
        let folder = try makeFolder("Projects/app/node_modules")
        let homeReal = try XCTUnwrap(RemovalGate.realPath(of: home))
        XCTAssertEqual(RemovalGate.checkedRealPath(of: folder, home: home), homeReal + "/Projects/app/node_modules")

        let elsewhere = try makeFolder("Elsewhere/app/node_modules")
        XCTAssertNotNil(RemovalGate.realPath(of: elsewhere))
        try fileManager.moveItem(at: home.appendingPathComponent("Projects/app"), to: home.appendingPathComponent("Projects/parked"))
        try fileManager.createSymbolicLink(at: home.appendingPathComponent("Projects/app"), withDestinationURL: home.appendingPathComponent("Elsewhere/app"))
        XCTAssertNil(RemovalGate.checkedRealPath(of: folder, home: home))
        XCTAssertFalse(RemovalGate.stillLeads(folder, to: RemovalGate.checkedRealPath(of: folder, home: home)))
    }

}
