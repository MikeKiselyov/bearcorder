import QAHelperCore
import SwiftUI

/// JSON / XML / YAML / HTML / SQL / GraphQL formatter with live output.
struct FormatterTool: View {
    let kind: FormatterKind
    @Binding var input: String

    @State private var mode: FormatMode = .format
    @State private var indentWidth = 2
    @State private var useTabs = false
    @State private var sortKeys = false
    @State private var unescape = false
    @State private var convertTarget: DataFormat = .yaml

    private var options: FormatOptions {
        var value = FormatOptions()
        value.indentWidth = indentWidth
        value.useTabs = useTabs
        value.sortKeys = sortKeys
        value.unescapeStrings = unescape
        value.mode = mode
        return value
    }

    private var result: FormatResult {
        return Formatters.format(input, kind: kind, options: options)
    }

    var body: some View {
        let current = result
        VStack(spacing: 0) {
            optionsBar
            Divider().overlay(Theme.border)
            SplitPanes {
                PaneHeader(title: "Input") {
                    Text("Paste ⌘V").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                CodeTextView(text: $input)
            } right: {
                PaneHeader(title: "Output") {
                    if !input.isEmpty {
                        Text(current.isValid ? statusTitle : "Invalid")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(current.isValid ? Theme.success : Theme.accentSoft)
                    }
                }
                if current.isValid {
                    CodeTextView(text: .constant(current.output), isEditable: false, highlight: highlighter)
                } else {
                    errorView(current.message)
                }
            }
            ToolFooter {
                Text(footerText(current)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer()
                if kind == .json && current.isValid && !input.isEmpty {
                    Menu {
                        ForEach([DataFormat.yaml, .xml, .csv]) { format in
                            Button("Copy as \(format.rawValue)") {
                                if let converted = try? DataConverter.convert(input, from: .json, to: format) {
                                    copyToClipboard(converted)
                                }
                            }
                        }
                    } label: {
                        Text("Copy as…")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                CopyButton(text: current.isValid ? current.output : "")
            }
        }
    }

    private var statusTitle: String {
        switch kind {
        case .json: return "Valid JSON"
        case .xml: return "Valid XML"
        case .yaml: return "Valid YAML"
        case .html: return "Parsed HTML"
        case .sql: return "SQL"
        case .graphql: return "GraphQL"
        }
    }

    private var highlighter: ((String) -> NSAttributedString)? {
        switch kind {
        case .json: return SyntaxHighlighter.json
        case .xml, .html: return SyntaxHighlighter.markup
        default: return nil
        }
    }

    private func footerText(_ current: FormatResult) -> String {
        if input.isEmpty { return "Paste or type on the left" }
        let inputBytes = input.utf8.count
        let outputBytes = current.output.utf8.count
        var text = current.message
        if current.isValid {
            text += " · \(inputBytes) B → \(outputBytes) B"
        }
        return text
    }

    private var optionsBar: some View {
        HStack(spacing: 14) {
            PillPicker(options: FormatMode.allCases, selection: $mode) { value in value.rawValue }
                .frame(width: 170)
            Picker("Indent", selection: Binding(get: { useTabs ? 0 : indentWidth }, set: { value in
                if value == 0 {
                    useTabs = true
                } else {
                    useTabs = false
                    indentWidth = value
                }
            })) {
                Text("2 spaces").tag(2)
                Text("4 spaces").tag(4)
                Text("Tabs").tag(0)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(mode == .minify)
            if kind == .json || kind == .yaml {
                Toggle("Sort keys", isOn: $sortKeys).toggleStyle(.checkbox)
            }
            if kind == .json {
                Toggle("Unescape nested JSON strings", isOn: $unescape).toggleStyle(.checkbox)
            }
            Spacer()
            Button("Clear") { input = "" }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.link)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.accentSoft)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.well)
    }
}

/// JSON / YAML / XML / CSV conversion.
struct DataConvertTool: View {
    @Binding var input: String
    @State private var source: DataFormat = .json
    @State private var target: DataFormat = .yaml

    var body: some View {
        let output = convert()
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PillPicker(options: DataFormat.allCases, selection: $source) { value in value.rawValue }
                    .frame(width: 240)
                Button {
                    let previous = source
                    source = target
                    target = previous
                    if case .success(let text) = output {
                        input = text
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.plain)
                .help("Swap and use the output as input")
                PillPicker(options: DataFormat.allCases, selection: $target) { value in value.rawValue }
                    .frame(width: 240)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider().overlay(Theme.border)
            SplitPanes {
                PaneHeader(title: "\(source.rawValue) input") { EmptyView() }
                CodeTextView(text: $input)
            } right: {
                PaneHeader(title: "\(target.rawValue) output") { EmptyView() }
                switch output {
                case .success(let text):
                    CodeTextView(text: .constant(text), isEditable: false, highlight: target == .json ? SyntaxHighlighter.json : (target == .xml ? SyntaxHighlighter.markup : nil))
                case .failure(let message):
                    Text(message)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.accentSoft)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Theme.well)
                }
            }
            ToolFooter {
                Text("Nested objects become dotted CSV columns; repeated XML elements become arrays.")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if case .success(let text) = output {
                    CopyButton(text: text)
                } else {
                    CopyButton(text: "")
                }
            }
        }
        .onAppear {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("<") {
                source = .xml
                target = .json
            }
        }
    }

    private enum Output {
        case success(String)
        case failure(String)
    }

    private func convert() -> Output {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .success("")
        }
        do {
            return .success(try DataConverter.convert(input, from: source, to: target))
        } catch let error as JSONParseError {
            return .failure(error.description)
        } catch {
            return .failure("\(error)")
        }
    }
}
