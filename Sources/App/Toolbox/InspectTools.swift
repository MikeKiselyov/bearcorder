import AppKit
import AppCore
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
            return (changes: [], error: L("toolbox.diff.error.before", "\(error)"))
        }
        do {
            right = try JSONParser.parse(rightText)
        } catch {
            return (changes: [], error: L("toolbox.diff.error.after", "\(error)"))
        }
        return (changes: JSONDiff.compare(left, right), error: nil)
    }

    var body: some View {
        let current = result
        SplitPanes {
            VSplitView {
                VStack(spacing: 0) {
                    PaneHeader(title: L("toolbox.diff.before")) { pasteButton(L("toolbox.diff.pasteBefore")) { text in input = text } }
                    CodeTextView(text: $input, label: L("toolbox.diff.before"))
                }
                VStack(spacing: 0) {
                    PaneHeader(title: L("toolbox.diff.after")) { pasteButton(L("toolbox.diff.pasteAfter")) { text in other = text } }
                    CodeTextView(text: $other, label: L("toolbox.diff.after"))
                }
            }
        } right: {
            PaneHeader(title: changesTitle(current.changes)) {
                CopyButton(text: report(current.changes), title: L("toolbox.diff.copyList"), primary: false)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = current.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning)
                    } else if current.changes.isEmpty && !input.isEmpty && !other.isEmpty {
                        Label(L("toolbox.diff.same"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.success)
                    } else if input.isEmpty || other.isEmpty {
                        Text(L("toolbox.diff.empty"))
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

    /// `name`: what VoiceOver (and tests) call the button, e.g. "Paste before".
    private func pasteButton(_ name: String, _ apply: @escaping (String) -> Void) -> some View {
        Button(L("toolbox.button.paste")) { apply(NSPasteboard.general.string(forType: .string) ?? "") }
            .accessibilityLabel(name)
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.link)
            .tip(L("toolbox.diff.paste.tip"))
    }

    private func changesTitle(_ changes: [JSONDiff.Change]) -> String {
        return L("toolbox.diff.count", changes.count)
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
                    .tip(L("toolbox.jsonPath.expression.tip"))
                ForEach(["$..id", "$.items[*]", "$.items[0]", "$..*"], id: \.self) { example in
                    Button(example) { expression = example }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.link)
                        .tip(L("toolbox.example.tip", example))
                }
            }
            .padding(12)
            .background(Theme.sidebar)
            SplitPanes {
                PaneHeader(title: "JSON") {
                    Button(L("toolbox.button.paste")) { input = NSPasteboard.general.string(forType: .string) ?? input }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.link)
                        .tip(L("toolbox.jsonPath.paste.tip"))
                }
                CodeTextView(text: $input)
            } right: {
                PaneHeader(title: L("toolbox.matches", current.matches.count)) {
                    CopyButton(text: valuesText(current.matches), title: L("toolbox.jsonPath.copyValues"), primary: false)
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
                    SectionLabel(L("toolbox.cron.expression"))
                    TextField(L("toolbox.cron.placeholder"), text: $input)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15, design: .monospaced))
                        .tip(L("toolbox.cron.expression.tip"))
                    HStack(spacing: 10) {
                        ForEach(examples, id: \.self) { example in
                            Button(example) { input = example }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.link)
                                .tip(L("toolbox.example.tip", example))
                        }
                    }
                    Text(L("toolbox.cron.fields"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                switch Result(catching: { try CronExpression.parse(expression) }) {
                case .success(let cron):
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(L("toolbox.cron.meaning"))
                        Text(cron.description).font(.system(size: 17, weight: .semibold)).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(L("toolbox.cron.nextRuns"))
                        let runs = cron.nextRuns(after: Date(), count: 10)
                        if runs.isEmpty {
                            Text(L("toolbox.cron.never")).font(.system(size: 12)).foregroundStyle(Theme.warning)
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
                        Text(L("toolbox.cron.zoneNote", TimeZone.current.identifier))
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
            PaneHeader(title: L("toolbox.http.raw")) {
                Button(L("toolbox.button.paste")) { input = NSPasteboard.general.string(forType: .string) ?? input }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .tip(L("toolbox.http.paste.tip"))
            }
            CodeTextView(text: $input)
        } right: {
            PaneHeader(title: summary(message)) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L("toolbox.http.empty"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if !message.query.isEmpty {
                        fields(L("toolbox.http.query"), message.query)
                    }
                    if !message.headers.isEmpty {
                        fields(L("toolbox.http.headers"), message.headers)
                    }
                    if !message.cookies.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(L("toolbox.http.cookies"))
                            ForEach(Array(message.cookies.enumerated()), id: \.offset) { _, cookie in
                                ValueRow(label: cookieLabel(cookie), value: cookie.value)
                            }
                        }
                    }
                    if !message.formFields.isEmpty {
                        fields(L("toolbox.http.formBody"), message.formFields)
                    }
                    if let pretty = message.prettyBody {
                        bodyBlock(L("toolbox.http.jsonBody"), pretty, bytes: message.body.utf8.count)
                    } else if !message.body.isEmpty && message.formFields.isEmpty {
                        bodyBlock(L("toolbox.http.body"), message.body, bytes: message.body.utf8.count)
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
                SectionLabel(L("toolbox.http.bodyTitle", title, bytes))
                Spacer()
                CopyButton(text: text, title: L("toolbox.button.copy"), primary: false, name: L("toolbox.copy.named", title.lowercased()))
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
        case .response: return L("toolbox.http.response", message.statusCode, message.reason)
        case .headers: return L("toolbox.http.headerCount", message.headers.count)
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
                    SectionLabel(L("toolbox.length.make"))
                    HStack(spacing: 12) {
                        TextField(L("toolbox.length.length"), value: $length, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .tip(L("toolbox.length.length.tip"))
                        Stepper("", value: $length, in: 0...LengthString.maximum).labelsHidden()
                            .accessibilityLabel(L("toolbox.length.change"))
                            .tip(L("toolbox.length.change.tip"))
                        PillPicker(options: LengthString.Style.allCases, selection: $style) { value in styleTitle(value) }
                            .frame(width: 380)
                            .tip(L("toolbox.length.style.tip"))
                        Spacer()
                        CopyButton(text: generated, title: L("toolbox.button.copy"), primary: false, name: L("toolbox.length.copyString"))
                    }
                    HStack(spacing: 8) {
                        ForEach(quickLengths, id: \.self) { value in
                            Button(String(value)) { length = value }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(length == value ? Theme.text : Theme.link)
                                .tip(L("toolbox.length.quick.tip", value))
                        }
                        Text(L("toolbox.length.aroundLimit")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    if style == .counter {
                        Text(L("toolbox.length.counterNote"))
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
                    SectionLabel(L("toolbox.length.count"))
                    CodeTextView(text: $input)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    countRow(inputCounts)
                    Text(L("toolbox.length.backends"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(16)
        }
    }

    private func preview(_ text: String) -> String {
        if text.count > 2000 {
            return String(text.prefix(2000)) + " " + L("toolbox.length.previewCut", text.count)
        }
        return text
    }

    private func styleTitle(_ style: LengthString.Style) -> String {
        switch style {
        case .counter: return L("toolbox.length.style.counter")
        case .cyrillic: return L("toolbox.length.style.cyrillic")
        case .emoji: return L("toolbox.length.style.emoji")
        default: return style.rawValue
        }
    }

    private func countRow(_ counts: LengthString.Counts) -> some View {
        HStack(spacing: 6) {
            ValueRow(label: L("toolbox.length.characters"), value: "\(counts.characters)", mono: true)
            ValueRow(label: L("toolbox.length.utf16"), value: "\(counts.utf16)", mono: true)
            ValueRow(label: L("toolbox.length.utf8"), value: "\(counts.utf8Bytes)", mono: true)
            ValueRow(label: L("toolbox.length.words"), value: "\(counts.words)", mono: true)
            ValueRow(label: L("toolbox.length.lines"), value: "\(counts.lines)", mono: true)
        }
    }
}
