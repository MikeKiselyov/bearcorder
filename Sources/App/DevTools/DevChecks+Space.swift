// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AVKit
import AppKit
import AppCore
import SwiftUI

@MainActor
extension DevChecks {
    /// Scratch settings domains this run made, to check they are gone at the end.
    static var scratchDomains: [String] = []

    static func preferencesFile(_ domain: String) -> URL {
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences/\(domain).plist")
    }

    /// Empties a scratch settings domain; its file is deleted at the end of the run. Removing the
    /// domain alone leaves an empty .plist in ~/Library/Preferences, one more after every run.
    static func forgetScratchDefaults(_ defaults: UserDefaults, domain: String) {
        defaults.removePersistentDomain(forName: domain)
        if !scratchDomains.contains(domain) {
            scratchDomains.append(domain)
        }
    }

    /// Clean-up settings: defaults, clamping, and project folders that stay inside the home folder.
    static func checkCleanupSettings() {
        let domain = "\(AppInfo.name).selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            check(false, "cleanup settings: scratch defaults")
            return
        }
        defer { forgetScratchDefaults(defaults, domain: domain) }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for name in ["Projects", "Cursor", "Desktop"] {
            try? FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        let roots = AppSettings.defaultProjectRoots(home: home)
        check(roots == ["Projects", "Cursor", "Desktop"], "default project roots are the existing folders", "\(roots)")

        let settings = AppSettings(defaults: defaults, home: home)
        check(settings.projectRoots == ["Projects", "Cursor", "Desktop"], "settings start with the default roots", "\(settings.projectRoots)")
        check(settings.oldProjectDays == 30, "old after 30 days by default", "\(settings.oldProjectDays)")
        check(settings.projectFoldersToTrash, "project folders go to the Trash by default")
        check(settings.dependencyKinds == Set(DependencyKind.allCases), "all dependency kinds by default", "\(settings.dependencyKinds)")
        check(settings.hiddenCacheRows.isEmpty, "no cache row is hidden by default")

        settings.oldProjectDays = 0
        check(settings.oldProjectDays == 1, "days below 1 are clamped to 1", "\(settings.oldProjectDays)")
        settings.oldProjectDays = 1000
        check(settings.oldProjectDays == 365, "days above 365 are clamped to 365", "\(settings.oldProjectDays)")
        check(defaults.integer(forKey: "oldProjectDays") == 365, "the clamped days are saved", "\(defaults.integer(forKey: "oldProjectDays"))")

        settings.projectRoots = ["Work", "/etc", "../outside", home.appendingPathComponent("Code").path, "/"]
        check(settings.projectRoots == ["Work", "Code"], "roots outside home are refused, absolute ones inside home become relative", "\(settings.projectRoots)")

        settings.dependencyKinds = [.nodeModules, .pods]
        settings.hiddenCacheRows = ["uv", "bun"]
        settings.projectFoldersToTrash = false
        let reloaded = AppSettings(defaults: defaults, home: home)
        check(reloaded.projectRoots == ["Work", "Code"], "roots are saved", "\(reloaded.projectRoots)")
        check(reloaded.oldProjectDays == 365, "days are saved", "\(reloaded.oldProjectDays)")
        check(reloaded.dependencyKinds == [.nodeModules, .pods], "kinds are saved", "\(reloaded.dependencyKinds)")
        check(reloaded.hiddenCacheRows == ["uv", "bun"], "hidden cache rows are saved", "\(reloaded.hiddenCacheRows)")
        check(!reloaded.projectFoldersToTrash, "the Trash choice is saved")

        // Add folder… refuses a folder outside home with a note; the next add clears it.
        let editor = ProjectRootsEditor()
        let refused = editor.add(URL(fileURLWithPath: "/private/tmp"), settings: reloaded, home: home)
        check(!refused && editor.refusedNote == "Choose a folder inside your home folder, not in Library" && reloaded.projectRoots == ["Work", "Code"], "adding a folder outside home is refused with a note", "\(editor.refusedNote ?? "no note") \(reloaded.projectRoots)")
        // ~/Library (app data, iCloud Drive, cloud storage) is never searched.
        let libraryRoots = AppSettings.projectRootsInsideHome(["Library", "Library/CloudStorage/x", "Library/Mobile Documents/com~apple~CloudDocs", home.appendingPathComponent("Library/Caches").path, "Projects/Library"], home: home)
        check(libraryRoots == ["Projects/Library"], "roots in ~/Library are dropped", "\(libraryRoots)")
        let lowercaseLibraryRoots = AppSettings.projectRootsInsideHome(["library/CloudStorage/x", "LIBRARY", home.appendingPathComponent("library/Caches").path], home: home)
        check(lowercaseLibraryRoots.isEmpty, "roots in ~/Library are dropped in any case", "\(lowercaseLibraryRoots)")
        let refusedLibrary = editor.add(home.appendingPathComponent("Library/CloudStorage/Drive"), settings: reloaded, home: home)
        check(!refusedLibrary && editor.refusedNote != nil && reloaded.projectRoots == ["Work", "Code"], "adding a folder in ~/Library is refused with a note", "\(reloaded.projectRoots)")
        let addedHome = editor.add(home, settings: reloaded, home: home)
        check(!addedHome && editor.refusedNote != nil, "adding the home folder itself is refused with a note")
        let added = editor.add(home.appendingPathComponent("Developer"), settings: reloaded, home: home)
        check(added && editor.refusedNote == nil && reloaded.projectRoots == ["Work", "Code", "Developer"], "adding a folder inside home adds it and clears the note", "\(reloaded.projectRoots)")
        editor.remove("Work", settings: reloaded)
        check(reloaded.projectRoots == ["Code", "Developer"], "Remove takes only that folder", "\(reloaded.projectRoots)")

        let extraRows: Set<String> = ["uv", "bun", "goModules", "maven", "huggingFace", "preCommit", "editorCaches", "playwright"]
        let categoryIDs = Set(CleanupCategory.all.map { $0.id })
        check(extraRows.isSubset(of: categoryIDs), "every extra cache row is a clean-up category")
    }

    /// Review lists: what is ticked at first, and that removing takes exactly the ticked rows that are
    /// still what the scan saw. Runs on a made-up home with a made-up Trash, never the real ones.
    static func checkSpaceReview() async {
        let files = FileManager.default
        let domain = "\(AppInfo.name).selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            check(false, "space review: scratch defaults")
            return
        }
        defer { forgetScratchDefaults(defaults, domain: domain) }
        let home = files.temporaryDirectory.appendingPathComponent("selftest-review-\(UUID().uuidString)").standardizedFileURL
        defer { try? files.removeItem(at: home) }
        let trash = home.appendingPathComponent(".Trash")
        let space = SpaceModel.shared
        let savedHome = space.homeOverride
        let savedTrash = space.trashOverride
        space.homeOverride = home
        space.trashOverride = trash
        defer {
            space.homeOverride = savedHome
            space.trashOverride = savedTrash
        }

        let projects = home.appendingPathComponent("Projects")
        let elsewhere = home.appendingPathComponent("Elsewhere/precious")
        let caches = home.appendingPathComponent("Library/Caches")
        let sixtyDaysAgo = Date().addingTimeInterval(-60 * 86400)
        do {
            for name in ["old-app", "fresh-app", "touched-app", "locked-app", "linked-app", "tracked-app"] {
                let project = projects.appendingPathComponent(name)
                let package = project.appendingPathComponent("node_modules/pkg")
                try files.createDirectory(at: package, withIntermediateDirectories: true)
                try Data(repeating: 1, count: 20_000).write(to: package.appendingPathComponent("index.js"))
                let manifest = project.appendingPathComponent("package.json")
                try Data("{}".utf8).write(to: manifest)
                if name != "fresh-app" {
                    try files.setAttributes([.modificationDate: sixtyDaysAgo], ofItemAtPath: manifest.path)
                }
            }
            // A project with nothing dated but its .venv: its age is unknown.
            let venv = projects.appendingPathComponent("venv-only/.venv")
            try files.createDirectory(at: venv.appendingPathComponent("lib"), withIntermediateDirectories: true)
            try Data("home = /usr/bin".utf8).write(to: venv.appendingPathComponent("pyvenv.cfg"))
            try Data(repeating: 3, count: 20_000).write(to: venv.appendingPathComponent("lib/module.py"))
            try files.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: elsewhere.appendingPathComponent("file"))
            for name in ["com.example.one", "com.example.two", "com.example.stuck"] {
                let item = caches.appendingPathComponent(name)
                try files.createDirectory(at: item, withIntermediateDirectories: true)
                try Data(repeating: 2, count: 20_000).write(to: item.appendingPathComponent("data"))
            }
            // Already in the Trash before the removal: a file and a folder with the same name as what goes there.
            try files.createDirectory(at: trash.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
            try Data("theirs".utf8).write(to: trash.appendingPathComponent("other.txt"))
        } catch {
            check(false, "space review could not prepare its home", "\(error)")
            return
        }
        // A project whose node_modules is in git is not offered.
        let tracked = projects.appendingPathComponent("tracked-app")
        let gitInit = Process()
        gitInit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitInit.arguments = ["-C", tracked.path, "init", "-q"]
        let gitAdd = Process()
        gitAdd.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitAdd.arguments = ["-C", tracked.path, "add", "node_modules"]
        for process in [gitInit, gitAdd] {
            try? process.run()
            process.waitUntilExit()
        }

        let settings = AppSettings(defaults: defaults, home: home)
        settings.oldProjectDays = 30
        settings.projectFoldersToTrash = true
        let kinds = settings.dependencyKinds
        let scan = await Task.detached(priority: .userInitiated) { () -> ProjectScanResult in
            return ProjectDependencies.scan(roots: [projects], kinds: kinds, maxDepth: 6, isTrackedByGit: SpaceReview.isTrackedByGit, shouldStop: { false })
        }.value
        let review = SpaceReview(projects: scan, settings: settings)

        func modules(_ name: String) -> String {
            return projects.appendingPathComponent(name).appendingPathComponent("node_modules").path
        }
        func row(_ name: String) -> SpaceReview.Row? {
            return review.rows.first(where: { item in item.path == modules(name) })
        }
        check(review.rows.count == 6, "space review lists the six untracked folders", "\(review.rows.map { $0.path })")
        let venvPath = projects.appendingPathComponent("venv-only/.venv").path
        let venvRow = review.rows.first(where: { item in item.path == venvPath })
        check(venvRow != nil && venvRow?.age == nil && venvRow?.isChecked == false, "a project of unknown age is listed unticked with no age", "\(String(describing: venvRow))")
        check(row("tracked-app") == nil, "space review leaves out node_modules that git tracks")
        check(row("old-app")?.isChecked == true, "space review ticks a project unchanged for 60 days")
        check((row("old-app")?.age ?? 0) >= 59, "space review shows the project's age in days", "\(String(describing: row("old-app")?.age))")
        check(row("fresh-app")?.isChecked == false, "space review leaves a fresh project unticked")
        check(review.selectedCount == 4, "space review counts the ticked rows", "\(review.selectedCount)")
        var expectedBytes: Int64 = 0
        for item in review.rows where item.isChecked {
            expectedBytes += item.bytes
        }
        check(review.selectedBytes == expectedBytes && expectedBytes > 0, "space review adds up the ticked sizes", "\(review.selectedBytes)")
        // The footer and the confirmation say the same count and size, in the right words.
        let actionText = SpaceReviewView.actionText(review)
        check(actionText == L("space.review.action.trash", 4, SpaceModel.format(expectedBytes)), "the review footer counts the ticked folders and their size", actionText)
        check(actionText.hasPrefix("Move 4 folders, ") && actionText.hasSuffix(" to the Trash"), "the review footer says the folders go to the Trash", actionText)
        settings.projectFoldersToTrash = false
        let deleting = SpaceReview(projects: scan, settings: settings)
        check(SpaceReviewView.actionText(deleting).hasPrefix("Delete 4 folders, "), "with the Trash off the review footer says Delete", SpaceReviewView.actionText(deleting))
        settings.projectFoldersToTrash = true
        check(L("space.review.action.trash", 1, "6 MB") == "Move 1 folder, 6 MB to the Trash", "one folder is written as one", L("space.review.action.trash", 1, "6 MB"))
        check(L("space.review.action.deleteItems", 5, "2.1 GB") == "Delete 5 items, 2.1 GB", "cache items are counted as items", L("space.review.action.deleteItems", 5, "2.1 GB"))
        check(L("space.review.forGood", 1, "6 MB") == "Delete this folder for good, 6 MB" && L("space.review.forGood", 3, "1.2 GB") == "Delete these 3 folders for good, 1.2 GB", "delete for good counts the trashed folders and their size", L("space.review.forGood", 3, "1.2 GB"))
        check(L("space.review.forGood.confirm", 1, "6 MB") == "Delete this folder, 6 MB for good? This cannot be undone." && L("space.review.forGood.confirm", 2, "1 GB") == "Delete these 2 folders, 1 GB for good? This cannot be undone.", "delete for good asks with the count and size", L("space.review.forGood.confirm", 2, "1 GB"))
        // The automation refuses these buttons without a made-up home: every removing label is known.
        var removalLabels: [String] = [actionText, SpaceReviewView.actionText(deleting), L("space.review.action.deleteItems", 5, "2.1 GB"), L("space.review.forGood", 1, "6 MB"), L("space.review.forGood", 3, "1 GB")]
        var unknownLabels: [String] = []
        for label in removalLabels where !FeatureAutomation.isSpaceRemovalLabel(label) {
            unknownLabels.append(label)
        }
        check(unknownLabels.isEmpty, "the automation knows every Space label that removes", unknownLabels.joined(separator: " | "))
        removalLabels = ["Review App caches", "Find projects", "Cancel", "Select all", "Move test-big.bin to Trash"]
        var wronglyKnown: [String] = []
        for label in removalLabels where FeatureAutomation.isSpaceRemovalLabel(label) {
            wronglyKnown.append(label)
        }
        check(wronglyKnown.isEmpty, "the automation does not refuse other Space buttons", wronglyKnown.joined(separator: " | "))

        // After the scan: a project is edited, one cannot be opened, one is swapped for a link.
        let lockedProject = projects.appendingPathComponent("locked-app")
        do {
            try Data("edit".utf8).write(to: projects.appendingPathComponent("touched-app/index.js"))
            try files.removeItem(atPath: modules("linked-app"))
            try files.createSymbolicLink(atPath: modules("linked-app"), withDestinationPath: elsewhere.path)
            try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedProject.path)
        } catch {
            check(false, "space review could not change the projects after the scan", "\(error)")
            return
        }
        defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedProject.path) }

        let result = await review.remove()
        try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedProject.path)
        check(result.removed == [modules("old-app")], "space review removes only the old project's folder", "\(result.removed)")
        check(!files.fileExists(atPath: modules("old-app")), "space review moves the old node_modules away")
        check(files.fileExists(atPath: modules("fresh-app")), "space review keeps the unticked project")
        var reasons: [String: String] = [:]
        for skipped in result.skipped {
            reasons[skipped.path] = skipped.reason
        }
        check(reasons[modules("touched-app")] == L("space.review.skip.changed"), "space review skips a project changed since the scan", "\(reasons)")
        check(files.fileExists(atPath: modules("touched-app")), "space review keeps the changed project's folder")
        check(reasons[modules("locked-app")] != nil, "space review reports a folder it cannot reach", "\(reasons)")
        check(files.fileExists(atPath: modules("locked-app") + "/pkg/index.js"), "space review leaves the unreachable folder as it is")
        check(reasons[modules("linked-app")] != nil, "space review refuses a folder swapped for a link", "\(reasons)")
        check(files.fileExists(atPath: elsewhere.appendingPathComponent("file").path), "nothing behind the link is removed")
        check(files.fileExists(atPath: modules("linked-app")), "the link itself stays")
        check(result.trashed.count == 1, "space review records what went to the Trash", "\(result.trashed)")
        let trashedPath = result.trashed.first?.path ?? ""
        check(trashedPath.hasPrefix(trash.path + "/") && trashedPath != trash.appendingPathComponent("node_modules").path, "the folder goes to the test Trash under a free name", trashedPath)
        check(files.fileExists(atPath: trashedPath + "/pkg/index.js"), "the trashed folder is whole in the Trash")
        check(review.lastResult?.removed == result.removed, "space review keeps the last result")
        check(row("old-app") == nil && row("fresh-app") != nil, "the removed row leaves the list, the others stay")

        // Put back and something else trashed under the same name: that other item must stay.
        let saved = review.lastResult
        let swapped = home.appendingPathComponent("Elsewhere/put-back")
        do {
            try files.moveItem(atPath: trashedPath, toPath: swapped.path)
            try files.createDirectory(atPath: trashedPath, withIntermediateDirectories: true)
            try Data("new".utf8).write(to: URL(fileURLWithPath: trashedPath).appendingPathComponent("new.txt"))
        } catch {
            check(false, "space review could not swap the trashed folder", "\(error)")
            return
        }
        await review.deleteTrashedForGood()
        check(files.fileExists(atPath: trashedPath + "/new.txt"), "delete for good keeps another item trashed under the same name")
        var reportedReplaced = false
        for skipped in review.lastResult?.skipped ?? [] where skipped.path == URL(fileURLWithPath: trashedPath).standardizedFileURL.path {
            reportedReplaced = skipped.reason == L("space.review.skip.trashReplaced")
        }
        check(reportedReplaced, "an item replaced in the Trash is shown with the skipped rows", "\(String(describing: review.lastResult?.skipped))")
        do {
            try files.removeItem(atPath: trashedPath)
            try files.moveItem(atPath: swapped.path, toPath: trashedPath)
        } catch {
            check(false, "space review could not swap the trashed folder back", "\(error)")
            return
        }
        review.lastResult = saved
        check(SpaceReviewView.forGoodText(saved ?? SpaceReview.RemovalResult()) == L("space.review.forGood", 1, SpaceModel.format(saved?.trashedTotal ?? 0)) && (saved?.trashedTotal ?? 0) > 0, "delete for good says the size of what was trashed", SpaceReviewView.forGoodText(saved ?? SpaceReview.RemovalResult()))
        // The first press only asks; Cancel (the flag back off) keeps it; only the answer deletes.
        review.askDeleteForGood()
        check(review.isConfirmingForGood && files.fileExists(atPath: trashedPath), "the first press of delete for good only asks")
        review.isConfirmingForGood = false
        check(files.fileExists(atPath: trashedPath) && review.lastResult?.trashed.count == 1, "cancelling delete for good keeps the folder in the Trash")
        review.askDeleteForGood()
        await review.deleteTrashedForGood()
        check(!review.isConfirmingForGood, "the question closes after delete for good")
        check(!files.fileExists(atPath: trashedPath), "delete for good removes what this removal trashed")
        check(files.fileExists(atPath: trash.appendingPathComponent("node_modules").path), "delete for good keeps a same-named folder that was in the Trash before")
        check(files.fileExists(atPath: trash.appendingPathComponent("other.txt").path), "delete for good keeps other files in the Trash")
        check(review.lastResult?.trashed.isEmpty == true, "nothing is left to delete for good")
        // Delete for good touches only what is inside the Trash, even when a record says otherwise.
        review.lastResult = SpaceReview.RemovalResult(removed: [], skipped: [], freedBytes: 0, trashed: [elsewhere])
        await review.deleteTrashedForGood()
        check(files.fileExists(atPath: elsewhere.appendingPathComponent("file").path), "delete for good refuses a folder outside the Trash")
        check(review.lastResult?.trashed == [elsewhere], "the refused folder stays on the list", "\(String(describing: review.lastResult?.trashed))")

        // Projects deleted for good when the Trash is off.
        settings.projectFoldersToTrash = false
        let rescan = await Task.detached(priority: .userInitiated) { () -> ProjectScanResult in
            return ProjectDependencies.scan(roots: [projects], kinds: kinds, maxDepth: 6, isTrackedByGit: SpaceReview.isTrackedByGit, shouldStop: { false })
        }.value
        let direct = SpaceReview(projects: rescan, settings: settings)
        for index in direct.rows.indices {
            direct.rows[index].isChecked = direct.rows[index].path == modules("fresh-app")
        }
        let directResult = await direct.remove()
        check(directResult.removed == [modules("fresh-app")] && directResult.trashed.isEmpty, "with the Trash off a project folder is deleted for good", "\(directResult.removed) \(directResult.trashed)")
        check(!files.fileExists(atPath: modules("fresh-app")), "the deleted folder is gone")

        // Cache items: all ticked; one that cannot be removed is reported and the others go.
        guard let appCaches = CleanupCategory.all.first(where: { item in item.id == "appCaches" }) else {
            check(false, "space review: App caches category")
            return
        }
        let items = await Task.detached(priority: .userInitiated) { () -> [CacheItem] in
            return SpaceReview.cacheItems(of: appCaches, home: home)
        }.value
        let cacheReview = SpaceReview(category: appCaches, items: items, settings: settings)
        var allTicked = cacheReview.rows.count == 3
        for item in cacheReview.rows where !item.isChecked {
            allTicked = false
        }
        check(allTicked, "space review ticks every cache item", "\(cacheReview.rows.map { $0.path })")
        let stuck = caches.appendingPathComponent("com.example.stuck")
        try? files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: stuck.path)
        defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stuck.path) }
        let cacheResult = await cacheReview.remove()
        try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stuck.path)
        check(cacheResult.removed.count == 2 && cacheResult.trashed.isEmpty, "cache items are deleted, not trashed", "\(cacheResult.removed)")
        check(!files.fileExists(atPath: caches.appendingPathComponent("com.example.one").path), "a ticked cache item is deleted")
        var stuckReported = false
        for skipped in cacheResult.skipped where skipped.path == stuck.path {
            stuckReported = true
        }
        check(stuckReported, "a cache item that cannot be removed is reported", "\(cacheResult.skipped)")
        check(files.fileExists(atPath: caches.path), "the cache folder itself stays")

        // Our captures are never a review list, even when handed items.
        guard let capturesCategory = CleanupCategory.all.first(where: { item in item.id == "captures" }),
              let capturesFolder = capturesCategory.folders.first else {
            check(false, "space review: Captures category")
            return
        }
        let capture = home.appendingPathComponent(capturesFolder).appendingPathComponent("capture-1")
        try? files.createDirectory(at: capture, withIntermediateDirectories: true)
        try? Data(repeating: 4, count: 20_000).write(to: capture.appendingPathComponent("video.mov"))
        let captureItems = CacheItems.children(of: [capture.deletingLastPathComponent()], keep: [], nameFor: { url in url.lastPathComponent })
        let capturesReview = SpaceReview(category: capturesCategory, items: captureItems, settings: settings)
        check(!captureItems.isEmpty && capturesReview.rows.isEmpty, "a captures review has no rows", "\(captureItems.count) items, \(capturesReview.rows.count) rows")
        check(SpaceReview.cacheItems(of: capturesCategory, home: home).isEmpty, "captures have no review items")
        let capturesResult = await capturesReview.remove()
        check(capturesResult.removed.isEmpty && files.fileExists(atPath: capture.appendingPathComponent("video.mov").path), "a captures review removes nothing")

        // A made-up home without a test Trash: nothing goes to the real Trash.
        space.trashOverride = nil
        settings.projectFoldersToTrash = true
        let noTrashScan = await Task.detached(priority: .userInitiated) { () -> ProjectScanResult in
            return ProjectDependencies.scan(roots: [projects], kinds: kinds, maxDepth: 6, isTrackedByGit: SpaceReview.isTrackedByGit, shouldStop: { false })
        }.value
        let noTrash = SpaceReview(projects: noTrashScan, settings: settings)
        for index in noTrash.rows.indices {
            noTrash.rows[index].isChecked = noTrash.rows[index].path == venvPath
        }
        let noTrashResult = await noTrash.remove()
        space.trashOverride = trash
        check(noTrashResult.removed.isEmpty && noTrashResult.trashed.isEmpty, "a made-up home without a test Trash trashes nothing", "\(noTrashResult.removed)")
        check(noTrashResult.skipped.count == 1 && files.fileExists(atPath: venvPath + "/pyvenv.cfg"), "the folder stays and is reported", "\(noTrashResult.skipped)")
    }

    /// Hugging Face keeps its login token beside the caches: listing and removing (through the
    /// review list, on a made-up home) touch only the caches.
    static func checkHuggingFaceTokensStay() async {
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("hf-home-\(UUID().uuidString)").standardizedFileURL
        defer { try? files.removeItem(at: home) }
        let huggingFace = home.appendingPathComponent(".cache/huggingface")
        let model = huggingFace.appendingPathComponent("hub/models--x")
        do {
            try files.createDirectory(at: model, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 20_000).write(to: model.appendingPathComponent("weights"))
            try Data("secret".utf8).write(to: huggingFace.appendingPathComponent("token"))
            try Data("secret".utf8).write(to: huggingFace.appendingPathComponent("stored_tokens"))
        } catch {
            check(false, "Hugging Face check could not prepare its folder", "\(error)")
            return
        }
        guard let category = CleanupCategory.all.first(where: { item in item.id == "huggingFace" }) else {
            check(false, "Hugging Face category exists")
            return
        }
        var folders: [URL] = []
        for folder in category.folders {
            folders.append(home.appendingPathComponent(folder))
        }
        let items = CacheItems.children(of: folders, keep: [], nameFor: { url in url.lastPathComponent })
        check(items.map { item in item.name } == ["models--x"], "Hugging Face lists only its caches", items.map { item in item.name }.joined(separator: ", "))
        let removed = await removeOnMadeUpHome(category, home: home)
        check(removed.count == 1, "Hugging Face removes its one cached model", "\(removed)")
        check(files.fileExists(atPath: huggingFace.appendingPathComponent("token").path) && files.fileExists(atPath: huggingFace.appendingPathComponent("stored_tokens").path), "cleaning Hugging Face keeps the login tokens")
        check(!files.fileExists(atPath: model.path), "cleaning Hugging Face removes the cached model")
    }

    /// Lists a category's items in a made-up home and removes every ticked one through its review
    /// list, as the window does; the Trash is a folder in that home. Returns the removed paths.
    static func removeOnMadeUpHome(_ category: CleanupCategory, home: URL) async -> [String] {
        let space = SpaceModel.shared
        let savedHome = space.homeOverride
        let savedTrash = space.trashOverride
        space.homeOverride = home
        space.trashOverride = home.appendingPathComponent(".Trash")
        defer {
            space.homeOverride = savedHome
            space.trashOverride = savedTrash
        }
        let items = SpaceReview.cacheItems(of: category, home: home)
        let review = SpaceReview(category: category, items: items, settings: AppSettings.shared)
        let result = await review.remove()
        return result.removed
    }

    /// Whole-folder caches (npm's _cacache): only the contents of the category's own folder go.
    /// A row whose folder is not exactly a declared one (~/.npm) is refused, a link inside is not
    /// followed. Maven rows start unticked, the others ticked.
    static func checkWholeFolderCaches() async {
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent("npm-home-\(UUID().uuidString)").standardizedFileURL
        defer { try? files.removeItem(at: home) }
        let npm = home.appendingPathComponent(".npm")
        let cacache = npm.appendingPathComponent("_cacache")
        let other = npm.appendingPathComponent("other/keep.json")
        let target = home.appendingPathComponent("Documents/precious.txt")
        let maven = home.appendingPathComponent(".m2/repository/com/example")
        do {
            try files.createDirectory(at: cacache.appendingPathComponent("content-v2"), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 20_000).write(to: cacache.appendingPathComponent("content-v2/blob"))
            try Data(repeating: 1, count: 20_000).write(to: cacache.appendingPathComponent("index"))
            try files.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: other)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("mine".utf8).write(to: target)
            try files.createSymbolicLink(at: cacache.appendingPathComponent("link-out"), withDestinationURL: target.deletingLastPathComponent())
            try files.createDirectory(at: maven, withIntermediateDirectories: true)
            try Data(repeating: 2, count: 20_000).write(to: maven.appendingPathComponent("lib.jar"))
            try files.createDirectory(at: home.appendingPathComponent("Library/Caches/com.example.app"), withIntermediateDirectories: true)
            try Data(repeating: 3, count: 20_000).write(to: home.appendingPathComponent("Library/Caches/com.example.app/data"))
            // JetBrains keeps IDE indexes and local history here: never listed. Poetry keeps its
            // virtual environments here: listed, but never ticked on its own.
            try files.createDirectory(at: home.appendingPathComponent("Library/Caches/JetBrains/IntelliJIdea2025.2"), withIntermediateDirectories: true)
            try Data(repeating: 4, count: 20_000).write(to: home.appendingPathComponent("Library/Caches/JetBrains/IntelliJIdea2025.2/index"))
            try files.createDirectory(at: home.appendingPathComponent("Library/Caches/pypoetry/virtualenvs"), withIntermediateDirectories: true)
            try Data(repeating: 5, count: 20_000).write(to: home.appendingPathComponent("Library/Caches/pypoetry/virtualenvs/env"))
            // Android Studio (built on JetBrains) keeps its caches in Google/AndroidStudio<version>.
            try files.createDirectory(at: home.appendingPathComponent("Library/Caches/Google/AndroidStudio2025.2"), withIntermediateDirectories: true)
            try Data(repeating: 6, count: 20_000).write(to: home.appendingPathComponent("Library/Caches/Google/AndroidStudio2025.2/index"))
        } catch {
            check(false, "whole-folder cache check could not prepare its home", "\(error)")
            return
        }
        guard let javascript = CleanupCategory.all.first(where: { item in item.id == "javascript" }),
              let mavenCategory = CleanupCategory.all.first(where: { item in item.id == "maven" }),
              let appCaches = CleanupCategory.all.first(where: { item in item.id == "appCaches" }) else {
            check(false, "whole-folder cache check: categories exist")
            return
        }
        let space = SpaceModel.shared
        let savedHome = space.homeOverride
        let savedTrash = space.trashOverride
        space.homeOverride = home
        space.trashOverride = home.appendingPathComponent(".Trash")

        // A made-up row for ~/.npm itself: not a folder of the category, so nothing in it goes.
        if let snapshot = FolderSnapshot.take(of: npm, marker: nil, projectRoot: nil, projectChanged: nil) {
            let wrong = SpaceReview(category: javascript, items: [CacheItem(url: npm, name: "~/.npm", bytes: 40_000, snapshot: snapshot)], settings: AppSettings.shared)
            let refused = await wrong.remove()
            check(refused.removed.isEmpty && refused.skipped.count == 1, "a whole-folder row that is not a declared folder is refused", "\(refused.removed) \(refused.skipped)")
            check(files.fileExists(atPath: other.path) && files.fileExists(atPath: cacache.appendingPathComponent("index").path), "nothing in ~/.npm goes for a refused row")
        } else {
            check(false, "whole-folder cache check: snapshot of ~/.npm")
        }
        // The same for ~/Library/Caches, the folder above Yarn's declared one: another app's cache stays.
        let caches = home.appendingPathComponent("Library/Caches")
        if let snapshot = FolderSnapshot.take(of: caches, marker: nil, projectRoot: nil, projectChanged: nil) {
            let wrong = SpaceReview(category: javascript, items: [CacheItem(url: caches, name: "~/Library/Caches", bytes: 20_000, snapshot: snapshot)], settings: AppSettings.shared)
            let refused = await wrong.remove()
            check(refused.removed.isEmpty && files.fileExists(atPath: caches.appendingPathComponent("com.example.app/data").path), "a row for the folder above a declared one removes nothing", "\(refused.removed) \(refused.skipped)")
        } else {
            check(false, "whole-folder cache check: snapshot of ~/Library/Caches")
        }

        let items = SpaceReview.cacheItems(of: javascript, home: home)
        let review = SpaceReview(category: javascript, items: items, settings: AppSettings.shared)
        check(review.rows.count == 1 && review.rows.first?.path == cacache.path && review.rows.first?.isChecked == true, "npm's cache is one ticked row for ~/.npm/_cacache", "\(review.rows.map { row in row.path })")
        _ = await review.remove()
        check(!files.fileExists(atPath: cacache.appendingPathComponent("content-v2").path) && !files.fileExists(atPath: cacache.appendingPathComponent("index").path), "the contents of ~/.npm/_cacache go")
        check(files.fileExists(atPath: cacache.path), "~/.npm/_cacache itself stays")
        check(files.fileExists(atPath: other.path), "~/.npm/other stays")
        check(files.fileExists(atPath: target.path), "a link inside the cache is not followed: its target stays")

        let mavenItems = SpaceReview.cacheItems(of: mavenCategory, home: home)
        let mavenReview = SpaceReview(category: mavenCategory, items: mavenItems, settings: AppSettings.shared)
        var mavenTicked = 0
        for row in mavenReview.rows where row.isChecked {
            mavenTicked += 1
        }
        check(!mavenReview.rows.isEmpty && mavenTicked == 0, "Maven rows start unticked", "\(mavenReview.rows.count) rows, \(mavenTicked) ticked")
        let cacheItems = SpaceReview.cacheItems(of: appCaches, home: home)
        let cacheReview = SpaceReview(category: appCaches, items: cacheItems, settings: AppSettings.shared)
        let jetBrainsPath = home.appendingPathComponent("Library/Caches/JetBrains").path
        let poetryPath = home.appendingPathComponent("Library/Caches/pypoetry").path
        let exampleAppPath = home.appendingPathComponent("Library/Caches/com.example.app").path
        let jetBrainsRow = cacheReview.rows.first(where: { row in row.path == jetBrainsPath })
        let poetryRow = cacheReview.rows.first(where: { row in row.path == poetryPath })
        let exampleAppRow = cacheReview.rows.first(where: { row in row.path == exampleAppPath })
        check(jetBrainsRow == nil, "App caches never list JetBrains", "\(cacheReview.rows.map { row in row.path })")
        let googlePath = home.appendingPathComponent("Library/Caches/Google").path
        let googleRow = cacheReview.rows.first(where: { row in row.path == googlePath })
        check(googleRow == nil, "App caches do not list Google while it holds Android Studio's caches", "\(cacheReview.rows.map { row in row.path })")
        check(poetryRow != nil && poetryRow?.isChecked == false, "App caches list pypoetry unticked", "\(String(describing: poetryRow))")
        check(exampleAppRow?.isChecked == true && cacheReview.selectedCount == cacheReview.rows.count - 1, "other cache rows start ticked", "\(cacheReview.selectedCount) of \(cacheReview.rows.count)")
        let unticked = await mavenReview.remove()
        check(unticked.removed.isEmpty && files.fileExists(atPath: maven.appendingPathComponent("lib.jar").path), "unticked Maven rows are not removed")
        space.homeOverride = savedHome
        space.trashOverride = savedTrash
    }

    /// Each reason AppCore gives for a skipped row reads as the text Space has always shown.
    static func checkSpaceSkipTexts() {
        var expected: [(reason: SpaceRemoval.SkipReason, text: String)] = []
        expected.append((reason: .refused(.missing), text: L("space.review.skip.gone")))
        expected.append((reason: .refused(.throughLink), text: L("space.review.skip.link")))
        expected.append((reason: .refused(.outsideHome), text: L("space.review.skip.notAllowed")))
        expected.append((reason: .refused(.homeOrTopFolder), text: L("space.review.skip.notAllowed")))
        expected.append((reason: .refused(.notAllowedName), text: L("space.review.skip.notAllowed")))
        expected.append((reason: .refused(.notInDeclaredCache), text: L("space.review.skip.notAllowed")))
        expected.append((reason: .refused(.notTrashedByApp), text: L("space.review.skip.notAllowed")))
        expected.append((reason: .changed(.gone), text: L("space.review.skip.gone")))
        expected.append((reason: .changed(.replaced), text: L("space.review.skip.changed")))
        expected.append((reason: .changed(.modified), text: L("space.review.skip.changed")))
        expected.append((reason: .changed(.markerGone), text: L("space.review.skip.changed")))
        expected.append((reason: .changed(.projectChanged), text: L("space.review.skip.changed")))
        expected.append((reason: .notAllowed, text: L("space.review.skip.notAllowed")))
        expected.append((reason: .gone, text: L("space.review.skip.gone")))
        expected.append((reason: .failed("disk full"), text: L("space.review.skip.failed", "disk full")))
        expected.append((reason: .commandFailed("go clean -modcache"), text: L("space.review.skip.failed", "go clean -modcache")))
        expected.append((reason: .trashReplaced, text: L("space.review.skip.trashReplaced")))
        expected.append((reason: .changedInTrash, text: L("space.review.skip.changedInTrash")))
        expected.append((reason: .refused(.ownRepository), text: L("space.review.skip.notAllowed")))
        expected.append((reason: .refused(.inLibrary), text: L("space.review.skip.notAllowed")))
        var wrong: [String] = []
        for item in expected {
            let text = SpaceReview.reasonText(for: item.reason)
            if text != item.text {
                wrong.append("\(item.reason) -> \(text)")
            }
        }
        check(wrong.isEmpty, "every skip reason from AppCore has its usual text", wrong.joined(separator: "; "))
    }

    /// Every clean-up category has its texts, none points into Cursor's or VS Code's `User` folder
    /// (settings and workspaces), and Playwright's browsers are not counted twice.
    static func checkCleanupCategories() {
        // Rows hidden in the settings leave the window and the menu; our captures always show.
        var sizes: [String: Int64] = [:]
        for category in CleanupCategory.all {
            sizes[category.id] = 1000
        }
        let shown = SpaceModel.visible(CleanupCategory.all, sizes: sizes, hidden: ["uv", "bun"])
        var shownIDs: [String] = []
        for category in shown {
            shownIDs.append(category.id)
        }
        check(!shownIDs.contains("uv") && !shownIDs.contains("bun"), "hidden cache rows are not shown", shownIDs.joined(separator: ","))
        check(shownIDs.contains("goModules") && shownIDs.contains("captures"), "the other rows still show", shownIDs.joined(separator: ","))
        check(shownIDs.count == CleanupCategory.all.count - 2, "only the hidden rows go", "\(shownIDs.count)")
        var missingText: [String] = []
        var userFolders: [String] = []
        for category in CleanupCategory.all {
            for key in ["title", "detail"] {
                let full = "space.category.\(category.id).\(key)"
                if L(full) == full || L(full).isEmpty {
                    missingText.append(full)
                }
            }
            for folder in category.folders {
                if folder.contains("/User") {
                    userFolders.append(folder)
                }
            }
        }
        check(missingText.isEmpty, "every clean-up category has a title and a detail", missingText.joined(separator: ", "))
        check(userFolders.isEmpty, "no clean-up category touches a User folder", userFolders.joined(separator: ", "))
        var credentialFolders: [String] = []
        for category in CleanupCategory.all {
            for folder in category.folders {
                if folder == ".cache/huggingface" || folder.lowercased().contains("token") {
                    credentialFolders.append(folder)
                }
            }
        }
        check(credentialFolders.isEmpty, "no clean-up category covers credentials", credentialFolders.joined(separator: ", "))
        let playwright = CleanupCategory.all.first(where: { category in category.id == "playwright" })
        let appCaches = CleanupCategory.all.first(where: { category in category.id == "appCaches" })
        let playwrightFolder = playwright?.folders.first ?? "missing"
        check(appCaches?.keep.contains(playwrightFolder) == true, "App caches skips Playwright's folder", playwrightFolder)
        let goModules = CleanupCategory.all.first(where: { category in category.id == "goModules" })
        check(goModules?.cleanCommand == ["go", "clean", "-modcache"], "Go modules are cleaned with go clean")
    }

    /// Runs `body` while Space shows a made-up home: a few caches and one old project with sizes
    /// measured from their files, a made-up disk, and a project search that just finished. The
    /// pictures of the menu's Space tab never show this Mac's disk, caches or projects.
    /// A made-up file: `bytes` of filler or `text`, optionally dated `daysOld` days ago.
    struct MadeUpFile {
        var path: String
        var bytes = 0
        var text: String?
        var daysOld: Int?
    }

    /// `extraFiles` adds made-up files under the home, for a picture that needs a longer list.
    static func withMadeUpSpaceHome(extraFiles: [MadeUpFile] = [], _ body: () async -> Void) async {
        let files = FileManager.default
        let domain = "\(AppInfo.name).snapshot.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            print("made-up Space home: no scratch defaults")
            await body()
            return
        }
        defer { forgetScratchDefaults(defaults, domain: domain) }
        let home = files.temporaryDirectory.appendingPathComponent("selftest-menu-home-\(UUID().uuidString)").standardizedFileURL
        defer { try? files.removeItem(at: home) }
        let samples: [(path: String, bytes: Int)] = [
            (path: ".cache/uv/wheels/numpy.whl", bytes: 24_000_000),
            (path: "Library/Caches/com.example.browser/data", bytes: 9_000_000),
            (path: "Library/Caches/com.example.music/data", bytes: 5_000_000),
            (path: "Library/Application Support/Cursor/CachedData/1.0/code.bin", bytes: 11_000_000),
            (path: ".bun/install/cache/react.tgz", bytes: 6_000_000),
            (path: "Projects/checkout-web/node_modules/lib/blob", bytes: 8_000_000),
        ]
        do {
            var madeUp: [MadeUpFile] = []
            for sample in samples {
                madeUp.append(MadeUpFile(path: sample.path, bytes: sample.bytes))
            }
            madeUp.append(contentsOf: extraFiles)
            for file in madeUp {
                let url = home.appendingPathComponent(file.path)
                try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let text = file.text {
                    try Data(text.utf8).write(to: url)
                } else {
                    try Data(repeating: 1, count: file.bytes).write(to: url)
                }
                if let days = file.daysOld {
                    try files.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(days) * 86400)], ofItemAtPath: url.path)
                }
            }
            let manifest = home.appendingPathComponent("Projects/checkout-web/package.json")
            try Data("{}".utf8).write(to: manifest)
            try files.setAttributes([.modificationDate: Date().addingTimeInterval(-90 * 86400)], ofItemAtPath: manifest.path)
        } catch {
            print("made-up Space home: could not prepare it: \(error)")
        }
        let space = SpaceModel.shared
        let savedHome = space.homeOverride
        let savedTrash = space.trashOverride
        let savedVolume = space.volumeOverride
        let savedMessage = space.message
        space.forgetReviewsForTests()
        space.homeOverride = home
        space.trashOverride = home.appendingPathComponent(".Trash")
        space.volumeOverride = (total: 494_380_000_000, free: 121_400_000_000)
        space.message = nil
        await waitForMeasure(space)
        await space.measure(force: true)
        await waitForMeasure(space)
        let settings = AppSettings(defaults: defaults, home: home)
        settings.projectRoots = ["Projects"]
        settings.oldProjectDays = 30
        settings.projectFoldersToTrash = true
        await space.scanProjects(settings: settings)
        await body()
        await waitForMeasure(space)
        space.forgetReviewsForTests()
        space.homeOverride = savedHome
        space.trashOverride = savedTrash
        space.volumeOverride = savedVolume
        space.message = savedMessage
        await space.measure(force: true)
        await waitForMeasure(space)
    }

    /// Waits for a measure in progress (possibly of another home) to end.
    private static func waitForMeasure(_ space: SpaceModel) async {
        var waited = 0
        while space.isMeasuring && waited < 300 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            waited += 1
        }
    }

    /// The review list of projects found in a made-up home (one old and ticked, one fresh, one of
    /// unknown age), its confirmation, and the Disk Space window on that list and on the categories.
    /// Nothing is removed; the real home is never looked at for these.
    static func renderSpaceReview(folder: URL, app: AppState) async {
        let files = FileManager.default
        let domain = "\(AppInfo.name).snapshot.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            print("space review snapshot: no scratch defaults")
            return
        }
        defer { forgetScratchDefaults(defaults, domain: domain) }
        let home = files.temporaryDirectory.appendingPathComponent("selftest-snapshot-\(UUID().uuidString)").standardizedFileURL
        defer { try? files.removeItem(at: home) }
        let space = SpaceModel.shared
        let savedHome = space.homeOverride
        let savedTrash = space.trashOverride
        space.homeOverride = home
        space.trashOverride = home.appendingPathComponent(".Trash")
        defer {
            space.homeOverride = savedHome
            space.trashOverride = savedTrash
        }
        let projects = home.appendingPathComponent("Projects")
        let ninetyDaysAgo = Date().addingTimeInterval(-90 * 86400)
        do {
            let samples: [(project: String, folder: String, marker: String, bytes: Int, old: Bool)] = [
                (project: "checkout-web", folder: "node_modules", marker: "package.json", bytes: 6_000_000, old: true),
                (project: "my-site", folder: "node_modules", marker: "package.json", bytes: 3_000_000, old: false),
                (project: "ml-notebooks", folder: ".venv", marker: "", bytes: 2_000_000, old: false),
            ]
            for sample in samples {
                let project = projects.appendingPathComponent(sample.project)
                let inside = project.appendingPathComponent(sample.folder).appendingPathComponent("lib")
                try files.createDirectory(at: inside, withIntermediateDirectories: true)
                try Data(repeating: 1, count: sample.bytes).write(to: inside.appendingPathComponent("blob"))
                if sample.folder == ".venv" {
                    // Nothing dated but the .venv: the project's age is unknown.
                    try Data("home = /usr/bin".utf8).write(to: project.appendingPathComponent(".venv/pyvenv.cfg"))
                    continue
                }
                let marker = project.appendingPathComponent(sample.marker)
                try Data("{}".utf8).write(to: marker)
                if sample.old {
                    try files.setAttributes([.modificationDate: ninetyDaysAgo], ofItemAtPath: marker.path)
                }
            }
        } catch {
            print("space review snapshot: could not prepare its home: \(error)")
            return
        }
        let settings = AppSettings(defaults: defaults, home: home)
        settings.projectRoots = ["Projects"]
        settings.oldProjectDays = 30
        settings.projectFoldersToTrash = true
        await space.scanProjects(settings: settings)
        guard let review = space.projectReview else {
            print("space review snapshot: no project review")
            return
        }
        let list = SpaceReviewView(review: review, model: space).padding(16).environment(app).preferredColorScheme(.dark)
        render(list, size: CGSize(width: 640, height: 360), to: folder.appendingPathComponent("space-review.png"))
        review.isConfirming = true
        render(list, size: CGSize(width: 640, height: 360), to: folder.appendingPathComponent("space-review-confirm.png"))
        review.isConfirming = false

        // The window on the projects list at its usual and its smallest size, and the categories.
        space.section = .cleanUp
        space.openReviewID = SpaceModel.projectsID
        render(SpaceView().environment(app).preferredColorScheme(.dark), size: CGSize(width: 1000, height: 700), to: folder.appendingPathComponent("space-window-projects.png"))
        render(SpaceView().environment(app).preferredColorScheme(.dark), size: CGSize(width: 760, height: 520), to: folder.appendingPathComponent("space-window-projects-min.png"))
        space.openReviewID = nil
        render(SpaceView().environment(app).preferredColorScheme(.dark), size: CGSize(width: 760, height: 520), to: folder.appendingPathComponent("space-window-min.png"))

        // After a removal into the made-up home's Trash: one folder moved, one gone before the
        // removal and reported, and the button to delete the moved one for good.
        for index in review.rows.indices {
            review.rows[index].isChecked = review.rows[index].title != "ml-notebooks/.venv"
        }
        try? files.removeItem(at: projects.appendingPathComponent("my-site/node_modules"))
        await review.remove()
        render(list, size: CGSize(width: 640, height: 360), to: folder.appendingPathComponent("space-review-result.png"))
        // "Delete … for good" asks first, with the same count and size.
        review.askDeleteForGood()
        render(list, size: CGSize(width: 640, height: 400), to: folder.appendingPathComponent("space-review-forgood-confirm.png"))
        review.isConfirmingForGood = false
        // The window measured the made-up home; the menu pictures measure the real one again.
        space.homeOverride = savedHome
        space.trashOverride = savedTrash
        // A measure the window started may still run on the made-up home: wait for it first.
        var waited = 0
        while space.isMeasuring && waited < 300 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            waited += 1
        }
        await space.measure(force: true)
    }
}
#endif
