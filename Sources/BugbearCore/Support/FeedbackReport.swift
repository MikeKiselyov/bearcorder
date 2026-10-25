import Foundation

/// A problem report or a feature idea for Bugbear itself. The app fills it in and opens GitHub's
/// "new issue" page with the issue form already filled: no token, the person checks the text and
/// presses Submit in their own account. Files cannot travel in that link, so logs go into a zip
/// the person drags into the issue.
public struct FeedbackReport: Equatable {
    public enum Kind: String, CaseIterable {
        case problem
        case idea

        /// The issue form in `.github/ISSUE_TEMPLATE`.
        public var template: String {
            switch self {
            case .problem:
                return "bug_report.yml"
            case .idea:
                return "feature_request.yml"
            }
        }

        public var label: String {
            switch self {
            case .problem:
                return "bug"
            case .idea:
                return "enhancement"
            }
        }
    }

    /// Where reports go, also from builds of a fork: forks have no issue forms and usually no issues.
    public static let defaultRepository = "MikeKiselyov/bugbear-app"
    /// GitHub answers "414 URI Too Long" a little above 8 KB, and a logged-out person is sent through
    /// the login page with the whole link encoded once more, so stay well under it.
    public static let maxURLLength = 5500
    /// GitHub cuts issue titles at 256 characters.
    public static let maxTitleLength = 200

    public var kind: Kind
    public var title: String
    public var details: String
    /// "Name: value" lines: version, macOS, Mac model, permissions and so on.
    public var environment: [EnvironmentSnapshot.Field]
    /// The last lines of Bugbear's own log, oldest first.
    public var logLines: [String]
    /// Why Bugbear crashed and where, from its crash report. Empty for ordinary reports.
    public var crash: String

    public init(kind: Kind, title: String = "", details: String = "", environment: [EnvironmentSnapshot.Field] = [], logLines: [String] = [], crash: String = "") {
        self.kind = kind
        self.title = title
        self.details = details
        self.environment = environment
        self.logLines = logLines
        self.crash = crash
    }

    /// Hides who the person is: the home folder becomes `~` and the user name `<user>`. Both are
    /// matched as whole names, so "/Users/mikey" or "latest" stay as they are for "mike" or "test".
    public static func redact(_ text: String, homePath: String, userName: String) -> String {
        var result = text
        var home = homePath
        while home.hasSuffix("/") {
            home.removeLast()
        }
        if !home.isEmpty {
            let pattern = NSRegularExpression.escapedPattern(for: home) + "(?=/|$|[^A-Za-z0-9._-])"
            result = replace(pattern, in: result, with: "~")
            // file:// links write spaces in the path as %20.
            if let encoded = home.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), encoded != home {
                let encodedPattern = NSRegularExpression.escapedPattern(for: encoded) + "(?=/|$|[^A-Za-z0-9._%-])"
                result = replace(encodedPattern, in: result, with: "~")
            }
        }
        // Short names like "a" would eat ordinary words.
        if userName.count >= 3 {
            // Whole words only, in any script; "self-test" and an earlier "<user>" stay as they are.
            let pattern = "(?<![\\p{L}\\p{N}_<-])" + NSRegularExpression.escapedPattern(for: userName) + "(?![\\p{L}\\p{N}_>-])"
            result = replace(pattern, in: result, with: "<user>")
        }
        return result
    }

    private static func replace(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    public var environmentText: String {
        var lines: [String] = []
        for item in environment {
            lines.append("\(item.name): \(item.value)")
        }
        return lines.joined(separator: "\n")
    }

    public var logText: String {
        return logLines.joined(separator: "\n")
    }

    /// The fields of the issue form, by their ids in the form file.
    public func formFields(logLineCount: Int) -> [(id: String, value: String)] {
        switch kind {
        case .problem:
            var lines: [String] = []
            let start = max(0, logLines.count - logLineCount)
            for index in start..<logLines.count {
                lines.append(logLines[index])
            }
            return [
                (id: "description", value: details),
                (id: "environment", value: environmentText),
                (id: "crash", value: crash),
                (id: "logs", value: lines.joined(separator: "\n")),
            ]
        case .idea:
            return [
                (id: "idea", value: details),
                (id: "environment", value: environmentText),
            ]
        }
    }

    /// The "new issue" page with the form filled in. Keeps as many of the newest log lines as fit,
    /// then shortens the description, then the title.
    public func issueURL(repository: String = FeedbackReport.defaultRepository) -> URL? {
        var target = repository
        if target.isEmpty {
            target = FeedbackReport.defaultRepository
        }
        var shortened = self
        shortened.title = FeedbackReport.shorten(title.trimmingCharacters(in: .whitespacesAndNewlines), to: FeedbackReport.maxTitleLength)
        var logLineCount = logLines.count
        while true {
            guard let url = shortened.buildURL(repository: target, logLineCount: logLineCount) else { return nil }
            if url.absoluteString.count <= FeedbackReport.maxURLLength {
                return url
            }
            if logLineCount > 0 {
                // Drop the oldest lines first, a few at a time.
                logLineCount = max(0, logLineCount - max(1, logLineCount / 5))
            } else if shortened.details.count > 200 {
                shortened.details = FeedbackReport.shorten(shortened.details, to: shortened.details.count * 3 / 4)
            } else if shortened.crash.count > 200 {
                shortened.crash = FeedbackReport.shorten(shortened.crash, to: shortened.crash.count * 3 / 4)
            } else if shortened.title.count > 40 {
                shortened.title = FeedbackReport.shorten(shortened.title, to: 40)
            } else {
                return nil
            }
        }
    }

    public static func shorten(_ text: String, to length: Int) -> String {
        if text.count <= length {
            return text
        }
        return String(text.prefix(max(0, length - 1))) + "…"
    }

    private func buildURL(repository: String, logLineCount: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository)/issues/new"
        // Labels come from the form files: GitHub ignores a labels parameter from people without
        // triage rights.
        var items: [URLQueryItem] = [URLQueryItem(name: "template", value: kind.template)]
        if !title.isEmpty {
            items.append(URLQueryItem(name: "title", value: title))
        }
        for field in formFields(logLineCount: logLineCount) {
            if !field.value.isEmpty {
                items.append(URLQueryItem(name: field.id, value: field.value))
            }
        }
        components.queryItems = items
        // URLComponents leaves "+" and ";" in values as they are; GitHub reads "+" as a space.
        var query = components.percentEncodedQuery ?? ""
        query = query.replacingOccurrences(of: "+", with: "%2B")
        query = query.replacingOccurrences(of: ";", with: "%3B")
        components.percentEncodedQuery = query
        return components.url
    }
}
