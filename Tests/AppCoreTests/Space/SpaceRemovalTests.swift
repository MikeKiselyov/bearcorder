import AppCore
import XCTest

/// What Space removes: only ticked rows that pass the gate and are still what the scan saw,
/// on a made-up home with a test Trash.
final class SpaceRemovalTests: XCTestCase {
    var base: URL!
    var home: URL!
    var trash: URL!
    let fileManager = FileManager.default
    let kinds: Set<DependencyKind> = Set(DependencyKind.allCases)

    override func setUpWithError() throws {
        base = fileManager.temporaryDirectory.appendingPathComponent("removal-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        // Inside the home, like ~/.Trash: delete for good goes through the gate, which stays in the home.
        trash = home.appendingPathComponent(".Trash")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: base)
    }

    @discardableResult
    func makeFile(_ relativePath: String, in folder: URL? = nil, text: String = "data") throws -> URL {
        let file = (folder ?? home).appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func context(projectsToTrash: Bool = true, trashOverride: URL?? = nil, cleanCommand: [String]? = nil, homeIsOverridden: Bool = true) -> SpaceRemoval.Context {
        var trashFolder: URL? = trash
        if let given = trashOverride {
            trashFolder = given
        }
        return SpaceRemoval.Context(
            home: home,
            trashOverride: trashFolder,
            projectsToTrash: projectsToTrash,
            kinds: kinds,
            cleanCommand: cleanCommand,
            homeIsOverridden: homeIsOverridden
        )
    }

    /// A project with package.json, a source file and a node_modules folder, as a scan would plan it.
    func makeProjectPlan() throws -> SpaceRemoval.Plan {
        let project = home.appendingPathComponent("Projects/app")
        let marker = try makeFile("package.json", in: project)
        try makeFile("index.js", in: project)
        try makeFile("node_modules/left-pad/index.js", in: project)
        let folder = project.appendingPathComponent("node_modules")
        let projectChanged = ProjectDependencies.lastChanged(of: project, kinds: kinds)
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: marker, projectRoot: project, projectChanged: projectChanged))
        return SpaceRemoval.Plan(url: folder, bytes: FileSizes.folder(folder), snapshot: snapshot, way: .projectFolder(.nodeModules))
    }

    func trashContents() throws -> [String] {
        return try fileManager.contentsOfDirectory(atPath: trash.path)
    }

    func noLog(_ message: String) {}

    func testRemovesTickedProjectFolderToTrash() throws {
        let plan = try makeProjectPlan()
        let result = SpaceRemoval.remove([plan], context: context(), log: noLog)
        XCTAssertEqual(result.removed, [plan.url.path])
        XCTAssertTrue(result.skipped.isEmpty)
        XCTAssertFalse(fileManager.fileExists(atPath: plan.url.path))
        let moved = trash.appendingPathComponent("node_modules").standardizedFileURL
        XCTAssertTrue(fileManager.fileExists(atPath: moved.appendingPathComponent("left-pad/index.js").path))
        XCTAssertEqual(result.trashed, [moved])
        XCTAssertNotNil(result.trashedSnapshots[moved.path])
        XCTAssertEqual(result.trashedBytes[moved.path], plan.bytes)
        XCTAssertEqual(result.trashedTotal, plan.bytes)
        XCTAssertEqual(result.freedBytes, plan.bytes)
    }

    func testDeletesWhenProjectsNotToTrash() throws {
        let plan = try makeProjectPlan()
        let result = SpaceRemoval.remove([plan], context: context(projectsToTrash: false), log: noLog)
        XCTAssertEqual(result.removed, [plan.url.path])
        XCTAssertFalse(fileManager.fileExists(atPath: plan.url.path))
        XCTAssertEqual(try trashContents(), [])
        XCTAssertTrue(result.trashed.isEmpty)
    }

    func testGateRefusalStopsRemoval() throws {
        try makeFile("Projects/app/package.json")
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: home, marker: nil, projectRoot: nil, projectChanged: nil))
        let plan = SpaceRemoval.Plan(url: home, bytes: 1, snapshot: snapshot, way: .projectFolder(.nodeModules))
        let result = SpaceRemoval.remove([plan], context: context(), log: noLog)
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertEqual(result.skipped.first?.reason, .refused(.homeOrTopFolder))
        XCTAssertTrue(fileManager.fileExists(atPath: home.appendingPathComponent("Projects/app/package.json").path))
        XCTAssertEqual(try trashContents(), [])
    }

    /// Changes one thing after the scan and checks the folder is skipped with that change and left alone.
    func checkChangedFolderIsSkipped(_ expected: SnapshotChange, reason: SpaceRemoval.SkipReason? = nil, change: (SpaceRemoval.Plan) throws -> Void, file: StaticString = #filePath, line: UInt = #line) throws {
        var expectedReason = SpaceRemoval.SkipReason.changed(expected)
        if let reason = reason {
            expectedReason = reason
        }
        let plan = try makeProjectPlan()
        try change(plan)
        let before = try? fileManager.contentsOfDirectory(atPath: plan.url.path)
        let result = SpaceRemoval.remove([plan], context: context(), log: noLog)
        XCTAssertTrue(result.removed.isEmpty, "\(expected)", file: file, line: line)
        XCTAssertEqual(result.skipped.count, 1, "\(expected)", file: file, line: line)
        XCTAssertEqual(result.skipped.first?.reason, expectedReason, file: file, line: line)
        XCTAssertEqual(try? fileManager.contentsOfDirectory(atPath: plan.url.path), before, "\(expected)", file: file, line: line)
        XCTAssertEqual(try trashContents(), [], "\(expected)", file: file, line: line)
        try? fileManager.removeItem(at: home)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    func testChangedFolderIsSkipped() throws {
        // A folder that is gone stops at the gate first (it checks the folder exists), as today.
        try checkChangedFolderIsSkipped(.gone, reason: .refused(.missing)) { plan in
            try self.fileManager.removeItem(at: plan.url)
        }
        try checkChangedFolderIsSkipped(.replaced) { plan in
            // Park the old folder so the new one cannot reuse its inode number.
            let parked = self.base.appendingPathComponent("parked-\(UUID().uuidString)")
            try self.fileManager.moveItem(at: plan.url, to: parked)
            try self.fileManager.createDirectory(at: plan.url, withIntermediateDirectories: false)
        }
        try checkChangedFolderIsSkipped(.modified) { plan in
            try self.makeFile("new.js", in: plan.url)
        }
        try checkChangedFolderIsSkipped(.markerGone) { plan in
            try self.fileManager.removeItem(at: plan.url.deletingLastPathComponent().appendingPathComponent("package.json"))
        }
        try checkChangedFolderIsSkipped(.projectChanged) { plan in
            let source = plan.url.deletingLastPathComponent().appendingPathComponent("index.js")
            try "edited".write(to: source, atomically: false, encoding: .utf8)
            try self.fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: source.path)
        }
    }

    func testMadeUpHomeWithoutTestTrashRefusesTrash() throws {
        let plan = try makeProjectPlan()
        // The context below means the real Trash. If the guard ever breaks, the move must fail
        // instead of putting the test folder into the user's Trash: macOS moves an item to the
        // Trash by renaming it, which a read-only parent folder refuses.
        let project = plan.url.deletingLastPathComponent()
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: project.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: project.path) }
        let result = SpaceRemoval.remove([plan], context: context(projectsToTrash: true, trashOverride: .some(nil), homeIsOverridden: true), log: noLog)
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.skipped.first?.reason, .notAllowed)
        XCTAssertTrue(fileManager.fileExists(atPath: plan.url.appendingPathComponent("left-pad/index.js").path))
        XCTAssertTrue(result.trashed.isEmpty)
    }

    func testFolderContentsOnlyInsideDeclaredFolders() throws {
        let declared = home.appendingPathComponent("Library/Caches/Homebrew")
        try makeFile("one.tar.gz", in: declared, text: String(repeating: "a", count: 5000))
        try makeFile("downloads/two.tar.gz", in: declared, text: String(repeating: "b", count: 5000))
        let outside = try makeFile("outside/keep.txt", in: base)
        try fileManager.createSymbolicLink(at: declared.appendingPathComponent("link"), withDestinationURL: outside.deletingLastPathComponent())
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: declared, marker: nil, projectRoot: nil, projectChanged: nil))
        let plan = SpaceRemoval.Plan(url: declared, bytes: FileSizes.folder(declared), snapshot: snapshot, way: .folderContents(declaredFolders: [declared.standardizedFileURL]))

        let result = SpaceRemoval.remove([plan], context: context(), log: noLog)

        XCTAssertFalse(fileManager.fileExists(atPath: declared.appendingPathComponent("one.tar.gz").path))
        XCTAssertFalse(fileManager.fileExists(atPath: declared.appendingPathComponent("downloads").path))
        XCTAssertTrue(fileManager.fileExists(atPath: declared.path), "the folder itself stays")
        XCTAssertTrue(fileManager.fileExists(atPath: outside.path), "the link target outside is untouched")
        // The link itself is refused by the gate, so the row is reported, as today.
        let linkValues = try declared.appendingPathComponent("link").resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(linkValues.isSymbolicLink, true)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertEqual(result.skipped.first?.reason, .refused(.throughLink))
        XCTAssertGreaterThan(result.freedBytes, 0)
        XCTAssertEqual(try trashContents(), [])
    }

    func testFolderContentsRefusesUndeclaredFolder() throws {
        let declared = home.appendingPathComponent("Library/Caches/Homebrew")
        let other = home.appendingPathComponent("Library/Caches/Other")
        try makeFile("keep.txt", in: declared)
        let kept = try makeFile("keep.txt", in: other)
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: other, marker: nil, projectRoot: nil, projectChanged: nil))
        let plan = SpaceRemoval.Plan(url: other, bytes: FileSizes.folder(other), snapshot: snapshot, way: .folderContents(declaredFolders: [declared.standardizedFileURL]))

        let result = SpaceRemoval.remove([plan], context: context(), log: noLog)

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.skipped.first?.reason, .refused(.notInDeclaredCache))
        XCTAssertTrue(fileManager.fileExists(atPath: kept.path))
        XCTAssertEqual(result.freedBytes, 0)
    }

    func testDeleteForGoodRefusesSwappedItem() throws {
        let plan = try makeProjectPlan()
        let removal = SpaceRemoval.remove([plan], context: context(), log: noLog)
        let moved = try XCTUnwrap(removal.trashed.first)
        // The trashed folder is put back and another one is trashed under the same name.
        let parked = base.appendingPathComponent("put-back")
        try fileManager.moveItem(at: moved, to: parked)
        let other = try makeFile("node_modules/other.js", in: trash).deletingLastPathComponent()

        let outcome = SpaceRemoval.deleteForGood(removal.trashed, snapshots: removal.trashedSnapshots, context: context(), log: noLog)

        XCTAssertTrue(fileManager.fileExists(atPath: other.appendingPathComponent("other.js").path))
        XCTAssertEqual(outcome.skipped.count, 1)
        XCTAssertEqual(outcome.skipped.first?.path, moved.path)
        XCTAssertEqual(outcome.skipped.first?.reason, .trashReplaced)
        // As today: a replaced item is reported, not kept for another try.
        XCTAssertEqual(outcome.left, [])
    }

    func testDeleteForGoodDeletesTrashedItem() throws {
        let plan = try makeProjectPlan()
        let removal = SpaceRemoval.remove([plan], context: context(), log: noLog)
        let moved = try XCTUnwrap(removal.trashed.first)
        try makeFile("someone-else.txt", in: trash)

        let outcome = SpaceRemoval.deleteForGood(removal.trashed, snapshots: removal.trashedSnapshots, context: context(), log: noLog)

        XCTAssertFalse(fileManager.fileExists(atPath: moved.path))
        XCTAssertTrue(fileManager.fileExists(atPath: trash.appendingPathComponent("someone-else.txt").path))
        XCTAssertEqual(outcome.left, [])
        XCTAssertTrue(outcome.skipped.isEmpty)
    }

    /// Tools write into their caches all the time, so a cache item whose date moved since the scan
    /// is still removed; only a project folder is skipped for that.
    func testModifiedCacheItemIsStillRemoved() throws {
        let root = home.appendingPathComponent("Library/Caches/com.example.app")
        let item = root.appendingPathComponent("data")
        try makeFile("blob.bin", in: item)
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: item, marker: nil, projectRoot: nil, projectChanged: nil))
        try fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: item.path)
        XCTAssertEqual(snapshot.change(now: item, lastChanged: { _ in Date.distantPast }), .modified, "the test really changes the date")
        let plan = SpaceRemoval.Plan(url: item, bytes: FileSizes.folder(item), snapshot: snapshot, way: .cacheItem(allowedRoots: [root.standardizedFileURL]))

        let result = SpaceRemoval.remove([plan], context: context(), log: noLog)

        XCTAssertFalse(fileManager.fileExists(atPath: item.path))
        XCTAssertEqual(result.removed, [item.standardizedFileURL.path])
        XCTAssertTrue(result.skipped.isEmpty)
    }

    /// Delete for good only works inside the Trash folder: a listed item elsewhere in the home,
    /// even one with a record that still matches, is kept and handed back.
    func testDeleteForGoodRefusesItemOutsideTheTrash() throws {
        let plan = try makeProjectPlan()
        let folder = plan.url.standardizedFileURL
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: nil, projectRoot: nil, projectChanged: nil))

        let outcome = SpaceRemoval.deleteForGood([folder], snapshots: [folder.path: snapshot], context: context(), log: noLog)

        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("left-pad/index.js").path))
        XCTAssertEqual(outcome.left, [folder])
        XCTAssertTrue(outcome.skipped.isEmpty)
    }

    /// An item in the Trash with no record of what was moved there cannot be checked, so it stays.
    func testDeleteForGoodKeepsItemWithoutRecord() throws {
        let plan = try makeProjectPlan()
        let removal = SpaceRemoval.remove([plan], context: context(), log: noLog)
        let moved = try XCTUnwrap(removal.trashed.first)

        let outcome = SpaceRemoval.deleteForGood(removal.trashed, snapshots: [:], context: context(), log: noLog)

        XCTAssertTrue(fileManager.fileExists(atPath: moved.appendingPathComponent("left-pad/index.js").path))
        XCTAssertEqual(outcome.left, [moved])
        XCTAssertTrue(outcome.skipped.isEmpty)
    }

    func testCleanCommandNotRunForMadeUpHome() throws {
        let folder = home.appendingPathComponent("go/pkg/mod")
        try makeFile("cache/download/x.zip", in: folder)
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: nil, projectRoot: nil, projectChanged: nil))
        let plan = SpaceRemoval.Plan(url: folder, bytes: FileSizes.folder(folder), snapshot: snapshot, way: .folderContents(declaredFolders: [folder.standardizedFileURL]))

        let result = SpaceRemoval.remove([plan], context: context(cleanCommand: ["/usr/bin/false"]), log: noLog)

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertEqual(result.skipped.first?.reason, .notAllowed)
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("cache/download/x.zip").path))
    }

    /// Something put into the trashed folder after the app moved it there is not deleted with it:
    /// the folder is kept and reported.
    func testDeleteForGoodKeepsItemChangedInTheTrash() throws {
        let plan = try makeProjectPlan()
        let removal = SpaceRemoval.remove([plan], context: context(), log: noLog)
        let moved = try XCTUnwrap(removal.trashed.first)
        try makeFile("put-here-later.txt", in: moved)

        let outcome = SpaceRemoval.deleteForGood(removal.trashed, snapshots: removal.trashedSnapshots, context: context(), log: noLog)

        XCTAssertTrue(fileManager.fileExists(atPath: moved.appendingPathComponent("put-here-later.txt").path))
        XCTAssertTrue(fileManager.fileExists(atPath: moved.appendingPathComponent("left-pad/index.js").path))
        XCTAssertEqual(outcome.skipped.count, 1)
        XCTAssertEqual(outcome.skipped.first?.path, moved.path)
        XCTAssertEqual(outcome.skipped.first?.reason, .changedInTrash)
    }

    /// Finder writes .DS_Store into a folder it shows; that alone does not keep the folder.
    func testDeleteForGoodIgnoresFindersDSStore() throws {
        let plan = try makeProjectPlan()
        let removal = SpaceRemoval.remove([plan], context: context(), log: noLog)
        let moved = try XCTUnwrap(removal.trashed.first)
        let dsStore = try makeFile(".DS_Store", in: moved)
        try fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: moved.path)
        XCTAssertTrue(fileManager.fileExists(atPath: dsStore.path))

        let outcome = SpaceRemoval.deleteForGood(removal.trashed, snapshots: removal.trashedSnapshots, context: context(), log: noLog)

        XCTAssertFalse(fileManager.fileExists(atPath: moved.path))
        XCTAssertEqual(outcome.left, [])
        XCTAssertTrue(outcome.skipped.isEmpty)
    }

    /// The gate's "trashed by the app" check uses the record of what was trashed, not the list
    /// being deleted: an item with no record is refused there.
    func testDeleteForGoodGateRefusesItemWithoutRecord() throws {
        let plan = try makeProjectPlan()
        let removal = SpaceRemoval.remove([plan], context: context(), log: noLog)
        var messages: [String] = []

        _ = SpaceRemoval.deleteForGood(removal.trashed, snapshots: [:], context: context(), log: { message in messages.append(message) })

        XCTAssertTrue(messages.contains(where: { message in message.contains("notTrashedByApp") }), "\(messages)")
    }


    /// The project folder above node_modules is swapped for a link between the gate's check and
    /// the removal: what is behind the link stays, the row is refused.
    func raceSwapsProjectForLink(_ plan: SpaceRemoval.Plan) throws -> (elsewhere: URL, swap: (URL) -> Void) {
        let project = plan.url.deletingLastPathComponent()
        let elsewhere = home.appendingPathComponent("Elsewhere/app")
        try makeFile("package.json", in: elsewhere)
        try makeFile("node_modules/precious/index.js", in: elsewhere)
        let parked = home.appendingPathComponent("Projects/app-parked")
        let fileManager = self.fileManager
        let swap: (URL) -> Void = { _ in
            try? fileManager.moveItem(at: project, to: parked)
            try? fileManager.createSymbolicLink(at: project, withDestinationURL: elsewhere)
        }
        return (elsewhere: elsewhere, swap: swap)
    }

    func testLinkSwappedInAfterTheGateIsRefusedWhenTrashing() throws {
        let plan = try makeProjectPlan()
        let race = try raceSwapsProjectForLink(plan)

        let result = SpaceRemoval.remove([plan], context: context(), log: noLog, beforeRemoving: race.swap)

        XCTAssertTrue(fileManager.fileExists(atPath: race.elsewhere.appendingPathComponent("node_modules/precious/index.js").path))
        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.skipped.first?.reason, .refused(.throughLink))
        XCTAssertEqual(try trashContents(), [])
    }

    func testLinkSwappedInAfterTheGateIsRefusedWhenDeleting() throws {
        let plan = try makeProjectPlan()
        let race = try raceSwapsProjectForLink(plan)

        let result = SpaceRemoval.remove([plan], context: context(projectsToTrash: false), log: noLog, beforeRemoving: race.swap)

        XCTAssertTrue(fileManager.fileExists(atPath: race.elsewhere.appendingPathComponent("node_modules/precious/index.js").path))
        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.skipped.first?.reason, .refused(.throughLink))
    }

    /// The same for a child of a whole-folder cache: its folder is swapped for a link.
    func testLinkSwappedInAfterTheGateIsRefusedForFolderContents() throws {
        let folder = home.appendingPathComponent(".npm/_cacache")
        try makeFile("index-v5/entry", in: folder)
        let elsewhere = home.appendingPathComponent("Documents/mine")
        try makeFile("index-v5/precious.txt", in: elsewhere)
        let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: nil, projectRoot: nil, projectChanged: nil))
        let plan = SpaceRemoval.Plan(url: folder, bytes: FileSizes.folder(folder), snapshot: snapshot, way: .folderContents(declaredFolders: [folder.standardizedFileURL]))
        let parked = home.appendingPathComponent(".npm/parked")
        let fileManager = self.fileManager
        let swap: (URL) -> Void = { _ in
            try? fileManager.moveItem(at: folder, to: parked)
            try? fileManager.createSymbolicLink(at: folder, withDestinationURL: elsewhere)
        }

        let result = SpaceRemoval.remove([plan], context: context(), log: noLog, beforeRemoving: swap)

        XCTAssertTrue(fileManager.fileExists(atPath: elsewhere.appendingPathComponent("index-v5/precious.txt").path))
        XCTAssertEqual(result.removed, [])
    }

    func testLinkSwappedInAfterTheGateIsRefusedWhenDeletingForGood() throws {
        let plan = try makeProjectPlan()
        let removal = SpaceRemoval.remove([plan], context: context(), log: noLog)
        let moved = try XCTUnwrap(removal.trashed.first)
        // The Trash itself becomes a link to another folder with a same-named item.
        let elsewhere = home.appendingPathComponent("Elsewhere/trash")
        try makeFile("node_modules/precious.txt", in: elsewhere)
        let parked = home.appendingPathComponent("trash-parked")
        let trash = self.trash!
        let fileManager = self.fileManager
        let swap: (URL) -> Void = { _ in
            try? fileManager.moveItem(at: trash, to: parked)
            try? fileManager.createSymbolicLink(at: trash, withDestinationURL: elsewhere)
        }

        let outcome = SpaceRemoval.deleteForGood(removal.trashed, snapshots: removal.trashedSnapshots, context: context(), log: noLog, beforeRemoving: swap)

        XCTAssertTrue(fileManager.fileExists(atPath: elsewhere.appendingPathComponent("node_modules/precious.txt").path))
        XCTAssertEqual(outcome.left, [moved])
    }


    /// Several rows of one project are checked against one reading of the project, not one each.
    func testProjectIsDatedOncePerRemoval() throws {
        let project = home.appendingPathComponent("Projects/mono")
        try makeFile(".git/HEAD", in: project)
        var plans: [SpaceRemoval.Plan] = []
        for name in ["a", "b", "c"] {
            let package = project.appendingPathComponent("packages/\(name)")
            let marker = try makeFile("package.json", in: package)
            try makeFile("node_modules/lib.js", in: package)
            let folder = package.appendingPathComponent("node_modules")
            let changed = ProjectDependencies.lastChanged(of: project, kinds: kinds)
            let snapshot = try XCTUnwrap(FolderSnapshot.take(of: folder, marker: marker, projectRoot: project, projectChanged: changed))
            plans.append(SpaceRemoval.Plan(url: folder, bytes: FileSizes.folder(folder), snapshot: snapshot, way: .projectFolder(.nodeModules)))
        }
        // The snapshots must all hold the newest date, taken after the last file was written.
        let newest = ProjectDependencies.lastChanged(of: project, kinds: kinds)
        var fresh: [SpaceRemoval.Plan] = []
        for plan in plans {
            var snapshot = plan.snapshot
            snapshot.projectChanged = newest
            fresh.append(SpaceRemoval.Plan(url: plan.url, bytes: plan.bytes, snapshot: snapshot, way: plan.way))
        }
        let ages = ProjectAges()

        let result = SpaceRemoval.remove(fresh, context: context(), log: noLog, ages: ages)

        XCTAssertEqual(result.removed.count, 3)
        XCTAssertEqual(ages.reads, 1)
    }

}
