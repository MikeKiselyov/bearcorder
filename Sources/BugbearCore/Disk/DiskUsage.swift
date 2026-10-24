import Foundation

/// Folder sizes from a disk scan, kept as a tree a few levels deep. Files deeper than `maxDepth`
/// count toward their ancestor at that depth, so the tree stays small however big the disk is.
public final class DiskTree {
    public final class Node {
        public let name: String
        public private(set) var bytes: Int64 = 0
        public private(set) var fileCount = 0
        fileprivate var childrenByName: [String: Node] = [:]

        init(name: String) {
            self.name = name
        }

        /// Biggest first.
        public var children: [Node] {
            var list = Array(childrenByName.values)
            list.sort { first, second in
                if first.bytes != second.bytes { return first.bytes > second.bytes }
                return first.name < second.name
            }
            return list
        }

        public func child(named name: String) -> Node? {
            return childrenByName[name]
        }

        fileprivate func add(_ size: Int64) {
            bytes += size
            fileCount += 1
        }
    }

    public let root: Node
    public let maxDepth: Int

    public init(rootName: String, maxDepth: Int = 6) {
        root = Node(name: rootName)
        self.maxDepth = maxDepth
    }

    /// Adds a file by its path components below the root, e.g. ["Library", "Caches", "x.db"].
    public func addFile(components: [String], bytes: Int64) {
        root.add(bytes)
        var node = root
        // The last component is the file itself; only folders become nodes.
        let folders = components.dropLast()
        var depth = 0
        for name in folders {
            if depth >= maxDepth { break }
            if let existing = node.childrenByName[name] {
                node = existing
            } else {
                let created = Node(name: name)
                node.childrenByName[name] = created
                node = created
            }
            node.add(bytes)
            depth += 1
        }
    }

    /// The node at a path below the root, or nil if the scan never saw it.
    public func node(at components: [String]) -> Node? {
        var node = root
        for name in components {
            guard let next = node.childrenByName[name] else { return nil }
            node = next
        }
        return node
    }
}

/// The biggest files seen in a scan. Keeps at most `limit`, ignoring anything under `minimumBytes`.
public struct TopFiles {
    public struct File: Equatable {
        public var path: String
        public var bytes: Int64

        public init(path: String, bytes: Int64) {
            self.path = path
            self.bytes = bytes
        }
    }

    public let limit: Int
    public let minimumBytes: Int64
    /// Biggest first.
    public private(set) var files: [File] = []

    public init(limit: Int, minimumBytes: Int64) {
        self.limit = limit
        self.minimumBytes = minimumBytes
    }

    public mutating func consider(path: String, bytes: Int64) {
        if bytes < minimumBytes { return }
        if files.count >= limit, let smallest = files.last, bytes <= smallest.bytes { return }
        var index = files.count
        for (position, file) in files.enumerated() where bytes > file.bytes {
            index = position
            break
        }
        files.insert(File(path: path, bytes: bytes), at: index)
        if files.count > limit {
            files.removeLast()
        }
    }
}
