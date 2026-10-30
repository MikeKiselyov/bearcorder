import Foundation

/// Release notes written for people (not commit messages), shown once after an update.
public struct WhatsNewRelease: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        /// SF Symbol name.
        public var symbol: String
        public var title: String
        public var text: String
        /// Keyboard shortcut or where to find it, e.g. "⌥⇧M" or "Toolbox → Regex". Empty for none.
        public var shortcut: String
        /// A picture of the change: a PNG, JPEG or animated GIF in `Sources/Bugbear/Resources/WhatsNew` without the
        /// extension. Empty for none.
        public var image: String

        public init(symbol: String, title: String, text: String, shortcut: String = "", image: String = "") {
            self.symbol = symbol
            self.title = title
            self.text = text
            self.shortcut = shortcut
            self.image = image
        }
    }

    /// Grows by one with every release. Never reuse or reorder.
    public var id: Int
    /// "major.minor.patch", higher than the release before it. Becomes the app's version.
    public var version: String
    public var title: String
    public var items: [Item]

    public init(id: Int, version: String, title: String, items: [Item]) {
        self.id = id
        self.version = version
        self.title = title
        self.items = items
    }
}

public enum WhatsNew {
    /// Where the pictures live in the repository and, copied by scripts/build-app.sh, in the app.
    public static let imageFolder = "Sources/Bugbear/Resources/WhatsNew"

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

    /// The newest release's version, "0.0.0" without releases.
    public static func latestVersion(_ releases: [WhatsNewRelease]) -> String {
        var latestID = 0
        var version = "0.0.0"
        for release in releases where release.id > latestID {
            latestID = release.id
            version = release.version
        }
        return version
    }

    /// A release as Markdown for the GitHub release page.
    public static func markdown(_ release: WhatsNewRelease) -> String {
        var lines: [String] = ["## \(release.title)", ""]
        for item in release.items {
            var line = "- **\(item.title)** - \(item.text)"
            if !item.shortcut.isEmpty {
                line += " (\(item.shortcut))"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Mistakes that would break versions or the update check. Empty when the catalog is fine.
    public static func problems(_ releases: [WhatsNewRelease]) -> [String] {
        var problems: [String] = []
        if releases.isEmpty {
            return ["There are no releases."]
        }
        for (position, release) in releases.enumerated() {
            let expectedID = releases.count - position
            if release.id != expectedID {
                problems.append("Release \"\(release.title)\" has id \(release.id), expected \(expectedID) (newest first, ids 1, 2, 3...).")
            }
            if ReleaseVersion(release.version) == nil {
                problems.append("Release \(release.id) has version \"\(release.version)\", expected major.minor.patch.")
            }
            if release.title.isEmpty || release.items.isEmpty {
                problems.append("Release \(release.id) needs a title and at least one item.")
            }
            if position + 1 < releases.count {
                let older = releases[position + 1]
                if !ReleaseVersion.isNewer(release.version, than: older.version) {
                    problems.append("Release \(release.id) version \(release.version) is not higher than \(older.version).")
                }
            }
        }
        return problems
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

/// A "major.minor.patch" version that compares by numbers, so 0.10.0 is newer than 0.9.0.
public struct ReleaseVersion: Equatable, Comparable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        if parts.count != 3 { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0, !part.hasPrefix("+") else { return nil }
            numbers.append(number)
        }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    public static func < (left: ReleaseVersion, right: ReleaseVersion) -> Bool {
        if left.major != right.major { return left.major < right.major }
        if left.minor != right.minor { return left.minor < right.minor }
        return left.patch < right.patch
    }

    /// False when either text is not a version.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidateVersion = ReleaseVersion(candidate), let currentVersion = ReleaseVersion(current) else { return false }
        return candidateVersion > currentVersion
    }

    /// The top release's version in the source of WhatsNewCatalog.swift, as GitHub serves it.
    public static func latest(inCatalogSource source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"WhatsNewRelease\(id: *[0-9]+, *version: *"([0-9]+\.[0-9]+\.[0-9]+)""#) else { return nil }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, range: range), let versionRange = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[versionRange])
    }
}
