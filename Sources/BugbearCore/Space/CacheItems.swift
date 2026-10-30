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
    /// One item per direct child of each folder, biggest first. Left out: paths in `keep`
    /// (standardized), Apple's `com.apple.*`, links and children that take no space.
    /// `nameFor` gives the name shown for a child.
    public static func children(of folders: [URL], keep: Set<String>, nameFor: (URL) -> String) -> [CacheItem] {
        var items: [CacheItem] = []
        for folder in folders {
            let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey]
            guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: []) else {
                continue
            }
            for child in children {
                if keep.contains(child.standardizedFileURL.path) {
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
