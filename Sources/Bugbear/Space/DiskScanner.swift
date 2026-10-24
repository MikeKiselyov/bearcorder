import BugbearCore
import Foundation

/// Measures and cleans folders, and scans the home folder for what takes space. Runs off the main
/// thread; folders macOS does not let us read are skipped quietly.
enum DiskScanner {
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

    static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: sizeKeys), values.isRegularFile == true else { return 0 }
        if let total = values.totalFileAllocatedSize {
            return Int64(total)
        }
        return Int64(values.fileAllocatedSize ?? 0)
    }

    /// Bytes used by everything inside `folder`, leaving out the `excluded` paths.
    static func size(of folder: URL, excluding excluded: Set<String> = []) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(sizeKeys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            if excluded.contains(url.standardizedFileURL.path) || isAppleFolder(url) {
                walker.skipDescendants()
                continue
            }
            total += allocatedSize(of: url)
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

    /// Deletes what is inside the category's folders (the folders themselves stay). Items macOS
    /// protects are left as they are. Returns the bytes freed.
    static func clean(_ category: CleanupCategory, home: URL) -> Int64 {
        let before = size(of: category, home: home)
        let excluded = excludedPaths(of: category, home: home)
        let files = FileManager.default
        for folder in category.folders {
            let url = home.appendingPathComponent(folder)
            guard let items = try? files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) else { continue }
            for item in items where !excluded.contains(item.standardizedFileURL.path) && !isAppleFolder(item) {
                try? files.removeItem(at: item)
            }
        }
        let after = size(of: category, home: home)
        return max(0, before - after)
    }

    private static func excludedPaths(of category: CleanupCategory, home: URL) -> Set<String> {
        var excluded: Set<String> = []
        for path in category.keep {
            excluded.insert(home.appendingPathComponent(path).standardizedFileURL.path)
        }
        return excluded
    }

    /// Walks `root` and returns folder sizes a few levels deep plus the biggest files.
    /// `progress` is called now and then from the scanning thread.
    static func scan(root: URL, skip: [String], progress: @escaping (Progress) -> Void) -> ScanResult? {
        let started = Date()
        let rootPath = root.standardizedFileURL.path
        let libraryPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").standardizedFileURL.path
        var skipped: Set<String> = []
        for path in skip {
            skipped.insert(root.appendingPathComponent(path).standardizedFileURL.path)
        }
        let tree = DiskTree(rootName: root.lastPathComponent)
        var top = TopFiles(limit: 100, minimumBytes: 50_000_000)
        var state = Progress()
        var lastReport = Date()
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(sizeKeys), options: [], errorHandler: { _, _ in true }) else { return nil }
        for case let url as URL in walker {
            if Task.isCancelled { return nil }
            let path = url.standardizedFileURL.path
            if skipped.contains(path) || isAppleFolder(url) {
                walker.skipDescendants()
                continue
            }
            let isInLibrary = url.deletingLastPathComponent().standardizedFileURL.path == libraryPath
            if isInLibrary && !scannedInLibrary.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            let bytes = allocatedSize(of: url)
            if bytes == 0 { continue }
            let relative = String(path.dropFirst(rootPath.count + 1))
            var components: [String] = []
            for part in relative.split(separator: "/") {
                components.append(String(part))
            }
            tree.addFile(components: components, bytes: bytes)
            top.consider(path: path, bytes: bytes)
            state.files += 1
            state.bytes += bytes
            if Date().timeIntervalSince(lastReport) > 0.25 {
                lastReport = Date()
                state.folder = components.first ?? ""
                progress(state)
            }
        }
        return ScanResult(tree: tree, topFiles: top.files, seconds: Date().timeIntervalSince(started))
    }
}
