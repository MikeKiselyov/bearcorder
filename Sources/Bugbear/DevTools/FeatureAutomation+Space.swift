// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI
import BugbearCore

@MainActor
extension FeatureAutomation {
    static func runSpace(_ name: String, _ argument: String, _ parts: [String], _ app: AppState) async -> String? {
        switch name {
        case "space-measure":
            // Sizes of the clean-up categories in the real home folder (nothing is deleted).
            let space = SpaceModel.shared
            await space.measure(force: true)
            var parts: [String] = ["free=\(SpaceModel.format(space.volumeFree))", "cleanable=\(SpaceModel.format(space.cleanableBytes))"]
            for category in CleanupCategory.all {
                parts.append("\(category.id)=\(SpaceModel.format(space.sizes[category.id] ?? 0))")
            }
            return parts.joined(separator: " ")

        case "space-scan":
            // space-scan (home + Applications), space-scan:appdata (also other apps' data),
            // or space-scan:<subfolder of home>.
            let space = SpaceModel.shared
            if argument == "appdata" {
                space.includeAppData = true
                space.startScan()
            } else if argument.isEmpty {
                space.startScan()
            } else {
                space.startScan(subfolder: argument)
            }
            while space.isScanning {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard let tree = space.tree, case .done(let seconds) = space.scanState else { return "no result" }
            var lines: [String] = [String(format: "files=%d scanned=%@ notCounted=%@ seconds=%.1f", tree.root.fileCount, SpaceModel.format(tree.root.bytes), SpaceModel.format(space.notCounted), seconds)]
            for root in tree.root.children {
                var inner: [String] = []
                for child in root.children.prefix(10) {
                    inner.append("\(child.name)=\(SpaceModel.format(child.bytes))")
                }
                lines.append("\(root.name)=\(SpaceModel.format(root.bytes)): " + inner.joined(separator: ", "))
            }
            return lines.joined(separator: " || ")

        case "space-stop-test":
            // space-stop-test:<first subfolder of home>:<second>: start a scan of the first, stop it while
            // it is still on its way, scan the second right away: the result is the second's, and the
            // stopped scan, waking up later, must not overwrite it. The first scan waits 2 s before
            // walking, so it is surely stopped in the middle, whatever the size of the folder.
            let space = SpaceModel.shared
            let second = parts.count > 2 ? parts[2] : argument
            space.scanStartDelay = 2
            space.startScan(subfolder: argument)
            try? await Task.sleep(nanoseconds: 500_000_000)
            space.cancelScan()
            let stoppedState = "\(space.scanState)"
            space.scanStartDelay = 0
            space.startScan(subfolder: second)
            while space.isScanning {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            // The stopped scan wakes up meanwhile: give it time to overwrite things, if it still could.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let tree = space.tree else { return "no result" }
            return "afterStop=\(stoppedState) final=\(space.scanState) files=\(tree.root.fileCount)"

        case "space-folder":
            // space-folder:Home > Library > Application Support: the biggest folders inside it.
            // " > " separates names, because a scanned subfolder root keeps its slashes.
            guard let node = SpaceModel.shared.tree?.node(at: argument.components(separatedBy: " > ")) else { return "not found" }
            var parts: [String] = []
            for child in node.children.prefix(12) {
                parts.append("\(child.name)=\(SpaceModel.format(child.bytes))")
            }
            return "\(argument)=\(SpaceModel.format(node.bytes)): " + parts.joined(separator: ", ")

        case "cleanup-pause":
            // cleanup-pause:on|off: the timed storage clean-up waits while tests change its limits.
            app.scheduledCleanUpPaused = argument == "on"
            return "paused=\(app.scheduledCleanUpPaused)"

        case "space-top":
            // Full paths of the biggest files from the last scan.
            var lines: [String] = []
            for file in SpaceModel.shared.topFiles.prefix(Int(argument) ?? 5) {
                lines.append("\(SpaceModel.format(file.bytes)) \(file.path)")
            }
            return lines.joined(separator: " | ")

        case "open-space":
            // open-space:<Clean up|Folders|Largest files>[:<review list: projects or a category id>]
            let section = SpaceView.Section(rawValue: argument) ?? .cleanUp
            var category: String?
            if parts.count > 2 {
                category = parts[2]
            }
            WindowManager.shared.close(id: "space")
            WindowManager.shared.openSpace(section: section, category: category)
            return "opened \(section.rawValue)"

        case "space-fake-home":
            // space-fake-home:on|off: the Disk Space window measures, scans and cleans a made-up
            // home folder with caches, a log, a big download and projects, so its buttons can be
            // pressed. Removed project folders go to <home>/.TestTrash, never the real Trash, and
            // the project settings are set for the test; off puts them back as they were.
            let space = SpaceModel.shared
            let files = FileManager.default
            if let fakeHome = space.homeOverride {
                try? files.removeItem(at: fakeHome)
            }
            space.homeOverride = nil
            space.applicationsOverride = nil
            space.trashOverride = nil
            space.scanStartDelay = 0
            space.forgetReviewsForTests()
            space.confirmingFile = nil
            space.message = nil
            if argument != "on" {
                restoreProjectSettings()
                await measureFully(space)
                return "off"
            }
            let fakeHome = AppPaths.temporary.appendingPathComponent("space-buttons-\(UUID().uuidString)", isDirectory: true)
            let samples = ["Library/Caches/com.example.app/blob.bin": 3_000_000, "Library/Caches/com.example.second/data.bin": 1_000_000, "Library/Logs/Example/run.log": 1_000_000, "Downloads/bugbear-test-big.bin": 60_000_000, "Applications/Example.app/Contents/Info.plist": 1_000]
            for (sample, bytes) in samples {
                let url = fakeHome.appendingPathComponent(sample)
                try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data(count: bytes).write(to: url)
            }
            makeFakeProjects(in: fakeHome.appendingPathComponent("Projects"), home: fakeHome)
            space.homeOverride = fakeHome
            space.applicationsOverride = fakeHome.appendingPathComponent("Applications")
            space.trashOverride = fakeHome.appendingPathComponent(".TestTrash")
            saveProjectSettings()
            let settings = AppSettings.shared
            settings.projectRoots = ["Projects"]
            settings.oldProjectDays = 30
            settings.projectFoldersToTrash = true
            settings.dependencyKinds = Set(DependencyKind.allCases)
            settings.hiddenCacheRows = []
            // A tiny home scans in no time; this leaves "Stop" something to stop.
            space.scanStartDelay = 2
            await measureFully(space)
            return fakeHome.path

        case "space-scan-delay":
            // space-scan-delay:<seconds>: the wait before a scan starts (space-fake-home:on sets 2 s so
            // "Stop" has something to stop); 0 once the test needs no running search to stop.
            guard SpaceModel.shared.homeOverride != nil else { return "refused: no made-up home" }
            SpaceModel.shared.scanStartDelay = Double(argument) ?? 0
            return "delay=\(SpaceModel.shared.scanStartDelay)"

        case "space-review-state":
            // space-review-state:<projects|category id>: the review list of the made-up home.
            // rows, ticked rows and their bytes, what is in the test Trash, and whether old-app's
            // node_modules is still there. Refuses without a made-up home.
            let space = SpaceModel.shared
            guard let fakeHome = space.homeOverride else { return "refused: no made-up home" }
            let files = FileManager.default
            var review: SpaceReview?
            if argument == SpaceModel.projectsID {
                review = space.projectReview
            } else {
                review = space.cacheReviews[argument]
            }
            let trashFolder = fakeHome.appendingPathComponent(".TestTrash")
            var trashed: [String] = []
            for name in (try? files.contentsOfDirectory(atPath: trashFolder.path)) ?? [] {
                trashed.append(name)
            }
            trashed.sort()
            let projects = fakeHome.appendingPathComponent("Projects")
            let oldExists = files.fileExists(atPath: projects.appendingPathComponent("old-app/node_modules").path)
            let freshExists = files.fileExists(atPath: projects.appendingPathComponent("fresh-app/node_modules").path)
            var parts: [String] = []
            parts.append("rows=\(review?.rows.count ?? 0)")
            parts.append("checked=\(review?.selectedCount ?? 0)")
            parts.append("selected=\(review?.selectedBytes ?? 0)")
            parts.append("trash=\(trashed.joined(separator: ","))")
            parts.append("exists=\(oldExists)")
            parts.append("fresh=\(freshExists)")
            parts.append("list=\(review != nil)")
            parts.append("scanning=\(space.isScanningProjects)")
            parts.append("confirming=\(review?.isConfirming ?? false)")
            parts.append("removing=\(review?.isRemoving ?? false)")
            parts.append("forGood=\(review?.lastResult?.trashed.count ?? 0)")
            parts.append("askingForGood=\(review?.isConfirmingForGood ?? false)")
            return parts.joined(separator: " ")

        case "space-add-root":
            // space-add-root:<absolute path>: what "Add folder…" in Settings → Storage does with the
            // folder picked in its panel (the panel itself cannot be driven). Only with a made-up home.
            guard SpaceModel.shared.homeOverride != nil else { return "refused: no made-up home" }
            let path = parts.count > 1 ? parts[1...].joined(separator: ":") : ""
            let added = ProjectRootsEditor.shared.add(URL(fileURLWithPath: path), settings: AppSettings.shared)
            let roots = AppSettings.shared.projectRoots.joined(separator: ",")
            return "added=\(added) roots=\(roots) note=\(ProjectRootsEditor.shared.refusedNote ?? "")"

        case "space-state":
            // What the Disk Space window's buttons changed.
            let space = SpaceModel.shared
            var scan = "idle"
            switch space.scanState {
            case .idle:
                scan = "idle"
            case .preparing, .running:
                scan = "running"
            case .done:
                scan = "done"
            }
            let caches = SpaceModel.format(space.sizes["appCaches"] ?? 0)
            return "scan=\(scan) appData=\(space.includeAppData) appCaches=\(caches) files=\(space.topFiles.count) folder=\(space.folderPath.joined(separator: " > "))"

        case "space-clean-test":
            // Removes "App caches" and "Logs" in a made-up home folder through their review lists
            // (the one way Space removes anything): caches go, kept folders stay.
            let space = SpaceModel.shared
            let fakeHome = AppPaths.temporary.appendingPathComponent("space-home-\(UUID().uuidString)", isDirectory: true)
            let files = FileManager.default
            let samples = ["Library/Caches/com.example.app/blob.bin", "Library/Caches/Homebrew/tool.tar.gz", "Library/Logs/Example/run.log", "Library/Logs/Bugbear/bugbear.log", "Library/Logs/DiagnosticReports/Example-2026.ips"]
            for sample in samples {
                let url = fakeHome.appendingPathComponent(sample)
                try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data(count: 2_000_000).write(to: url)
            }
            space.homeOverride = fakeHome
            await space.measure(force: true)
            let beforeCaches = space.sizes["appCaches"] ?? 0
            let beforeHomebrew = space.sizes["homebrew"] ?? 0
            for category in CleanupCategory.all where category.id == "appCaches" || category.id == "logs" {
                _ = await DevChecks.removeOnMadeUpHome(category, home: fakeHome)
            }
            let cacheGone = !files.fileExists(atPath: fakeHome.appendingPathComponent(samples[0]).path)
            let homebrewKept = files.fileExists(atPath: fakeHome.appendingPathComponent(samples[1]).path)
            let otherLogGone = !files.fileExists(atPath: fakeHome.appendingPathComponent(samples[2]).path)
            let ownLogKept = files.fileExists(atPath: fakeHome.appendingPathComponent(samples[3]).path)
            let folderKept = files.fileExists(atPath: fakeHome.appendingPathComponent("Library/Caches").path)
            let crashReportKept = files.fileExists(atPath: fakeHome.appendingPathComponent(samples[4]).path)
            let result = "before appCaches=\(SpaceModel.format(beforeCaches)) homebrew=\(SpaceModel.format(beforeHomebrew)) cacheGone=\(cacheGone) homebrewKept=\(homebrewKept) otherLogGone=\(otherLogGone) ownLogKept=\(ownLogKept) cachesFolderKept=\(folderKept) crashReportsKept=\(crashReportKept)"
            space.message = nil
            space.homeOverride = nil
            try? files.removeItem(at: fakeHome)
            await space.measure(force: true)
            return result

        case "cleanup-dryrun":
            // cleanup-dryrun:<days>:<GB>: what the limits would delete, without deleting.
            let days = Int(argument) ?? 0
            let gigabytes = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
            let sizes = await app.store.measureSizes()
            var items: [StoragePolicy.Item] = []
            var total: Int64 = 0
            for capture in app.store.captures {
                let bytes = sizes[capture.id] ?? 0
                total += bytes
                items.append(StoragePolicy.Item(id: capture.id, createdAt: capture.createdAt, bytes: bytes))
            }
            let doomed = StoragePolicy.itemsToDelete(items, now: Date(), maxAgeDays: days, maxBytes: Int64(gigabytes) * 1_000_000_000, protected: [])
            return "captures=\(items.count) total=\(total) wouldDelete=\(doomed.count)"

        default:
            return nil
        }
    }

    /// The labels of Space's buttons that remove files: a review footer and its confirmation
    /// ("Move 2 folders, 1 GB to the Trash", "Delete 3 items, 2 GB") and "Delete … for good".
    static func isSpaceRemovalLabel(_ label: String) -> Bool {
        let patterns = [
            "^Move [0-9]+ folders?, .+ to the Trash$",
            "^Delete [0-9]+ (folders?|items?), .+$",
            "^Delete (this folder|these [0-9]+ folders) for good, .+$",
        ]
        for pattern in patterns where label.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// The project settings as they were before space-fake-home:on, and which of them the person
    /// had set (the others were defaults, and go back to being defaults).
    private struct SavedProjectSettings {
        let projectRoots: [String]
        let oldProjectDays: Int
        let projectFoldersToTrash: Bool
        let dependencyKinds: Set<DependencyKind>
        let hiddenCacheRows: Set<String>
        let storedKeys: Set<String>
    }

    private static var savedProjectSettings: SavedProjectSettings?

    private static let projectSettingKeys = ["projectRoots", "oldProjectDays", "projectFoldersToTrash", "dependencyKinds", "hiddenCacheRows"]

    private static func saveProjectSettings() {
        // Turned on twice: the first copy is what the person had.
        if savedProjectSettings != nil {
            return
        }
        let settings = AppSettings.shared
        var stored: Set<String> = []
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        for key in projectSettingKeys where domain[key] != nil {
            stored.insert(key)
        }
        savedProjectSettings = SavedProjectSettings(
            projectRoots: settings.projectRoots,
            oldProjectDays: settings.oldProjectDays,
            projectFoldersToTrash: settings.projectFoldersToTrash,
            dependencyKinds: settings.dependencyKinds,
            hiddenCacheRows: settings.hiddenCacheRows,
            storedKeys: stored
        )
    }

    private static func restoreProjectSettings() {
        guard let saved = savedProjectSettings else {
            return
        }
        let settings = AppSettings.shared
        settings.projectRoots = saved.projectRoots
        settings.oldProjectDays = saved.oldProjectDays
        settings.projectFoldersToTrash = saved.projectFoldersToTrash
        settings.dependencyKinds = saved.dependencyKinds
        settings.hiddenCacheRows = saved.hiddenCacheRows
        for key in projectSettingKeys where !saved.storedKeys.contains(key) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        savedProjectSettings = nil
    }

    /// The projects of the made-up home: old-app (60 days old), fresh-app (changed now), a build
    /// folder that is no Gradle project, a project whose node_modules is in git, and a link back
    /// to the home folder. Only the first two have folders to offer.
    private static func makeFakeProjects(in projects: URL, home: URL) {
        let files = FileManager.default
        for name in ["old-app", "fresh-app", "vendored"] {
            let project = projects.appendingPathComponent(name)
            let package = project.appendingPathComponent("node_modules/pkg")
            try? files.createDirectory(at: package, withIntermediateDirectories: true)
            try? Data(count: 5_000_000).write(to: package.appendingPathComponent("index.js"))
            try? Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        }
        let plainBuild = projects.appendingPathComponent("plain/build")
        try? files.createDirectory(at: plainBuild, withIntermediateDirectories: true)
        try? Data(count: 1_000_000).write(to: plainBuild.appendingPathComponent("output.bin"))
        try? files.createSymbolicLink(at: projects.appendingPathComponent("link-home"), withDestinationURL: home)
        let vendored = projects.appendingPathComponent("vendored")
        for arguments in [["init", "-q"], ["add", "node_modules", "package.json"]] {
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["-C", vendored.path] + arguments
            git.standardOutput = FileHandle.nullDevice
            git.standardError = FileHandle.nullDevice
            try? git.run()
            git.waitUntilExit()
        }
        // Every file and folder of old-app dates from 60 days ago, the project folder too.
        let sixtyDaysAgo = Date().addingTimeInterval(-60 * 86400)
        let oldApp = projects.appendingPathComponent("old-app")
        var paths: [String] = []
        if let walker = files.enumerator(atPath: oldApp.path) {
            for case let relative as String in walker {
                paths.append(oldApp.appendingPathComponent(relative).path)
            }
        }
        paths.append(oldApp.path)
        for path in paths {
            try? files.setAttributes([.modificationDate: sixtyDaysAgo], ofItemAtPath: path)
        }
    }

    /// Measures the categories of the home now in use. A measure already running (of the other
    /// home, started by an open window) only queues another one, so wait for both to end.
    private static func measureFully(_ space: SpaceModel) async {
        await space.measure(force: true)
        var waited = 0
        while space.isMeasuring && waited < 1200 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
    }
}
#endif
