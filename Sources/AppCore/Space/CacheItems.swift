import Foundation

/// One thing in a cache category that can be ticked and removed: a child folder or file.
public struct CacheItem: Equatable, Sendable {
    public var url: URL
    public var name: String
    public var bytes: Int64
    public var snapshot: FolderSnapshot

    public init(url: URL, name: String, bytes: Int64, snapshot: FolderSnapshot) {
        self.url = url
        self.name = name
        self.bytes = bytes
        self.snapshot = snapshot
    }
}

public enum CacheItems {
    /// Paths below `home` to keep, standardized. A name ending in `*` stands for every existing
    /// entry of its folder that starts with the rest (Google/AndroidStudio* for each version).
    public static func keptPaths(_ patterns: [String], home: URL) -> Set<String> {
        var kept: Set<String> = []
        for pattern in patterns {
            let url = home.appendingPathComponent(pattern).standardizedFileURL
            let name = url.lastPathComponent
            if !name.hasSuffix("*") {
                kept.insert(url.path)
                continue
            }
            let prefix = String(name.dropLast())
            let folder = url.deletingLastPathComponent()
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
                continue
            }
            for entry in entries where entry.hasPrefix(prefix) {
                kept.insert(folder.appendingPathComponent(entry).standardizedFileURL.path)
            }
        }
        return kept
    }

    /// True when the path is kept or holds a kept path: removing it would remove what is kept.
    static func holdsKeptPath(_ path: String, keep: Set<String>) -> Bool {
        for kept in keep {
            if kept == path || kept.hasPrefix(path + "/") {
                return true
            }
        }
        return false
    }

    /// One item per direct child of each folder, biggest first. Left out: paths in `keep`
    /// (standardized, see `keptPaths`) and children that hold one, Apple's `com.apple.*`, links and children that take no space.
    /// `nameFor` gives the name shown for a child.
    public static func children(of folders: [URL], keep: Set<String>, nameFor: (URL) -> String) -> [CacheItem] {
        var items: [CacheItem] = []
        for folder in folders {
            let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey]
            guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: []) else {
                continue
            }
            for child in children {
                // Kept, or holding something kept (Google with Android Studio's caches inside).
                if holdsKeptPath(child.standardizedFileURL.path, keep: keep) {
                    continue
                }
                if child.lastPathComponent.hasPrefix("com.apple.") {
                    continue
                }
                guard let values = try? child.resourceValues(forKeys: Set(keys)) else {
                    continue
                }
                if values.isSymbolicLink == true {
                    continue
                }
                var bytes: Int64 = 0
                if values.isDirectory == true {
                    bytes = FileSizes.folder(child)
                } else {
                    bytes = FileSizes.allocated(child)
                }
                if bytes == 0 {
                    continue
                }
                guard let snapshot = FolderSnapshot.take(of: child, marker: nil, projectRoot: nil, projectChanged: nil) else {
                    continue
                }
                items.append(CacheItem(url: child, name: nameFor(child), bytes: bytes, snapshot: snapshot))
            }
        }
        items.sort { first, second in first.bytes > second.bytes }
        return items
    }
}
