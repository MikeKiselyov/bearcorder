import AppKit
import BugbearCore
import Observation

/// A list of things Space can remove, each with a checkbox: the dependency folders found in projects,
/// or the items of one cache category. Removing takes only the ticked rows that are still exactly
/// what the scan saw; everything else is left alone and reported.
@MainActor
@Observable
final class SpaceReview {
    struct Row: Identifiable {
        /// The standardized path.
        let id: String
        let title: String
        let path: String
        let bytes: Int64
        /// Days since the project last changed; nil for cache items.
        let age: Int?
        var isChecked: Bool
    }

    struct RemovalResult {
        var removed: [String] = []
        var skipped: [(path: String, reason: String)] = []
        var freedBytes: Int64 = 0
        /// Where the removed project folders are now, to delete them for good later.
        var trashed: [URL] = []
        /// What each trashed item was right after the move, by standardized path: delete for good
        /// removes only an item that is still that one.
        var trashedSnapshots: [String: FolderSnapshot] = [:]
        /// The size of each trashed item, by standardized path, for "Delete … for good".
        var trashedBytes: [String: Int64] = [:]

        /// What the items still in the Trash take.
        var trashedTotal: Int64 {
            var total: Int64 = 0
            for url in trashed {
                total += trashedBytes[url.standardizedFileURL.path] ?? 0
            }
            return total
        }
    }

    /// How one row is removed, what removing it needs and the rest of a removal live in BugbearCore.
    typealias Way = SpaceRemoval.Way
    typealias Plan = SpaceRemoval.Plan
    typealias Context = SpaceRemoval.Context

    var rows: [Row]
    /// Dependency folders found in projects (with ages), not the items of a cache category.
    let isProjectList: Bool
    /// The confirmation with the numbers is showing.
    var isConfirming = false
    /// The question before deleting the trashed folders for good is showing.
    var isConfirmingForGood = false
    private(set) var isRemoving = false
    var lastResult: RemovalResult?

    @ObservationIgnored private var plans: [String: Plan] = [:]
    @ObservationIgnored private let context: Context

    var selectedBytes: Int64 {
        var total: Int64 = 0
        for row in rows where row.isChecked {
            total += row.bytes
        }
        return total
    }

    /// Every row, ticked or not.
    var totalBytes: Int64 {
        var total: Int64 = 0
        for row in rows {
            total += row.bytes
        }
        return total
    }

    /// Ticked rows go to the Trash instead of being deleted at once.
    var movesToTrash: Bool {
        return isProjectList && context.projectsToTrash
    }

    var selectedCount: Int {
        var count = 0
        for row in rows where row.isChecked {
            count += 1
        }
        return count
    }

    /// Dependency folders from a project scan. Rows start ticked when the project is at least
    /// `oldProjectDays` old.
    init(projects scan: ProjectScanResult, settings: AppSettings, now: Date = Date()) {
        let space = SpaceModel.shared
        context = Context(
            home: space.home,
            trashOverride: space.trashOverride,
            projectsToTrash: settings.projectFoldersToTrash,
            kinds: settings.dependencyKinds,
            cleanCommand: nil,
            homeIsOverridden: space.homeOverride != nil
        )
        isProjectList = true
        var list: [Row] = []
        for dependency in scan.found {
            let url = dependency.url.standardizedFileURL
            let path = url.path
            if plans[path] != nil {
                continue
            }
            // A project with no dated file has no known age: it is listed but never ticked on its own.
            var age: Int?
            var isOld = false
            if dependency.lastChanged != Date.distantPast {
                let seconds = now.timeIntervalSince(dependency.lastChanged)
                let days = max(0, Int((seconds / 86400).rounded(.down)))
                age = days
                isOld = days >= settings.oldProjectDays
            }
            let projectParent = dependency.projectRoot.deletingLastPathComponent().standardizedFileURL.path
            var title = path
            if path.hasPrefix(projectParent + "/") {
                title = String(path.dropFirst(projectParent.count + 1))
            }
            list.append(Row(id: path, title: title, path: path, bytes: dependency.bytes, age: age, isChecked: isOld))
            plans[path] = Plan(url: url, bytes: dependency.bytes, snapshot: dependency.snapshot, way: .projectFolder(dependency.kind))
        }
        list.sort { first, second in first.bytes > second.bytes }
        rows = list
    }

    /// The items of one cache category (`cacheItems(of:home:)`), ticked unless the category says
    /// its rows start unticked (Maven: locally installed artifacts may not come back).
    init(category: CleanupCategory, items: [CacheItem], settings: AppSettings) {
        let space = SpaceModel.shared
        let home = space.home
        context = Context(
            home: home,
            trashOverride: space.trashOverride,
            projectsToTrash: settings.projectFoldersToTrash,
            kinds: settings.dependencyKinds,
            cleanCommand: category.cleanCommand,
            homeIsOverridden: space.homeOverride != nil
        )
        isProjectList = false
        rows = []
        // Only categories whose contents may be deleted get rows; our captures never do.
        if category.action != .deleteContents {
            return
        }
        var allowedRoots: [URL] = []
        for folder in category.folders {
            allowedRoots.append(home.appendingPathComponent(folder).standardizedFileURL)
        }
        var list: [Row] = []
        for item in items {
            let url = item.url.standardizedFileURL
            let path = url.path
            if plans[path] != nil {
                continue
            }
            var way = Way.cacheItem(allowedRoots: allowedRoots)
            if category.itemMode == .wholeFolder {
                way = .folderContents(declaredFolders: allowedRoots)
            }
            list.append(Row(id: path, title: item.name, path: path, bytes: item.bytes, age: nil, isChecked: category.startsTicked))
            plans[path] = Plan(url: url, bytes: item.bytes, snapshot: item.snapshot, way: way)
        }
        rows = list
    }

    /// The rows of a cache category: one per child of its folders, or one per folder for categories
    /// cleaned as a whole. Measures sizes, so call it away from the main thread.
    nonisolated static func cacheItems(of category: CleanupCategory, home: URL) -> [CacheItem] {
        if category.action != .deleteContents {
            return []
        }
        var folders: [URL] = []
        for folder in category.folders {
            folders.append(home.appendingPathComponent(folder))
        }
        if category.itemMode == .perChild {
            var keep: Set<String> = []
            for path in category.keep {
                keep.insert(home.appendingPathComponent(path).standardizedFileURL.path)
            }
            return CacheItems.children(of: folders, keep: keep, nameFor: CleanupCategory.itemName)
        }
        var items: [CacheItem] = []
        for (index, folder) in folders.enumerated() {
            let values = try? folder.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true || values?.isDirectory != true {
                continue
            }
            let bytes = FileSizes.folder(folder)
            if bytes == 0 {
                continue
            }
            guard let snapshot = FolderSnapshot.take(of: folder, marker: nil, projectRoot: nil, projectChanged: nil) else {
                continue
            }
            items.append(CacheItem(url: folder, name: "~/" + category.folders[index], bytes: bytes, snapshot: snapshot))
        }
        return items
    }

    // MARK: Removing

    /// Removes the ticked rows. A row that fails is reported with its reason and the others go on.
    @discardableResult
    func remove() async -> RemovalResult {
        isConfirming = false
        isConfirmingForGood = false
        if isRemoving {
            return RemovalResult()
        }
        isRemoving = true
        var checked: [Plan] = []
        for row in rows where row.isChecked {
            if let plan = plans[row.id] {
                checked.append(plan)
            }
        }
        let context = self.context
        let result = await Task.detached(priority: .userInitiated) { () -> RemovalResult in
            return SpaceReview.remove(checked, context: context)
        }.value

        let removed = Set(result.removed)
        var kept: [Row] = []
        for row in rows {
            if removed.contains(row.id) {
                plans[row.id] = nil
            } else {
                kept.append(row)
            }
        }
        rows = kept
        lastResult = result
        isRemoving = false
        return result
    }

    /// The first press of "Delete … for good": only asks. Nothing is deleted until the question
    /// is answered with `deleteTrashedForGood()`.
    func askDeleteForGood() {
        guard let result = lastResult, !result.trashed.isEmpty, !isRemoving else {
            return
        }
        isConfirming = false
        isConfirmingForGood = true
    }

    /// Deletes for good what the last removal moved to the Trash, and nothing else in the Trash.
    /// An item another one replaced in the Trash is not deleted and is reported with the skipped rows.
    func deleteTrashedForGood() async {
        isConfirmingForGood = false
        guard var result = lastResult, !result.trashed.isEmpty, !isRemoving else {
            return
        }
        isRemoving = true
        let trashed = result.trashed
        let snapshots = result.trashedSnapshots
        let context = self.context
        let outcome = await Task.detached(priority: .userInitiated) { () -> (left: [URL], skipped: [(path: String, reason: String)]) in
            return SpaceReview.deleteForGood(trashed, snapshots: snapshots, context: context)
        }.value
        result.trashed = outcome.left
        result.skipped.append(contentsOf: outcome.skipped)
        lastResult = result
        isRemoving = false
    }

    /// Removes in BugbearCore and puts the reasons into words.
    nonisolated private static func remove(_ plans: [Plan], context: Context) -> RemovalResult {
        let core = SpaceRemoval.remove(plans, context: context, log: log)
        var result = RemovalResult()
        result.removed = core.removed
        result.skipped = texts(for: core.skipped)
        result.freedBytes = core.freedBytes
        result.trashed = core.trashed
        result.trashedSnapshots = core.trashedSnapshots
        result.trashedBytes = core.trashedBytes
        return result
    }

    nonisolated private static func deleteForGood(_ trashed: [URL], snapshots: [String: FolderSnapshot], context: Context) -> (left: [URL], skipped: [(path: String, reason: String)]) {
        let outcome = SpaceRemoval.deleteForGood(trashed, snapshots: snapshots, context: context, log: log)
        return (left: outcome.left, skipped: texts(for: outcome.skipped))
    }

    /// Failures go to the log as errors, the rest as info, as before the removal moved to BugbearCore.
    nonisolated private static func log(_ message: String) {
        if message.hasPrefix("space: could not") {
            Log.error(message)
        } else {
            Log.info(message)
        }
    }

    nonisolated private static func texts(for skipped: [(path: String, reason: SpaceRemoval.SkipReason)]) -> [(path: String, reason: String)] {
        var list: [(path: String, reason: String)] = []
        for item in skipped {
            list.append((path: item.path, reason: reasonText(for: item.reason)))
        }
        return list
    }

    /// The words shown for a skipped row.
    nonisolated static func reasonText(for reason: SpaceRemoval.SkipReason) -> String {
        switch reason {
        case .refused(let refusal):
            return reasonText(for: refusal)
        case .changed(let change):
            if change == .gone {
                return L("space.review.skip.gone")
            }
            return L("space.review.skip.changed")
        case .notAllowed:
            return L("space.review.skip.notAllowed")
        case .gone:
            return L("space.review.skip.gone")
        case .failed(let description):
            return L("space.review.skip.failed", description)
        case .commandFailed(let command):
            return L("space.review.skip.failed", command)
        case .trashReplaced:
            return L("space.review.skip.trashReplaced")
        }
    }

    nonisolated private static func reasonText(for refusal: RemovalRefusal) -> String {
        switch refusal {
        case .missing:
            return L("space.review.skip.gone")
        case .throughLink:
            return L("space.review.skip.link")
        case .outsideHome, .homeOrTopFolder, .notAllowedName, .notInDeclaredCache, .notTrashedByBugbear:
            return L("space.review.skip.notAllowed")
        }
    }

    // MARK: Git

    /// True when git tracks anything in the folder: such a folder belongs to the repository and is
    /// not offered. Any git failure (no repository, no git) means not tracked. A git that does not
    /// answer in 10 seconds counts as tracked, so a folder is never offered on a guess.
    nonisolated static func isTrackedByGit(_ folder: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // No fsmonitor: a repository's hook must not start a daemon or run a program for this question.
        process.arguments = ["-c", "core.fsmonitor=false", "-C", folder.deletingLastPathComponent().path, "ls-files", "-z", "--", folder.lastPathComponent]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let stopper = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: stopper)
        // The first bytes are enough: one tracked file means tracked.
        let firstBytes = output.fileHandleForReading.availableData
        if !firstBytes.isEmpty {
            stopper.cancel()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            return true
        }
        process.waitUntilExit()
        stopper.cancel()
        if process.terminationReason == .uncaughtSignal {
            Log.info("space: git did not answer for \(folder.path); not offered")
            return true
        }
        return false
    }
}
