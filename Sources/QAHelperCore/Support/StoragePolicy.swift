import Foundation

/// Which saved captures to delete: older than N days, then the oldest until the total fits.
public enum StoragePolicy {
    public struct Item: Equatable {
        public var id: UUID
        public var createdAt: Date
        public var bytes: Int64

        public init(id: UUID, createdAt: Date, bytes: Int64) {
            self.id = id
            self.createdAt = createdAt
            self.bytes = bytes
        }
    }

    /// `maxAgeDays` 0 and `maxBytes` 0 mean no limit. `protected` items (open in an editor) are kept.
    public static func itemsToDelete(_ items: [Item], now: Date, maxAgeDays: Int, maxBytes: Int64, protected: Set<UUID>) -> [UUID] {
        var doomed: [UUID] = []
        var kept: [Item] = []
        let oldestAllowed = now.addingTimeInterval(-Double(maxAgeDays) * 24 * 3600)
        for item in items {
            if maxAgeDays > 0 && item.createdAt < oldestAllowed && !protected.contains(item.id) {
                doomed.append(item.id)
            } else {
                kept.append(item)
            }
        }
        if maxBytes <= 0 { return doomed }
        var total: Int64 = 0
        for item in kept {
            total += item.bytes
        }
        let oldestFirst = kept.sorted { first, second in first.createdAt < second.createdAt }
        for item in oldestFirst {
            if total <= maxBytes { break }
            if protected.contains(item.id) { continue }
            doomed.append(item.id)
            total -= item.bytes
        }
        return doomed
    }
}
