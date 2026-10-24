import Foundation

/// A Markdown bug report: steps built from recorded clicks and keys (no AI), environment and files.
public enum BugReport {
    public enum ActionKind {
        case click
        case key
        case marker
    }

    /// One recorded input, already mapped to the time shown in the report.
    public struct Action {
        public var kind: ActionKind
        /// Seconds into the video, or negative seconds before a screenshot.
        public var time: Double
        /// Key label like "⌘ Enter", or "typing…" for masked plain typing.
        public var label: String
        /// Clicked element, e.g. `"Submit" button`. Empty when unknown.
        public var target: String
        /// App that received the click. Empty when unknown.
        public var app: String

        public init(kind: ActionKind, time: Double, label: String = "", target: String = "", app: String = "") {
            self.kind = kind
            self.time = time
            self.label = label
            self.target = target
            self.app = app
        }
    }

    public static let typingLabel = "typing…"

    public enum Format: String, CaseIterable, Identifiable {
        case markdown = "Markdown"
        /// Jira (Server / Data Center) wiki markup.
        case jira = "Jira wiki"

        public var id: String { rawValue }
    }

    /// One line per step, "[00:04] Click …". Runs of typing merge into one step;
    /// a click right after another on the same target is a double-click.
    public static func stepLines(from actions: [Action]) -> [(time: Double, text: String)] {
        var steps: [(time: Double, text: String, action: Action)] = []
        let sorted = actions.sorted { first, second in first.time < second.time }
        for action in sorted {
            let text = describe(action)
            if let last = steps.last {
                let sameTyping = action.kind == .key && action.label == typingLabel && last.action.kind == .key && last.action.label == typingLabel
                if sameTyping {
                    continue
                }
                let repeatedClick = action.kind == .click && last.action.kind == .click && last.action.target == action.target && last.action.app == action.app && action.time - last.action.time < 0.5
                if repeatedClick {
                    steps[steps.count - 1].text = text.replacingOccurrences(of: "Click", with: "Double-click")
                    continue
                }
            }
            steps.append((time: action.time, text: text, action: action))
        }
        var lines: [(time: Double, text: String)] = []
        for step in steps {
            lines.append((time: step.time, text: step.text))
        }
        return lines
    }

    /// Numbered Markdown steps: "1. [00:04] Click …".
    public static func steps(from actions: [Action]) -> [String] {
        var lines: [String] = []
        for (index, step) in stepLines(from: actions).enumerated() {
            lines.append("\(index + 1). [\(clock(step.time))] \(step.text)")
        }
        return lines
    }

    static func describe(_ action: Action) -> String {
        switch action.kind {
        case .marker:
            return "⚑ Bug moment"
        case .key:
            if action.label == typingLabel {
                return "Type text"
            }
            return "Press \(action.label)"
        case .click:
            var text = "Click"
            if !action.target.isEmpty {
                text += " \(action.target)"
            }
            if !action.app.isEmpty {
                text += " in \(action.app)"
            }
            return text
        }
    }

    /// "00:04", "1:02:05", or "−00:12" for times before a screenshot.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(abs(seconds).rounded(.down))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let rest = whole % 60
        var text = String(format: "%02d:%02d", minutes, rest)
        if hours > 0 {
            text = String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        if seconds < 0 {
            return "−" + text
        }
        return text
    }

    public static func markdown(environment: EnvironmentSnapshot, actions: [Action], files: [String], timeZone zone: TimeZone = .current) -> String {
        return report(environment: environment, actions: actions, files: files, format: .markdown, timeZone: zone)
    }

    public static func report(environment: EnvironmentSnapshot, actions: [Action], files: [String], format: Format, timeZone zone: TimeZone = .current) -> String {
        if format == .jira {
            return jira(environment: environment, actions: actions, files: files, timeZone: zone)
        }
        var lines: [String] = []
        lines.append("## Summary")
        lines.append("")
        lines.append("")
        lines.append("## Steps to reproduce")
        let steps = steps(from: actions)
        if steps.isEmpty {
            lines.append("1. ")
        } else {
            lines.append(contentsOf: steps)
        }
        lines.append("")
        lines.append("## Expected result")
        lines.append("")
        lines.append("")
        lines.append("## Actual result")
        lines.append("")
        lines.append("")
        lines.append("## Environment")
        for row in environment.rows(timeZone: zone) {
            lines.append("- \(row.label): \(row.value)")
        }
        if !files.isEmpty {
            lines.append("")
            lines.append("## Attachments")
            for file in files {
                lines.append("- \(file)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Jira wiki: "h2." headings, "#" numbered steps, "*Label:*" environment, {{monospace}} times and paths.
    static func jira(environment: EnvironmentSnapshot, actions: [Action], files: [String], timeZone zone: TimeZone) -> String {
        var lines: [String] = []
        lines.append("h2. Summary")
        lines.append("")
        lines.append("h2. Steps to reproduce")
        let steps = stepLines(from: actions)
        if steps.isEmpty {
            lines.append("# ")
        }
        for step in steps {
            lines.append("# {{\(clock(step.time))}} \(jiraEscape(step.text))")
        }
        lines.append("")
        lines.append("h2. Expected result")
        lines.append("")
        lines.append("h2. Actual result")
        lines.append("")
        lines.append("h2. Environment")
        for row in environment.rows(timeZone: zone) {
            lines.append("* *\(jiraEscape(row.label)):* \(jiraEscape(row.value))")
        }
        if !files.isEmpty {
            lines.append("")
            lines.append("h2. Attachments")
            for file in files {
                lines.append("* {{\(file)}}")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Brackets and braces would turn into links and macros in Jira.
    static func jiraEscape(_ text: String) -> String {
        var result = ""
        for character in text {
            if character == "[" || character == "]" || character == "{" || character == "}" || character == "|" {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }
}
