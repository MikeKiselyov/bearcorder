import AppKit
import BugbearCore
import SwiftUI

// MARK: - JSON diff

struct JSONDiffTool: View {
    @Binding var input: String
    @State private var other = ""

    private var result: (changes: [JSONDiff.Change], error: String?) {
        let leftText = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightText = other.trimmingCharacters(in: .whitespacesAndNewlines)
        if leftText.isEmpty || rightText.isEmpty {
            return (changes: [], error: nil)
        }
        let left: JSONValue
        let right: JSONValue
        do {
            left = try JSONParser.parse(leftText)
        } catch {
            return (changes: [], error: "Before: \(error)")
        }
        do {
            right = try JSONParser.parse(rightText)
        } catch {
            return (changes: [], error: "After: \(error)")
        }
        return (changes: JSONDiff.compare(left, right), error: nil)
    }

    var body: some View {
        let current = result
        SplitPanes {
            VSplitView {
                VStack(spacing: 0) {
                    PaneHeader(title: "Before") { pasteButton { text in input = text } }
                    CodeTextView(text: $input)
                }
                VStack(spacing: 0) {
                    PaneHeader(title: "After") { pasteButton { text in other = text } }
                    CodeTextView(text: $other)
                }
            }
        } right: {
            PaneHeader(title: changesTitle(current.changes)) {
                CopyButton(text: report(current.changes), title: "Copy list", primary: false)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = current.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning)
                    } else if current.changes.isEmpty && !input.isEmpty && !other.isEmpty {
                        Label("The documents are the same (key order and 1 vs 1.0 are ignored).", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.success)
                    } else if input.isEmpty || other.isEmpty {
                        Text("Paste two JSON responses to see what changed between them.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(Array(current.changes.enumerated()), id: \.offset) { _, change in
                        changeRow(change)
                    }
                }
                .padding(12)
            }
        }
    }

    private func pasteButton(_ apply: @escaping (String) -> Void) -> some View {
        Button("Paste") { apply(NSPasteboard.general.string(forType: .string) ?? "") }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.link)
            .tip("Replace this side with the JSON on the clipboard")
    }

    private func changesTitle(_ changes: [JSONDiff.Change]) -> String {
        if changes.count == 1 {
            return "1 difference"
        }
        return "\(changes.count) differences"
    }

    private func changeRow(_ change: JSONDiff.Change) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(change.kind.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color(for: change.kind).opacity(0.25))
                    .foregroundStyle(color(for: change.kind))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(change.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }
            if let old = change.old {
                Text("− " + old).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.warning).textSelection(.enabled).lineLimit(4)
            }
            if let new = change.new {
                Text("+ " + new).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.success).textSelection(.enabled).lineLimit(4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func color(for kind: JSONDiff.Kind) -> Color {
        switch kind {
        case .added: return Theme.success
        case .removed: return Theme.warning
        case .changed: return Theme.link
        }
    }

    private func report(_ changes: [JSONDiff.Change]) -> String {
        var lines: [String] = []
        for change in changes {
            var line = "\(change.kind.rawValue) \(change.path)"
            if let old = change.old {
                line += "  was \(old)"
            }
            if let new = change.new {
                line += "  now \(new)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - JSONPath

struct JSONPathTool: View {
    @Binding var input: String
    @State private var expression = "$..id"

    private var result: (matches: [JSONPath.Match], error: String?) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return (matches: [], error: nil)
        }
        let root: JSONValue
        do {
            root = try JSONParser.parse(text)
        } catch {
            return (matches: [], error: "JSON: \(error)")
        }
        do {
            return (matches: try JSONPath.query(expression, in: root), error: nil)
        } catch let problem as JSONPath.ParseError {
            return (matches: [], error: problem.message)
        } catch {
            return (matches: [], error: "\(error)")
        }
    }

    var body: some View {
        let current = result
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("$.items[*].price", text: $expression)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .tip("JSONPath expression to select values from the JSON below, for example $..id")
                ForEach(["$..id", "$.items[*]", "$.items[0]", "$..*"], id: \.self) { example in
                    Button(example) { expression = example }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.link)
                        .tip("Try the example expression \(example)")
                }
            }
            .padding(12)
            .background(Theme.sidebar)
            SplitPanes {
                PaneHeader(title: "JSON") {
                    Button("Paste") { input = NSPasteboard.general.string(forType: .string) ?? input }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.link)
                        .tip("Replace the JSON with the clipboard contents")
                }
                CodeTextView(text: $input)
            } right: {
                PaneHeader(title: current.matches.count == 1 ? "1 match" : "\(current.matches.count) matches") {
                    CopyButton(text: valuesText(current.matches), title: "Copy values", primary: false)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if let error = current.error {
                            Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning)
                        }
                        ForEach(Array(current.matches.prefix(500).enumerated()), id: \.offset) { _, match in
                            ValueRow(label: match.path, value: JSONPrinter().pretty(match.value))
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func valuesText(_ matches: [JSONPath.Match]) -> String {
        var lines: [String] = []
        for match in matches {
            lines.append(JSONPrinter().minified(match.value))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Cron

struct CronTool: View {
    @Binding var input: String

    private let examples = ["*/5 * * * *", "0 9 * * 1-5", "30 2 * * 0", "0 0 1 * *", "@hourly", "0 */6 * * *"]

    var body: some View {
        let expression = input.isEmpty ? "*/15 * * * *" : input
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Expression")
                    TextField("minute hour day month weekday", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15, design: .monospaced))
                        .tip("Cron expression to explain: minute, hour, day of month, month, weekday")
                    HStack(spacing: 10) {
                        ForEach(examples, id: \.self) { example in
                            Button(example) { input = example }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.link)
                                .tip("Try the example expression \(example)")
                        }
                    }
                    Text("minute (0-59) · hour (0-23) · day of month (1-31) · month (1-12 or JAN) · weekday (0-7 or MON, 0 and 7 are Sunday)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                switch Result(catching: { try CronExpression.parse(expression) }) {
                case .success(let cron):
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Meaning")
                        Text(cron.description).font(.system(size: 17, weight: .semibold)).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Next runs")
                        let runs = cron.nextRuns(after: Date(), count: 10)
                        if runs.isEmpty {
                            Text("Never runs (for example 30 February).").font(.system(size: 12)).foregroundStyle(Theme.warning)
                        }
                        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                            HStack {
                                Text(TimeConverter.format(run, pattern: "EEE d MMM yyyy, HH:mm", timeZone: .current))
                                    .font(.system(size: 13, design: .monospaced))
                                Spacer()
                                Text(TimeConverter.format(run, pattern: "HH:mm 'UTC'", timeZone: TimeZone(identifier: "UTC") ?? .current))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Text("Times in your zone (\(TimeZone.current.identifier)); the server may run cron in UTC.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                case .failure(let error):
                    Text((error as? CronExpression.ParseError)?.message ?? "\(error)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - HTTP message

struct HTTPTool: View {
    @Binding var input: String

    var body: some View {
        let message = HTTPMessage.parse(input)
        SplitPanes {
            PaneHeader(title: "Raw request or response") {
                Button("Paste") { input = NSPasteboard.general.string(forType: .string) ?? input }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .tip("Replace the input with the request or response on the clipboard")
            }
            CodeTextView(text: $input)
        } right: {
            PaneHeader(title: summary(message)) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Paste a request or response: from devtools (Copy request headers), Charles, Proxyman or a log.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if !message.query.isEmpty {
                        fields("Query parameters", message.query)
                    }
                    if !message.headers.isEmpty {
                        fields("Headers", message.headers)
                    }
                    if !message.cookies.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Cookies")
                            ForEach(Array(message.cookies.enumerated()), id: \.offset) { _, cookie in
                                ValueRow(label: cookieLabel(cookie), value: cookie.value)
                            }
                        }
                    }
                    if !message.formFields.isEmpty {
                        fields("Form body", message.formFields)
                    }
                    if let pretty = message.prettyBody {
                        bodyBlock("JSON body", pretty, bytes: message.body.utf8.count)
                    } else if !message.body.isEmpty && message.formFields.isEmpty {
                        bodyBlock("Body", message.body, bytes: message.body.utf8.count)
                    }
                }
                .padding(12)
            }
        }
    }

    /// Full body text: ValueRow cuts long values after three lines.
    private func bodyBlock(_ title: String, _ text: String, bytes: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("\(title) · \(bytes) bytes")
                Spacer()
                CopyButton(text: text, title: "Copy", primary: false)
            }
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func summary(_ message: HTTPMessage) -> String {
        switch message.kind {
        case .request: return "\(message.method) \(message.path)"
        case .response: return "Response \(message.statusCode) \(message.reason)"
        case .headers: return "\(message.headers.count) headers"
        }
    }

    private func cookieLabel(_ cookie: HTTPMessage.Cookie) -> String {
        if cookie.attributes.isEmpty {
            return cookie.name
        }
        return "\(cookie.name) · \(cookie.attributes.joined(separator: "; "))"
    }

    private func fields(_ title: String, _ list: [HTTPMessage.Field]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("\(title) · \(list.count)")
            ForEach(Array(list.enumerated()), id: \.offset) { _, field in
                ValueRow(label: field.name, value: field.value)
            }
        }
    }
}

// MARK: - String length

struct LengthTool: View {
    @Binding var input: String
    @State private var length = 256
    @State private var style = LengthString.Style.counter

    private let quickLengths = [10, 50, 100, 255, 256, 1000, 1024, 4096, 65536]

    var body: some View {
        let generated = LengthString.make(length: length, style: style)
        let generatedCounts = LengthString.counts(generated)
        let inputCounts = LengthString.counts(input)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Make a string of exact length")
                    HStack(spacing: 12) {
                        TextField("Length", value: $length, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .tip("Exact length of the string to generate, in characters")
                        Stepper("", value: $length, in: 0...LengthString.maximum).labelsHidden()
                            .tip("Make the string one character longer or shorter")
                        PillPicker(options: LengthString.Style.allCases, selection: $style) { value in value.rawValue }
                            .frame(width: 380)
                            .tip("What to fill the string with: a counterstring shows where a field cuts it, Cyrillic and emoji test byte limits")
                        Spacer()
                        CopyButton(text: generated, title: "Copy", primary: false)
                    }
                    HStack(spacing: 8) {
                        ForEach(quickLengths, id: \.self) { value in
                            Button(String(value)) { length = value }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(length == value ? Theme.text : Theme.link)
                                .tip("Set the length to \(value), a common field limit")
                        }
                        Text("±1 around a limit: 254, 255, 256").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    if style == .counter {
                        Text("Counterstring: every * sits at the position written before it, so where the field cuts the text shows the limit.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(preview(generated))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    countRow(generatedCounts)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Count any text")
                    CodeTextView(text: $input)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    countRow(inputCounts)
                    Text("Backends limit differently: characters (most UIs), UTF-16 units (JavaScript, Java), or UTF-8 bytes (MySQL, many APIs).")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(16)
        }
    }

    private func preview(_ text: String) -> String {
        if text.count > 2000 {
            return String(text.prefix(2000)) + " … (\(text.count) characters, Copy takes all)"
        }
        return text
    }

    private func countRow(_ counts: LengthString.Counts) -> some View {
        HStack(spacing: 6) {
            ValueRow(label: "Characters", value: "\(counts.characters)", mono: true)
            ValueRow(label: "UTF-16 units", value: "\(counts.utf16)", mono: true)
            ValueRow(label: "UTF-8 bytes", value: "\(counts.utf8Bytes)", mono: true)
            ValueRow(label: "Words", value: "\(counts.words)", mono: true)
            ValueRow(label: "Lines", value: "\(counts.lines)", mono: true)
        }
    }
}
