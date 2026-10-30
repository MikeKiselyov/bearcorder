import Foundation

/// How much disk space files take (allocated blocks, not the length of their content).
public enum FileSizes {
    private static let sizeKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]

    /// Bytes one regular file takes. Folders, links and unreadable items count as 0.
    public static func allocated(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: sizeKeys), values.isRegularFile == true else { return 0 }
        if let total = values.totalFileAllocatedSize {
            return Int64(total)
        }
        return Int64(values.fileAllocatedSize ?? 0)
    }

    /// Bytes used by everything inside `url`. Unreadable items are skipped.
    public static func folder(_ url: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(sizeKeys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in walker {
            total += allocated(item)
        }
        return total
    }
}
