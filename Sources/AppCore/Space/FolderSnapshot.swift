import Foundation

/// What changed in a folder since it was scanned.
public enum SnapshotChange: Equatable, Sendable {
    case gone, replaced, markerGone, projectChanged
    /// The folder's own modification date differs from the snapshot; callers decide (project folders are skipped, cache items ignore it).
    case modified
}

/// A folder's identity when Space scanned it. Checked again right before the folder is removed.
public struct FolderSnapshot: Equatable, Sendable {
    public var fileID: UInt64
    public var modified: Date
    /// A file that must still exist, such as package.json beside node_modules.
    public var marker: URL?
    public var projectRoot: URL?
    public var projectChanged: Date?
    /// The names directly inside the folder, without Finder's .DS_Store, when they were recorded
    /// (for an item moved to the Trash): a folder whose date moved only because Finder wrote a
    /// .DS_Store into it is still the same.
    public var childNames: [String]?

    public init(fileID: UInt64, modified: Date, marker: URL?, projectRoot: URL?, projectChanged: Date?, childNames: [String]? = nil) {
        self.fileID = fileID
        self.modified = modified
        self.marker = marker
        self.projectRoot = projectRoot
        self.projectChanged = projectChanged
        self.childNames = childNames
    }

    /// The names directly inside a folder, sorted, without .DS_Store; nil when it cannot be read.
    public static func childNames(of folder: URL) -> [String]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return nil
        }
        var kept: [String] = []
        for name in names where name != ".DS_Store" {
            kept.append(name)
        }
        kept.sort()
        return kept
    }

    /// nil when the folder cannot be read.
    public static func take(of folder: URL, marker: URL?, projectRoot: URL?, projectChanged: Date?) -> FolderSnapshot? {
        guard let identity = identity(of: folder) else {
            return nil
        }
        return FolderSnapshot(
            fileID: identity.fileID,
            modified: identity.modified,
            marker: marker,
            projectRoot: projectRoot,
            projectChanged: projectChanged
        )
    }

    /// nil means the folder is still the one that was scanned.
    public func change(now folder: URL, lastChanged: (URL) -> Date) -> SnapshotChange? {
        guard let current = FolderSnapshot.identity(of: folder) else {
            return .gone
        }
        if current.fileID != fileID {
            return .replaced
        }
        if current.modified != modified {
            return .modified
        }
        if let marker = marker, !FileManager.default.fileExists(atPath: marker.path) {
            return .markerGone
        }
        if let projectRoot = projectRoot, let projectChanged = projectChanged {
            if lastChanged(projectRoot) > projectChanged {
                return .projectChanged
            }
        }
        return nil
    }

    /// lstat, so a link is looked at itself and not followed.
    private static func identity(of folder: URL) -> (fileID: UInt64, modified: Date)? {
        var info = stat()
        if lstat(folder.path, &info) != 0 {
            return nil
        }
        let seconds = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        return (UInt64(info.st_ino), Date(timeIntervalSince1970: seconds))
    }
}
