import BugbearCore
import Foundation

/// Measures and cleans folders, and scans the home folder for what takes space. Runs off the main
/// thread; folders macOS does not let us read are skipped quietly.
enum DiskScanner {
    /// Set from the main thread when the person presses Stop; the walk checks it between files.
    /// (A detached task does not see its parent's cancellation, so a flag is needed.)
    final class StopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false

        var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
        }
    }

    struct Progress {
        var files = 0
        var bytes: Int64 = 0
        var folder = ""
    }

    struct ScanResult {
        var tree: DiskTree
        var topFiles: [TopFiles.File]
        var seconds: Double
    }

    /// Folders the scan does not open: other apps' sandboxes, personal data macOS guards with a
    /// permission prompt (Photos, Music, Contacts, Calendars, Reminders, iCloud Drive, Mail, Messages,
    /// Safari), and the Trash.
    static let skippedInScan = [
        ".Trash", "Pictures/Photos Library.photoslibrary", "Music/Music",
        "Library/Application Support/AddressBook", "Library/Application Support/Music",
        "Library/Application Support/CallHistoryDB", "Library/Application Support/CallHistoryTransactions",
        "Library/Application Support/Knowledge", "Library/Application Support/iLifeMediaBrowser",
        "Library/Application Support/FileProvider",
    ]

    /// Inside ~/Library only these folders are scanned. The rest is macOS's own data, and much of it
    /// is guarded: opening it makes macOS ask about Music, Contacts, Calendars and more.
    static let scannedInLibrary: Set<String> = ["Application Support", "Caches", "Developer", "Logs", "pnpm"]

    /// Apple's own folders in Library (com.apple.*) are left alone: some are protected and opening
    /// them makes macOS ask for Music, Photos or other permissions, and the rest are system data.
    static func isAppleFolder(_ url: URL) -> Bool {
        return url.lastPathComponent.hasPrefix("com.apple.")
    }

    private static let sizeKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]

    /// Bytes used by everything inside `folder`, leaving out the `excluded` paths.
    static func size(of folder: URL, excluding excluded: Set<String> = []) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(sizeKeys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            if excluded.contains(url.standardizedFileURL.path) || isAppleFolder(url) {
                walker.skipDescendants()
                continue
            }
            total += FileSizes.allocated(url)
        }
        return total
    }

    /// Bytes a category uses below `home`.
    static func size(of category: CleanupCategory, home: URL) -> Int64 {
        let excluded = excludedPaths(of: category, home: home)
        var total: Int64 = 0
        for folder in category.folders {
            total += size(of: home.appendingPathComponent(folder), excluding: excluded)
        }
        return total
    }

    private static func excludedPaths(of category: CleanupCategory, home: URL) -> Set<String> {
        var excluded: Set<String> = []
        for path in category.keep {
            excluded.insert(home.appendingPathComponent(path).standardizedFileURL.path)
        }
        return excluded
    }

    /// A folder to scan, shown in the tree under `name` ("Home", "Applications").
    struct Root {
        var name: String
        var url: URL
        /// Paths below `url` left out.
        var skip: [String]
    }

    /// Walks the roots and returns folder sizes a few levels deep, under one "This Mac" node, plus
    /// the biggest files. `includeAppData` also opens other apps' private data in ~/Library
    /// (Containers, Group Containers), which macOS asks about once.
    /// `progress` is called now and then from the scanning thread.
    static func scan(roots: [Root], includeAppData: Bool, stop: StopFlag, progress: @escaping (Progress) -> Void) -> ScanResult? {
        let started = Date()
        let libraryPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").standardizedFileURL.path
        var allowedInLibrary = scannedInLibrary
        if includeAppData {
            allowedInLibrary.insert("Containers")
            allowedInLibrary.insert("Group Containers")
        }
        let tree = DiskTree(rootName: "This Mac", maxDepth: 7)
        var top = TopFiles(limit: 100, minimumBytes: 50_000_000)
        var state = Progress()
        var lastReport = Date()
        for root in roots {
            let rootPath = root.url.standardizedFileURL.path
            var skipped: Set<String> = []
            for path in root.skip {
                skipped.insert(root.url.appendingPathComponent(path).standardizedFileURL.path)
            }
            guard let walker = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: Array(sizeKeys), options: [], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in walker {
                if stop.isStopped { return nil }
                let path = url.standardizedFileURL.path
                if skipped.contains(path) || isAppleFolder(url) {
                    walker.skipDescendants()
                    continue
                }
                let isInLibrary = url.deletingLastPathComponent().standardizedFileURL.path == libraryPath
                if isInLibrary && !allowedInLibrary.contains(url.lastPathComponent) {
                    walker.skipDescendants()
                    continue
                }
                let bytes = FileSizes.allocated(url)
                if bytes == 0 { continue }
                let relative = String(path.dropFirst(rootPath.count + 1))
                var components: [String] = [root.name]
                for part in relative.split(separator: "/") {
                    components.append(String(part))
                }
                tree.addFile(components: components, bytes: bytes)
                top.consider(path: path, bytes: bytes)
                state.files += 1
                state.bytes += bytes
                if Date().timeIntervalSince(lastReport) > 0.25 {
                    lastReport = Date()
                    state.folder = root.name + "/" + (components.count > 2 ? components[1] : "")
                    progress(state)
                }
            }
        }
        return ScanResult(tree: tree, topFiles: top.files, seconds: Date().timeIntervalSince(started))
    }
}
