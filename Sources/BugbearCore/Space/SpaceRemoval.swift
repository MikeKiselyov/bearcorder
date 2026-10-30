import Foundation

/// Removes the rows ticked in Space: only those that pass the gate and are still exactly what the
/// scan saw. A row that fails is reported with its reason and the others go on.
public enum SpaceRemoval {
    /// How one row is removed.
    public enum Way: Sendable {
        /// A dependency folder inside a project: to the Trash or deleted, as the settings say.
        case projectFolder(DependencyKind)
        /// One child of a cache folder, deleted.
        case cacheItem(allowedRoots: [URL])
        /// What is inside a cache folder, deleted; the folder itself stays. The folder must be
        /// exactly one of the category's declared folders, and each child is checked against them.
        case folderContents(declaredFolders: [URL])
    }

    /// What removing a row needs, fixed when the list is made.
    public struct Plan: Sendable {
        /// Standardized once; the same URL goes to the gate, the snapshot check and the removal.
        public let url: URL
        public let bytes: Int64
        public let snapshot: FolderSnapshot
        public let way: Way

        public init(url: URL, bytes: Int64, snapshot: FolderSnapshot, way: Way) {
            self.url = url.standardizedFileURL
            self.bytes = bytes
            self.snapshot = snapshot
            self.way = way
        }
    }

    /// Everything a removal needs besides the rows, so it can run away from the main thread.
    public struct Context: Sendable {
        public let home: URL
        /// Tests: a folder used as the Trash. nil means the real Trash.
        public let trashOverride: URL?
        public let projectsToTrash: Bool
        public let kinds: Set<DependencyKind>
        /// Run instead of removing files (Go's module cache).
        public let cleanCommand: [String]?
        /// The home is a made-up one (tests): without a test Trash nothing goes to the real Trash.
        public let homeIsOverridden: Bool

        public init(home: URL, trashOverride: URL?, projectsToTrash: Bool, kinds: Set<DependencyKind>, cleanCommand: [String]?, homeIsOverridden: Bool) {
            self.home = home
            self.trashOverride = trashOverride
            self.projectsToTrash = projectsToTrash
            self.kinds = kinds
            self.cleanCommand = cleanCommand
            self.homeIsOverridden = homeIsOverridden
        }
    }

    /// Why a row was left alone.
    public enum SkipReason: Equatable, Sendable {
        /// The gate refused the folder (or, for folder contents, one of its children).
        case refused(RemovalRefusal)
        /// The folder is not the one the scan saw.
        case changed(SnapshotChange)
        /// A place Space does not remove from here: a made-up home with the real Trash, or a clean
        /// command with a made-up home.
        case notAllowed
        /// The folder could not be read any more.
        case gone
        /// Moving or deleting failed, with the system's description.
        case failed(String)
        /// The clean command left files behind; the command as one line.
        case commandFailed(String)
        /// Delete for good: another item with the same name is in the Trash now.
        case trashReplaced
    }

    public struct Result: Sendable {
        public var removed: [String] = []
        public var skipped: [(path: String, reason: SkipReason)] = []
        public var freedBytes: Int64 = 0
        /// Where the removed project folders are now, to delete them for good later.
        public var trashed: [URL] = []
        /// What each trashed item was right after the move, by standardized path: delete for good
        /// removes only an item that is still that one.
        public var trashedSnapshots: [String: FolderSnapshot] = [:]
        /// The size of each trashed item, by standardized path, for "Delete … for good".
        public var trashedBytes: [String: Int64] = [:]

        public init() {}

        /// What the items still in the Trash take.
        public var trashedTotal: Int64 {
            var total: Int64 = 0
            for url in trashed {
                total += trashedBytes[url.standardizedFileURL.path] ?? 0
            }
            return total
        }
    }

    public static func remove(_ plans: [Plan], context: Context, log: (String) -> Void) -> Result {
        var result = Result()
        var commandRows: [Plan] = []
        for plan in plans {
            let path = plan.url.path
            if let reason = gateReason(for: plan, home: context.home, log: log) {
                result.skipped.append((path: path, reason: reason))
                log("space: skipped \(path): \(reason)")
                continue
            }
            if let reason = changeReason(for: plan, kinds: context.kinds) {
                result.skipped.append((path: path, reason: reason))
                log("space: skipped \(path): \(reason)")
                continue
            }
            if context.cleanCommand != nil {
                commandRows.append(plan)
                continue
            }
            switch plan.way {
            case .projectFolder:
                if context.projectsToTrash {
                    if context.homeIsOverridden && context.trashOverride == nil {
                        // A made-up home with the real Trash: nothing from a test reaches the real Trash.
                        result.skipped.append((path: path, reason: .notAllowed))
                        log("space: skipped \(path): made-up home without a test Trash")
                        continue
                    }
                    do {
                        let moved = try moveToTrash(plan.url, trashOverride: context.trashOverride)
                        if let moved = moved {
                            let movedURL = moved.standardizedFileURL
                            result.trashed.append(movedURL)
                            if let snapshot = FolderSnapshot.take(of: movedURL, marker: nil, projectRoot: nil, projectChanged: nil) {
                                result.trashedSnapshots[movedURL.path] = snapshot
                            }
                            result.trashedBytes[movedURL.path] = plan.bytes
                        }
                        result.removed.append(path)
                        result.freedBytes += plan.bytes
                        log("space: removed \(path) \(plan.bytes) trash")
                    } catch {
                        result.skipped.append((path: path, reason: .failed(error.localizedDescription)))
                        log("space: could not move \(path) to the Trash: \(error.localizedDescription)")
                    }
                } else {
                    deleteRow(plan, into: &result, log: log)
                }
            case .cacheItem:
                deleteRow(plan, into: &result, log: log)
            case .folderContents(let declaredFolders):
                deleteContents(plan, declaredFolders: declaredFolders, into: &result, home: context.home, log: log)
            }
        }
        if let command = context.cleanCommand, !commandRows.isEmpty {
            runCommand(command, rows: commandRows, into: &result, home: context.home, log: log)
        }
        return result
    }

    private static func deleteRow(_ plan: Plan, into result: inout Result, log: (String) -> Void) {
        let path = plan.url.path
        do {
            try FileManager.default.removeItem(at: plan.url)
            result.removed.append(path)
            result.freedBytes += plan.bytes
            log("space: removed \(path) \(plan.bytes) deleted")
        } catch {
            result.skipped.append((path: path, reason: .failed(error.localizedDescription)))
            log("space: could not delete \(path): \(error.localizedDescription)")
        }
    }

    /// Deletes what is inside a cache folder; each child goes through the gate on its own, against
    /// the category's declared folders (never against the row's own path).
    private static func deleteContents(_ plan: Plan, declaredFolders: [URL], into result: inout Result, home: URL, log: (String) -> Void) {
        let path = plan.url.path
        let files = FileManager.default
        guard let children = try? files.contentsOfDirectory(at: plan.url, includingPropertiesForKeys: nil, options: []) else {
            result.skipped.append((path: path, reason: .gone))
            return
        }
        var failure: SkipReason?
        for child in children {
            let childURL = child.standardizedFileURL
            if childURL.lastPathComponent.hasPrefix("com.apple.") {
                continue
            }
            if let refusal = RemovalGate.refusal(for: childURL, target: .cacheItem(allowedRoots: declaredFolders), home: home) {
                failure = .refused(refusal)
                log("space: skipped \(childURL.path): \(refusal)")
                continue
            }
            do {
                try files.removeItem(at: childURL)
            } catch {
                failure = .failed(error.localizedDescription)
                log("space: could not delete \(childURL.path): \(error.localizedDescription)")
            }
        }
        let left = FileSizes.folder(plan.url)
        let freed = max(0, plan.bytes - left)
        result.freedBytes += freed
        if let failure = failure {
            result.skipped.append((path: path, reason: failure))
            return
        }
        result.removed.append(path)
        log("space: removed \(path) \(freed) deleted")
    }

    /// A category cleaned by its own tool runs the tool once for all its ticked rows.
    private static func runCommand(_ command: [String], rows: [Plan], into result: inout Result, home: URL, log: (String) -> Void) {
        // The tool works on the real home; with a made-up home (tests) it is not run.
        let realHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if home.standardizedFileURL.path != realHome {
            for plan in rows {
                result.skipped.append((path: plan.url.path, reason: .notAllowed))
            }
            return
        }
        var before: Int64 = 0
        for plan in rows {
            before += FileSizes.folder(plan.url)
        }
        // The tool cleans only the folder that passed the gate and the snapshot check
        // (go clean -modcache cleans $GOMODCACHE, which may point elsewhere).
        for plan in rows {
            runTool(command, environment: ["GOMODCACHE": plan.url.path])
        }
        var after: Int64 = 0
        for plan in rows {
            after += FileSizes.folder(plan.url)
        }
        result.freedBytes += max(0, before - after)
        for plan in rows {
            let path = plan.url.path
            if FileSizes.folder(plan.url) > 0 {
                result.skipped.append((path: path, reason: .commandFailed(command.joined(separator: " "))))
                continue
            }
            result.removed.append(path)
            log("space: removed \(path) \(plan.bytes) deleted")
        }
    }

    /// Runs a clean-up command such as `go clean -modcache` and waits for it. A missing tool is not an error.
    private static func runTool(_ command: [String], environment extra: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin"
        environment["PATH"] = extraPaths + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        for (name, value) in extra {
            environment[name] = value
        }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    /// nil when the gate lets the row's folder be removed.
    private static func gateReason(for plan: Plan, home: URL, log: (String) -> Void) -> SkipReason? {
        let target: RemovalTarget
        switch plan.way {
        case .projectFolder(let kind):
            target = .projectFolder(kind)
        case .cacheItem(let allowedRoots):
            target = .cacheItem(allowedRoots: allowedRoots)
        case .folderContents(let declaredFolders):
            // Only a folder the category declares, exactly; each child is checked again when the
            // contents are deleted. The gate below checks the folder's own way down (links, home).
            var isDeclared = false
            for folder in declaredFolders where folder.standardizedFileURL.path == plan.url.path {
                isDeclared = true
            }
            if !isDeclared {
                log("space: \(plan.url.path) is not a folder of its category")
                return .refused(.notInDeclaredCache)
            }
            target = .cacheItem(allowedRoots: [plan.url.deletingLastPathComponent()])
        }
        guard let refusal = RemovalGate.refusal(for: plan.url, target: target, home: home) else {
            return nil
        }
        return .refused(refusal)
    }

    /// nil when the folder is still the one the scan saw. Project folders are skipped on any change;
    /// caches change on their own, so for them only a folder that is gone or replaced counts.
    private static func changeReason(for plan: Plan, kinds: Set<DependencyKind>) -> SkipReason? {
        let change = plan.snapshot.change(now: plan.url, lastChanged: { root in
            return ProjectDependencies.lastChanged(of: root, kinds: kinds)
        })
        guard let change = change else {
            return nil
        }
        switch plan.way {
        case .projectFolder:
            return .changed(change)
        case .cacheItem, .folderContents:
            if change == .gone || change == .replaced {
                return .changed(change)
            }
            return nil
        }
    }

    // MARK: Trash

    /// The folder the Trash is: the test folder when set, else ~/.Trash.
    private static func trashLocation(_ trashOverride: URL?) -> URL {
        if let folder = trashOverride {
            return folder.standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").standardizedFileURL
    }

    /// Moves a folder to the Trash and returns where it is now (nil when macOS does not say).
    /// With a test Trash it is a plain move into that folder, under a free name.
    private static func moveToTrash(_ url: URL, trashOverride: URL?) throws -> URL? {
        let files = FileManager.default
        guard let folder = trashOverride else {
            var resulting: NSURL?
            try files.trashItem(at: url, resultingItemURL: &resulting)
            if let moved = resulting {
                return moved as URL
            }
            return nil
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = url.lastPathComponent
        var destination = folder.appendingPathComponent(name)
        var number = 2
        while (try? files.attributesOfItem(atPath: destination.path)) != nil {
            destination = folder.appendingPathComponent("\(name) \(number)")
            number += 1
        }
        try files.moveItem(at: url, to: destination)
        return destination
    }

    /// Deletes the given trashed items, each only when it is inside the Trash and the gate agrees.
    /// Returns the ones still there, and the ones left alone because another item took their place.
    public static func deleteForGood(_ trashed: [URL], snapshots: [String: FolderSnapshot], context: Context, log: (String) -> Void) -> (left: [URL], skipped: [(path: String, reason: SkipReason)]) {
        var skipped: [(path: String, reason: SkipReason)] = []
        var trashedPaths: Set<String> = []
        for url in trashed {
            trashedPaths.insert(url.standardizedFileURL.path)
        }
        let trashPrefix = trashLocation(context.trashOverride).path + "/"
        var left: [URL] = []
        for url in trashed {
            let standardized = url.standardizedFileURL
            let path = standardized.path
            if !path.hasPrefix(trashPrefix) {
                log("space: not deleting \(path): not in the Trash")
                left.append(url)
                continue
            }
            if let refusal = RemovalGate.refusal(for: standardized, target: .trashedByBugbear(trashed: trashedPaths), home: context.home) {
                if refusal == .missing {
                    // Already gone (the Trash was emptied): nothing left to delete.
                    continue
                }
                log("space: not deleting \(path): \(refusal)")
                left.append(url)
                continue
            }
            // Still the item this removal moved there? It may have been put back and something
            // else trashed under the same name.
            guard let snapshot = snapshots[path] else {
                log("space: not deleting \(path): no record of what was trashed")
                left.append(url)
                continue
            }
            let change = snapshot.change(now: standardized, lastChanged: { _ in Date.distantPast })
            if change == .gone {
                continue
            }
            if change == .replaced {
                log("space: not deleting \(path): another item is there now")
                skipped.append((path: path, reason: .trashReplaced))
                continue
            }
            do {
                try FileManager.default.removeItem(at: standardized)
                log("space: deleted from the Trash \(path)")
            } catch {
                log("space: could not delete \(path) from the Trash: \(error.localizedDescription)")
                left.append(url)
            }
        }
        return (left: left, skipped: skipped)
    }
}
