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
        /// The file's inode when it was scanned; 0 when not known.
        public var fileID: UInt64

        public init(path: String, bytes: Int64, fileID: UInt64 = 0) {
            self.path = path
            self.bytes = bytes
            self.fileID = fileID
        }
    }

    /// The inode of the file itself (a link is not followed); nil when it cannot be read.
    public static func fileID(of path: String) -> UInt64? {
        var info = stat()
        if lstat(path, &info) != 0 {
            return nil
        }
        return UInt64(info.st_ino)
    }

    /// Package extensions also recognised by name, should macOS not mark the folder as a package.
    static let packageExtensions: Set<String> = ["app", "photoslibrary", "bundle", "framework", "plugin", "appex", "xcarchive", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band", "pkg", "kext", "utm", "pvm", "vmwarevm", "sparsebundle"]

    /// True when a folder above the file is a package (an app, a Photos library, a bundle): the
    /// file is part of it and is not offered on its own.
    public static func isInsidePackage(_ path: String) -> Bool {
        var folder = URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent()
        while folder.path != "/" {
            if packageExtensions.contains(folder.pathExtension.lowercased()) {
                return true
            }
            let values = try? folder.resourceValues(forKeys: [.isPackageKey])
            if values?.isPackage == true {
                return true
            }
            folder = folder.deletingLastPathComponent().standardizedFileURL
        }
        return false
    }

    /// True when the file at the path is still the one the scan saw: a regular file (not a link)
    /// with the same inode, not inside a package. Only then may "Move to Trash" take it.
    public static func isStillTheSame(_ file: File) -> Bool {
        if file.fileID == 0 {
            return false
        }
        var info = stat()
        if lstat(file.path, &info) != 0 {
            return false
        }
        if (info.st_mode & S_IFMT) != S_IFREG {
            return false
        }
        if UInt64(info.st_ino) != file.fileID {
            return false
        }
        if isInsidePackage(file.path) {
            return false
        }
        return true
    }

    public let limit: Int
    public let minimumBytes: Int64
    /// Biggest first.
    public private(set) var files: [File] = []

    public init(limit: Int, minimumBytes: Int64) {
        self.limit = limit
        self.minimumBytes = minimumBytes
    }

    /// `fileID` is the file's inode at scan time, checked again before it is moved to the Trash.
    public mutating func consider(path: String, bytes: Int64, fileID: UInt64 = 0) {
        if bytes < minimumBytes { return }
        if files.count >= limit, let smallest = files.last, bytes <= smallest.bytes { return }
        var index = files.count
        for (position, file) in files.enumerated() where bytes > file.bytes {
            index = position
            break
        }
        files.insert(File(path: path, bytes: bytes, fileID: fileID), at: index)
        if files.count > limit {
            files.removeLast()
        }
    }
}
