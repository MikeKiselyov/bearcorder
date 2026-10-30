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

        /// The name shown in the scan steps: the folder's own name, or a description for other apps' data.
        var title: String {
            if skipWhenDenied == "Library/Containers" {
                return L("space.access.otherAppsData")
            }
            return id
        }
    }

    var volumeTotal: Int64 = 0
    var volumeFree: Int64 = 0
    /// Bytes per category id; missing while measuring or when the folder does not exist.
    private(set) var sizes: [String: Int64] = [:]
    private(set) var isMeasuring = false
    /// The section the Disk Space window shows.
    var section: SpaceView.Section = .cleanUp
    /// The review list open in "Clean up": a category id or `SpaceModel.projectsID`; nil shows the categories.
    var openReviewID: String?
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
    /// Tests point this at a folder used as the Trash, so removals never reach the real Trash.
    @ObservationIgnored var trashOverride: URL?
    /// Pictures for the docs: the disk size and free space shown instead of this Mac's.
    @ObservationIgnored var volumeOverride: (total: Int64, free: Int64)?

    var home: URL {
        return homeOverride ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// The id of the review list of dependency folders found in projects.
    static let projectsID = "projects"

    /// Categories with something in them, biggest first. Our captures always show; rows hidden in
    /// the settings do not.
    var visibleCategories: [CleanupCategory] {
        return SpaceModel.visible(CleanupCategory.all, sizes: sizes, hidden: AppSettings.shared.hiddenCacheRows)
    }

    static func visible(_ categories: [CleanupCategory], sizes: [String: Int64], hidden: Set<String>) -> [CleanupCategory] {
        var list: [CleanupCategory] = []
        for category in categories {
            if hidden.contains(category.id) {
                continue
            }
            let bytes = sizes[category.id] ?? 0
            if bytes > 0 || category.action == .openCaptures {
                list.append(category)
            }
        }
        list.sort { first, second in (sizes[first.id] ?? 0) > (sizes[second.id] ?? 0) }
        return list
    }

    var cleanableBytes: Int64 {
        let hidden = AppSettings.shared.hiddenCacheRows
        var total: Int64 = 0
        for category in CleanupCategory.all where category.action == .deleteContents {
            if hidden.contains(category.id) {
                continue
            }
            total += sizes[category.id] ?? 0
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Disk and categories

    func refreshVolume() {
        if let made = volumeOverride {
            volumeTotal = made.total
            volumeFree = made.free
            return
        }
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
            names.append(check.title)
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

    // MARK: Review lists

    /// The dependency folders found by the last "Find projects".
    private(set) var projectReview: SpaceReview?
    private(set) var isScanningProjects = false
    /// When the last project scan finished.
    private(set) var projectsScannedAt: Date?
    /// Project folders that could not be read in the last scan.
    private(set) var unreadableProjectRoots: [URL] = []
    /// The open review list of each cache category, by category id.
    private(set) var cacheReviews: [String: SpaceReview] = [:]
    @ObservationIgnored private var projectScanStop = DiskScanner.StopFlag()

    /// Looks for dependency folders in the project folders from the settings (the app's, unless a
    /// snapshot or test passes its own).
    func scanProjects(settings given: AppSettings? = nil) async {
        let settings = given ?? AppSettings.shared
        if isScanningProjects {
            return
        }
        isScanningProjects = true
        let stop = DiskScanner.StopFlag()
        projectScanStop = stop
        var roots: [URL] = []
        for path in settings.projectRoots {
            roots.append(home.appendingPathComponent(path))
        }
        let kinds = settings.dependencyKinds
        let searchedHome = home
        // Tests: a made-up home is searched in no time; the wait leaves "Stop" something to stop.
        var waited = 0.0
        while waited < scanStartDelay && !stop.isStopped {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }
        let result = await Task.detached(priority: .userInitiated) { () -> ProjectScanResult in
            return ProjectDependencies.scan(roots: roots, kinds: kinds, maxDepth: 6, isTrackedByGit: SpaceReview.isTrackedByGit, shouldStop: { stop.isStopped }, home: searchedHome)
        }.value
        isScanningProjects = false
        if stop.isStopped {
            return
        }
        projectReview = SpaceReview(projects: result, settings: settings)
        unreadableProjectRoots = result.unreadableRoots
        projectsScannedAt = Date()
        Log.info("space: found \(result.found.count) dependency folders in \(roots.count) project folders")
    }

    func stopProjectScan() {
        projectScanStop.stop()
    }

    #if AUTOMATION
    /// Tests: drops every review list and the last project search, so a made-up home starts and
    /// ends with nothing found.
    func forgetReviewsForTests() {
        projectScanStop.stop()
        projectReview = nil
        projectsScannedAt = nil
        unreadableProjectRoots = []
        cacheReviews = [:]
        openReviewID = nil
    }
    #endif

    /// Lists the items of a cache category for review; the list stays until the category is closed.
    /// nil for a category that is not cleaned by deleting (our captures).
    func openReview(for category: CleanupCategory) async -> SpaceReview? {
        if category.action != .deleteContents {
            return nil
        }
        if let open = cacheReviews[category.id] {
            return open
        }
        let root = home
        let items = await Task.detached(priority: .userInitiated) { () -> [CacheItem] in
            return SpaceReview.cacheItems(of: category, home: root)
        }.value
        let review = SpaceReview(category: category, items: items, settings: AppSettings.shared)
        cacheReviews[category.id] = review
        return review
    }

    func closeReview(for categoryID: String) {
        cacheReviews[categoryID] = nil
    }

    /// Opens a review list in "Clean up"; nil goes back to the categories. The list of a cache
    /// category that is left is closed, so it is listed afresh next time; one still removing stays.
    func showReview(_ id: String?) {
        if let previous = openReviewID, previous != id, let review = cacheReviews[previous], !review.isRemoving {
            closeReview(for: previous)
        }
        openReviewID = id
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
            message = L("space.message.movedToTrash", (path as NSString).lastPathComponent, SpaceModel.format(freed))
            refreshVolume()
        } catch {
            message = L("space.message.trashFailed", error.localizedDescription)
        }
    }
}
