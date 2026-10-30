import Foundation

/// What changed on GitHub since this build, from the "compare" API:
/// GET https://api.github.com/repos/{owner}/{repo}/compare/{built commit}...{branch}
public struct UpdateInfo: Equatable {
    public struct Change: Equatable {
        public var title: String
        public var shortSHA: String
        /// The pull request this change came in with, when it is a merged pull request.
        public var pullRequest: Int?

        public init(title: String, shortSHA: String, pullRequest: Int? = nil) {
            self.title = title
            self.shortSHA = shortSHA
            self.pullRequest = pullRequest
        }

        /// The pull request page, or the commit page for a change pushed without one.
        public func url(repository: String) -> URL? {
            if repository.isEmpty { return nil }
            if let number = pullRequest {
                return URL(string: "https://github.com/\(repository)/pull/\(number)")
            }
            if shortSHA.isEmpty { return nil }
            return URL(string: "https://github.com/\(repository)/commit/\(shortSHA)")
        }
    }

    /// The newest release on GitHub, empty when only commits are known.
    public var version: String
    /// Commits on the branch that this build does not have.
    public var newCommitCount: Int
    /// Newest first: merged pull requests with their titles, or commit titles when the branch
    /// has no pull requests.
    public var changes: [Change]
    /// How many changes there are in all; `changes` holds the newest of them.
    public var changeCount: Int

    public init(version: String = "", newCommitCount: Int, changes: [Change], changeCount: Int? = nil) {
        self.version = version
        self.newCommitCount = newCommitCount
        self.changes = changes
        self.changeCount = changeCount ?? changes.count
    }

    /// Where the release catalog lives in the repository; the update check reads its top version.
    public static let catalogPath = "Sources/AppCore/Support/WhatsNewCatalog.swift"

    public static func catalogURL(repository: String, branch: String) -> URL? {
        if repository.isEmpty || branch.isEmpty { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(repository)/\(branch)/\(catalogPath)")
    }

    /// Updates always come from main: a copy built from a pull request branch would otherwise look
    /// at a branch that is deleted once the pull request is merged (GitHub answers 404).
    public static let updateBranch = "main"

    /// The release catalog an installed copy compares its version with.
    public static func updateCatalogURL(repository: String) -> URL? {
        return catalogURL(repository: repository, branch: updateBranch)
    }

    /// What changed on main since the commit a copy was built from.
    public static func updateCompareURL(repository: String, builtCommit: String) -> URL? {
        return compareURL(repository: repository, commit: builtCommit, branch: updateBranch)
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
        var pullRequests: [Change] = []
        var commitChanges: [Change] = []
        let commits = root["commits"] as? [[String: Any]] ?? []
        for entry in commits.reversed() {
            let sha = String((entry["sha"] as? String ?? "").prefix(7))
            let details = entry["commit"] as? [String: Any] ?? [:]
            let message = details["message"] as? String ?? ""
            if let pullRequest = pullRequestChange(message: message, shortSHA: sha) {
                pullRequests.append(pullRequest)
                continue
            }
            let title = firstLine(of: message)
            // "Merge branch 'main' into feature" only brings a branch up to date.
            if title.hasPrefix("Merge branch ") || title.hasPrefix("Merge remote-tracking branch ") {
                continue
            }
            commitChanges.append(Change(title: title, shortSHA: sha))
        }
        // With pull requests, the other commits are the work inside them: list the pull requests.
        var all = commitChanges
        if !pullRequests.isEmpty {
            all = pullRequests
        }
        var changes: [Change] = []
        for change in all {
            if changes.count >= limit { break }
            changes.append(change)
        }
        return UpdateInfo(newCommitCount: aheadBy, changes: changes, changeCount: all.count)
    }

    /// "Merge pull request #12 from owner/branch" with the pull request title on a later line,
    /// or a squash merge "Title (#12)". Nil for other commits.
    static func pullRequestChange(message: String, shortSHA: String) -> Change? {
        let title = firstLine(of: message)
        let mergePrefix = "Merge pull request #"
        if title.hasPrefix(mergePrefix) {
            let rest = title.dropFirst(mergePrefix.count)
            var digits = ""
            for character in rest {
                if !character.isNumber { break }
                digits.append(character)
            }
            guard let number = Int(digits) else { return nil }
            var pullRequestTitle = ""
            let lines = message.split(separator: "\n", omittingEmptySubsequences: true)
            if lines.count > 1 {
                pullRequestTitle = lines[1].trimmingCharacters(in: .whitespaces)
            }
            if pullRequestTitle.isEmpty {
                pullRequestTitle = "Pull request #\(number)"
            }
            return Change(title: pullRequestTitle, shortSHA: shortSHA, pullRequest: number)
        }
        // Squash merge: "Fix the crop handles (#12)".
        if title.hasSuffix(")"), let open = title.range(of: " (#", options: .backwards) {
            let digits = title[open.upperBound..<title.index(before: title.endIndex)]
            if let number = Int(digits) {
                return Change(title: String(title[..<open.lowerBound]), shortSHA: shortSHA, pullRequest: number)
            }
        }
        return nil
    }

    static func firstLine(of message: String) -> String {
        guard let line = message.split(separator: "\n", maxSplits: 1).first else { return "" }
        return String(line)
    }
}
