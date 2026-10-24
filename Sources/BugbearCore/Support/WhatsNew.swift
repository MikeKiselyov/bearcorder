import Foundation

/// Release notes written for people (not commit messages), shown once after an update.
public struct WhatsNewRelease: Equatable {
    public struct Item: Equatable {
        /// SF Symbol name.
        public var symbol: String
        public var title: String
        public var text: String
        /// Keyboard shortcut or where to find it, e.g. "⌥⇧M" or "Toolbox → Regex". Empty for none.
        public var shortcut: String

        public init(symbol: String, title: String, text: String, shortcut: String = "") {
            self.symbol = symbol
            self.title = title
            self.text = text
            self.shortcut = shortcut
        }
    }

    /// Grows by one with every release that has notes. Never reuse or reorder.
    public var id: Int
    public var title: String
    public var items: [Item]

    public init(id: Int, title: String, items: [Item]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public enum WhatsNew {
    /// Releases the user has not seen yet, newest first.
    public static func unseen(_ releases: [WhatsNewRelease], lastSeenID: Int) -> [WhatsNewRelease] {
        var result: [WhatsNewRelease] = []
        for release in releases where release.id > lastSeenID {
            result.append(release)
        }
        result.sort { first, second in first.id > second.id }
        return result
    }

    public static func latestID(_ releases: [WhatsNewRelease]) -> Int {
        var latest = 0
        for release in releases where release.id > latest {
            latest = release.id
        }
        return latest
    }

    /// Show after an update from the app (there are commits to list) or when there are unseen notes.
    /// A plain rebuild with nothing new stays quiet.
    public static func shouldShow(unseenReleases: [WhatsNewRelease], updatedFromCommit: String, changes: [String]) -> Bool {
        if !unseenReleases.isEmpty {
            return true
        }
        return !updatedFromCommit.isEmpty && !changes.isEmpty
    }
}
