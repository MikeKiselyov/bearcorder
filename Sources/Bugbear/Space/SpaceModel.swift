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
        /// Asking macOS for the protected folders before the scan, so it runs without interruptions.
        case preparing
        case running(DiskScanner.Progress)
        case done(seconds: Double)
    }

    /// One protected folder macOS asks about, checked before the scan.
    struct AccessCheck: Identifiable {
        enum State {
            case waiting
            case asking
            case allowed
            case denied
        }

        let id: String
        let url: URL
        /// Paths below the home folder to leave out of the scan when access is denied.
        let skipWhenDenied: String
        var state: State = .waiting
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

    private(set) var scanState: ScanState = .idle {
        didSet { lastScanProgress = Date() }
    }
    /// When the scan last reported progress. A long pause usually means macOS is showing a
    /// permission prompt and the scan waits for the answer.
    private(set) var lastScanProgress = Date()
    private(set) var tree: DiskTree?
    private(set) var topFiles: [TopFiles.File] = []
    /// The folder shown in "Folders", as names below the home folder.
    var folderPath: [String] = []
    /// The file waiting for "Move to Trash" to be confirmed.
    var confirmingFile: String?

    @ObservationIgnored private var measuredAt: Date?
    @ObservationIgnored private var measureAgain = false
    /// Each scan gets a number; results and progress of an older, stopped scan are ignored.
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var scanStop = DiskScanner.StopFlag()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// Tests point this at a made-up home folder.
    @ObservationIgnored var homeOverride: URL?
    /// And this at a made-up Applications folder, so a scan stays inside the test's files.
    @ObservationIgnored var applicationsOverride: URL?
    /// Tests: a wait before scanning, so a scan of a tiny made-up home is still running for "Stop".
    @ObservationIgnored var scanStartDelay: Double = 0

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
        if isMeasuring {
            // A clean while sizes are being measured: measure again once this one ends, or the
            // cleaned category would keep showing its old size.
            if force {
                measureAgain = true
            }
            return
        }
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
        if measureAgain {
            measureAgain = false
            await measure(force: true)
        }
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
        switch scanState {
        case .preparing, .running:
            return true
        case .idle, .done:
            return false
        }
    }

    private(set) var accessChecks: [AccessCheck] = []
    private(set) var scanStartedAt = Date()

    /// Folders macOS refused, which the result does not include.
    var deniedFolders: [String] {
        var names: [String] = []
        for check in accessChecks where check.state == .denied {
            names.append(check.id)
        }
        return names
    }

    /// Also scan other apps' private data in ~/Library (Docker images often live there). macOS asks once.
    var includeAppData: Bool = UserDefaults.standard.bool(forKey: "spaceIncludeAppData") {
        didSet { UserDefaults.standard.set(includeAppData, forKey: "spaceIncludeAppData") }
    }
    /// What the last scan covered, to open folders in Finder.
    @ObservationIgnored private var scanRoots: [DiskScanner.Root] = []

    /// Bytes in use on the disk that the scan did not see: macOS itself, other users, skipped folders,
    /// local snapshots.
    var notCounted: Int64 {
        guard let scanned = tree?.root.bytes else { return 0 }
        return max(0, volumeTotal - volumeFree - scanned)
    }

    /// Scans the home folder and /Applications, or just `subfolder` of home (used by tests).
    func startScan(subfolder: String? = nil) {
        if isScanning { return }
        scanStartedAt = Date()
        scanState = .preparing
        folderPath = []
        refreshVolume()
        var roots: [DiskScanner.Root] = []
        if let inner = subfolder {
            // The skip list is relative to the home folder; make it relative to the subfolder.
            var relative: [String] = []
            for path in DiskScanner.skippedInScan where path.hasPrefix(inner + "/") {
                relative.append(String(path.dropFirst(inner.count + 1)))
            }
            roots.append(DiskScanner.Root(name: inner, url: home.appendingPathComponent(inner), skip: relative))
        } else {
            roots.append(DiskScanner.Root(name: "Home", url: home, skip: DiskScanner.skippedInScan))
            roots.append(DiskScanner.Root(name: "Applications", url: applicationsOverride ?? URL(fileURLWithPath: "/Applications"), skip: []))
        }
        var checks: [AccessCheck] = []
        if subfolder == nil {
            for name in ["Desktop", "Documents", "Downloads"] {
                checks.append(AccessCheck(id: name, url: home.appendingPathComponent(name), skipWhenDenied: name))
            }
            if includeAppData {
                checks.append(AccessCheck(id: "Other apps' data", url: home.appendingPathComponent("Library/Containers"), skipWhenDenied: "Library/Containers"))
            }
        }
        accessChecks = checks
        let withAppData = includeAppData
        scanGeneration += 1
        let generation = scanGeneration
        let stop = DiskScanner.StopFlag()
        scanStop = stop
        scanTask = Task {
            // 1. Every permission prompt now, one after another, while the person is looking.
            for index in checks.indices {
                if generation != scanGeneration { return }
                accessChecks[index].state = .asking
                let folder = checks[index].url
                let isAppData = checks[index].skipWhenDenied == "Library/Containers"
                let allowed = await Task.detached(priority: .userInitiated) { () -> Bool in
                    return SpaceModel.canRead(folder, insideAnApp: isAppData)
                }.value
                // Stopped (and maybe restarted with other checks) while macOS was asking.
                if generation != scanGeneration { return }
                accessChecks[index].state = allowed ? .allowed : .denied
                Log.info("space: access to \(checks[index].id) \(allowed ? "allowed" : "denied")")
            }
            // Denied folders are left out instead of failing file by file.
            if !roots.isEmpty && roots[0].name == "Home" {
                for check in accessChecks where check.state == .denied {
                    roots[0].skip.append(check.skipWhenDenied)
                }
            }
            if generation != scanGeneration { return }
            scanRoots = roots
            let scanRootsNow = roots
            scanState = .running(DiskScanner.Progress())
            if scanStartDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(scanStartDelay * 1_000_000_000))
                if generation != scanGeneration { return }
            }
            // 2. The scan itself.
            let result = await Task.detached(priority: .utility) { () -> DiskScanner.ScanResult? in
                return DiskScanner.scan(roots: scanRootsNow, includeAppData: withAppData, stop: stop) { progress in
                    Task { @MainActor in
                        let model = SpaceModel.shared
                        guard generation == model.scanGeneration, case .running = model.scanState else { return }
                        model.scanState = .running(progress)
                    }
                }
            }.value
            if generation != scanGeneration { return }
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

    /// Opening a protected folder is what makes macOS ask; this returns once it is answered.
    /// For other apps' data the prompt comes from looking inside one app's container.
    nonisolated static func canRead(_ folder: URL, insideAnApp: Bool) -> Bool {
        let files = FileManager.default
        guard let items = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: []) else { return false }
        if !insideAnApp { return true }
        for item in items where !item.lastPathComponent.hasPrefix("com.apple.") {
            let data = item.appendingPathComponent("Data")
            if files.fileExists(atPath: data.path) {
                return (try? files.contentsOfDirectory(atPath: data.path)) != nil
            }
        }
        return true
    }

    func cancelScan() {
        scanStop.stop()
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        scanState = .idle
    }

    /// The folder currently open in "Folders".
    var currentFolder: DiskTree.Node? {
        return tree?.node(at: folderPath)
    }

    /// The folder on disk for a path in the tree; the first name is the scanned root.
    func url(forFolder path: [String]) -> URL? {
        guard let first = path.first, let root = scanRoots.first(where: { item in item.name == first }) else { return nil }
        var url = root.url
        for name in path.dropFirst() {
            url = url.appendingPathComponent(name)
        }
        return url
    }

    // MARK: Files

    func reveal(_ url: URL) {
        SystemActions.reveal([url])
    }

    /// Moves a file to the Trash, where it can still be put back.
    func moveToTrash(_ path: String) {
        confirmingFile = nil
        do {
            try SystemActions.trash(URL(fileURLWithPath: path))
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
