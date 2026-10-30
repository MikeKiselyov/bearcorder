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
        /// Typing: what the field held when the typing stopped. Empty unless the person turned on
        /// typed text in steps; never for password fields.
        public var text: String
        /// The web page the action happened on, when it was in a browser. Empty otherwise.
        public var url: String

        public init(kind: ActionKind, time: Double, label: String = "", target: String = "", app: String = "", text: String = "", url: String = "") {
            self.kind = kind
            self.time = time
            self.label = label
            self.target = target
            self.app = app
            self.text = text
            self.url = url
        }
    }

    public static let typingLabel = "typing…"

    public enum Format: String, CaseIterable, Identifiable {
        case markdown = "Markdown"
        /// Jira (Server / Data Center) wiki markup.
        case jira = "Jira wiki"

        public var id: String { rawValue }
    }

    /// One line per step, "[00:04] Click …". Runs of typing in one field merge into one step that
    /// shows the newest text; a click right after another on the same target is a double-click;
    /// a new web page adds an "Open …" step before the first action on it.
    /// Keys that edit the text being typed.
    static let typingEditKeys: Set<String> = ["Space", "Delete", "⌥ Delete", "⌃ Delete", "Fwd Delete"]

    public static func stepLines(from actions: [Action]) -> [(time: Double, text: String)] {
        var steps: [(time: Double, text: String, action: Action)] = []
        let sorted = actions.sorted { first, second in first.time < second.time }
        var currentPage = ""
        for action in sorted {
            let page = pageName(action.url)
            if !page.isEmpty && page != currentPage {
                currentPage = page
                let opened = Action(kind: .marker, time: action.time, url: action.url)
                steps.append((time: action.time, text: "Open \(page)", action: opened))
            }
            let text = describe(action)
            if let last = steps.last {
                let sameTyping = action.kind == .key && action.label == typingLabel && last.action.kind == .key && last.action.label == typingLabel && last.action.target == action.target
                if sameTyping {
                    if !action.text.isEmpty {
                        steps[steps.count - 1].text = text
                        steps[steps.count - 1].action = action
                    }
                    continue
                }
                // Space and Delete while typing are part of the typing, not steps of their own:
                // "Type text, Press Space, Type text" became three steps for one field.
                if last.action.kind == .key && last.action.label == typingLabel && action.kind == .key && typingEditKeys.contains(action.label) {
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

    /// Numbered Markdown steps: "1. Click …". No times: a ticket reader repeats the steps, the
    /// seconds into the clip only got in the way.
    public static func steps(from actions: [Action]) -> [String] {
        var lines: [String] = []
        for (index, step) in stepLines(from: actions).enumerated() {
            lines.append("\(index + 1). \(step.text)")
        }
        return lines
    }

    static func describe(_ action: Action) -> String {
        switch action.kind {
        case .marker:
            return "⚑ Bug moment"
        case .key:
            if action.label == typingLabel {
                var text = "Type text"
                if !action.text.isEmpty {
                    text = "Type \"\(shortText(action.text))\""
                }
                if !action.target.isEmpty {
                    text += " in \(action.target)"
                }
                return text
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

    /// Longest typed text shown in a step.
    static let maxTextLength = 80

    /// Typed text on one line, cut to `maxTextLength`.
    static func shortText(_ text: String) -> String {
        var line = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        line = line.trimmingCharacters(in: .whitespaces)
        if line.count > maxTextLength {
            return String(line.prefix(maxTextLength - 1)) + "…"
        }
        return line
    }

    /// "stage.myapp.com/checkout" for "https://stage.myapp.com/checkout?token=…#top". The query is
    /// left out: it can hold tokens, codes or an email, and changes without a new page.
    static func pageName(_ url: String) -> String {
        var name = url
        if let cut = name.firstIndex(where: { character in character == "?" || character == "#" }) {
            name = String(name[..<cut])
        }
        for scheme in ["https://", "http://"] where name.hasPrefix(scheme) {
            name = String(name.dropFirst(scheme.count))
        }
        if name.hasSuffix("/") {
            name.removeLast()
        }
        if name.count > 120 {
            name = String(name.prefix(119)) + "…"
        }
        return name
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

    public static func markdown(environment: EnvironmentSnapshot, actions: [Action], timeZone zone: TimeZone = .current) -> String {
        return report(environment: environment, actions: actions, format: .markdown, timeZone: zone)
    }

    /// The ticket body: steps, expected and actual result, environment. No Summary (the ticket has
    /// a title of its own) and no attachments (local file paths mean nothing to whoever reads it).
    public static func report(environment: EnvironmentSnapshot, actions: [Action], format: Format, timeZone zone: TimeZone = .current) -> String {
        if format == .jira {
            return jira(environment: environment, actions: actions, timeZone: zone)
        }
        var lines: [String] = []
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
        return lines.joined(separator: "\n")
    }

    /// Jira wiki: "h2." headings, "#" numbered steps, "*Label:*" environment.
    static func jira(environment: EnvironmentSnapshot, actions: [Action], timeZone zone: TimeZone) -> String {
        var lines: [String] = []
        lines.append("h2. Steps to reproduce")
        let steps = stepLines(from: actions)
        if steps.isEmpty {
            lines.append("# ")
        }
        for step in steps {
            lines.append("# \(jiraEscape(step.text, textMarkup: true))")
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
        return lines.joined(separator: "\n")
    }

    /// Brackets and braces would turn into links and macros in Jira.
    /// Brackets, braces and pipes are links, macros and tables in Jira. With `textMarkup`, also
    /// * _ + ^ ~ (bold, italic, underline, super/subscript around words), which typed text in steps
    /// often has; environment values like URLs keep them, or their links would break.
    static func jiraEscape(_ text: String, textMarkup: Bool = false) -> String {
        var markup: Set<Character> = ["[", "]", "{", "}", "|"]
        if textMarkup {
            for character in ["*", "_", "+", "^", "~"] as [Character] {
                markup.insert(character)
            }
        }
        var result = ""
        for character in text {
            if markup.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }
}
