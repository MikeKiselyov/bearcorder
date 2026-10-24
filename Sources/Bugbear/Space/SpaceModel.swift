import AppKit
import BugbearCore
import Observation

/// Disk space: how full the disk is, what can be cleaned, and what takes the most room in the home folder.
@MainActor
@Observable
final class SpaceModel {
    static let shared = SpaceModel()

    enum ScanState {
        case idle
        case running(DiskScanner.Progress)
        case done(seconds: Double)
    }

    var volumeTotal: Int64 = 0
    var volumeFree: Int64 = 0
    /// Bytes per category id; missing while measuring or when the folder does not exist.
    private(set) var sizes: [String: Int64] = [:]
    private(set) var isMeasuring = false
    private(set) var cleaningID: String?
    /// The category waiting for "Delete" to be confirmed.
    var confirmingID: String?
    /// Last result line, e.g. "Freed 3.2 GB from App caches".
    var message: String?

    private(set) var scanState: ScanState = .idle
    private(set) var tree: DiskTree?
    private(set) var topFiles: [TopFiles.File] = []
    /// The folder shown in "Folders", as names below the home folder.
    var folderPath: [String] = []
    /// The file waiting for "Move to Trash" to be confirmed.
    var confirmingFile: String?

    @ObservationIgnored private var measuredAt: Date?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// Tests point this at a made-up home folder.
    @ObservationIgnored var homeOverride: URL?

    var home: URL {
        return homeOverride ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// Categories with something in them, biggest first. Our captures always show.
    var visibleCategories: [CleanupCategory] {
        var list: [CleanupCategory] = []
        for category in CleanupCategory.all {
            let bytes = sizes[category.id] ?? 0
            if bytes > 0 || category.action == .openCaptures {
                list.append(category)
            }
        }
        list.sort { first, second in (sizes[first.id] ?? 0) > (sizes[second.id] ?? 0) }
        return list
    }

    var cleanableBytes: Int64 {
        var total: Int64 = 0
        for category in CleanupCategory.all where category.action == .deleteContents {
            total += sizes[category.id] ?? 0
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Disk and categories

    func refreshVolume() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        volumeTotal = Int64(values.volumeTotalCapacity ?? 0)
        volumeFree = values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Measures every category. Skipped when done less than a minute ago, unless `force`.
    func measure(force: Bool = false) async {
        refreshVolume()
        if isMeasuring { return }
        if !force, let last = measuredAt, Date().timeIntervalSince(last) < 60 { return }
        isMeasuring = true
        let root = home
        let measured = await Task.detached(priority: .utility) { () -> [String: Int64] in
            var result: [String: Int64] = [:]
            for category in CleanupCategory.all {
                result[category.id] = DiskScanner.size(of: category, home: root)
            }
            return result
        }.value
        sizes = measured
        measuredAt = Date()
        isMeasuring = false
    }

    func clean(_ category: CleanupCategory) async {
        guard category.action == .deleteContents, cleaningID == nil else { return }
        confirmingID = nil
        cleaningID = category.id
        let root = home
        let freed = await Task.detached(priority: .userInitiated) { () -> Int64 in
            return DiskScanner.clean(category, home: root)
        }.value
        Log.info("space: cleaned \(category.id), freed \(freed) bytes")
        message = "Freed \(SpaceModel.format(freed)) from \(category.title)"
        cleaningID = nil
        await measure(force: true)
    }

    // MARK: Scan

    var isScanning: Bool {
        if case .running = scanState { return true }
        return false
    }

    /// Scans the home folder, or `subfolder` of it (used by tests).
    func startScan(subfolder: String? = nil) {
        if isScanning { return }
        scanState = .running(DiskScanner.Progress())
        folderPath = []
        var root = home
        var skip = DiskScanner.skippedInScan
        if let inner = subfolder {
            root = home.appendingPathComponent(inner)
            // The skip list is relative to the home folder; make it relative to the new root.
            var relative: [String] = []
            for path in DiskScanner.skippedInScan where path.hasPrefix(inner + "/") {
                relative.append(String(path.dropFirst(inner.count + 1)))
            }
            skip = relative
        }
        scanTask = Task {
            let result = await Task.detached(priority: .utility) { () -> DiskScanner.ScanResult? in
                return DiskScanner.scan(root: root, skip: skip) { progress in
                    Task { @MainActor in
                        if SpaceModel.shared.isScanning {
                            SpaceModel.shared.scanState = .running(progress)
                        }
                    }
                }
            }.value
            guard let finished = result else {
                scanState = .idle
                return
            }
            tree = finished.tree
            topFiles = finished.topFiles
            scanState = .done(seconds: finished.seconds)
            Log.info(String(format: "space: scanned %d files, %@ in %.1fs", finished.tree.root.fileCount, SpaceModel.format(finished.tree.root.bytes), finished.seconds))
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanState = .idle
    }

    /// The folder currently open in "Folders".
    var currentFolder: DiskTree.Node? {
        return tree?.node(at: folderPath)
    }

    func url(forFolder path: [String]) -> URL {
        var url = home
        for name in path {
            url = url.appendingPathComponent(name)
        }
        return url
    }

    // MARK: Files

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Moves a file to the Trash, where it can still be put back.
    func moveToTrash(_ path: String) {
        confirmingFile = nil
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            var kept: [TopFiles.File] = []
            var freed: Int64 = 0
            for file in topFiles {
                if file.path == path {
                    freed = file.bytes
                } else {
                    kept.append(file)
                }
            }
            topFiles = kept
            message = "Moved \((path as NSString).lastPathComponent) to the Trash (\(SpaceModel.format(freed))). Empty the Trash to free the space."
            refreshVolume()
        } catch {
            message = "Could not move it to the Trash: \(error.localizedDescription)"
        }
    }
}
