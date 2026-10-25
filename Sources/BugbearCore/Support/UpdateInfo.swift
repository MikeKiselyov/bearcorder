import Foundation

/// What changed on GitHub since this build, from the "compare" API:
/// GET https://api.github.com/repos/{owner}/{repo}/compare/{built commit}...{branch}
public struct UpdateInfo: Equatable {
    public struct Change: Equatable {
        public var title: String
        public var shortSHA: String

        public init(title: String, shortSHA: String) {
            self.title = title
            self.shortSHA = shortSHA
        }
    }

    /// The newest release on GitHub, empty when only commits are known.
    public var version: String
    /// Commits on the branch that this build does not have.
    public var newCommitCount: Int
    /// Newest first, first line of each commit message.
    public var changes: [Change]

    public init(version: String = "", newCommitCount: Int, changes: [Change]) {
        self.version = version
        self.newCommitCount = newCommitCount
        self.changes = changes
    }

    /// Where the release catalog lives in the repository; the update check reads its top version.
    public static let catalogPath = "Sources/BugbearCore/Support/WhatsNewCatalog.swift"

    public static func catalogURL(repository: String, branch: String) -> URL? {
        if repository.isEmpty || branch.isEmpty { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(repository)/\(branch)/\(catalogPath)")
    }

    public var isAvailable: Bool {
        return newCommitCount > 0
    }

    public static func compareURL(repository: String, commit: String, branch: String) -> URL? {
        if repository.isEmpty || commit.isEmpty || branch.isEmpty { return nil }
        return URL(string: "https://api.github.com/repos/\(repository)/compare/\(commit)...\(branch)")
    }

    /// Nil when the response is not a compare result (error, rate limit, unknown commit).
    public static func parse(compareJSON data: Data, limit: Int = 15) -> UpdateInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else { return nil }
        guard let aheadBy = root["ahead_by"] as? Int else { return nil }
        var changes: [Change] = []
        let commits = root["commits"] as? [[String: Any]] ?? []
        for entry in commits.reversed() {
            if changes.count >= limit { break }
            let sha = entry["sha"] as? String ?? ""
            let details = entry["commit"] as? [String: Any] ?? [:]
            let message = details["message"] as? String ?? ""
            let title = message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            changes.append(Change(title: title, shortSHA: String(sha.prefix(7))))
        }
        return UpdateInfo(newCommitCount: aheadBy, changes: changes)
    }
}
