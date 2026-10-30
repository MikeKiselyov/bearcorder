import AppCore
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
                PaneHeader(title: L("toolbox.pane.input")) {
                    Text(L("toolbox.format.pasteHint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                CodeTextView(text: $input)
            } right: {
                PaneHeader(title: L("toolbox.pane.output")) {
                    if !input.isEmpty {
                        Text(current.isValid ? statusTitle : L("toolbox.format.invalid"))
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
                            Button(L("toolbox.format.copyAs", format.rawValue)) {
                                if let converted = try? DataConverter.convert(input, from: .json, to: format) {
                                    copyToClipboard(converted)
                                }
                            }
                        }
                    } label: {
                        Text(L("toolbox.format.copyAs.menu"))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .tip(L("toolbox.format.copyAs.tip"))
                }
                CopyButton(text: current.isValid ? current.output : "")
            }
        }
    }

    private var statusTitle: String {
        switch kind {
        case .json: return L("toolbox.format.valid", "JSON")
        case .xml: return L("toolbox.format.valid", "XML")
        case .yaml: return L("toolbox.format.valid", "YAML")
        case .html: return L("toolbox.format.parsed", "HTML")
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
        if input.isEmpty { return L("toolbox.format.empty") }
        let inputBytes = input.utf8.count
        let outputBytes = current.output.utf8.count
        var text = current.message
        if current.isValid {
            text += " · " + L("toolbox.format.sizes", inputBytes, outputBytes)
        }
        return text
    }

    private var optionsBar: some View {
        HStack(spacing: 14) {
            PillPicker(options: FormatMode.allCases, selection: $mode) { value in modeTitle(value) }
                .frame(width: 170)
                .tip(L("toolbox.format.mode.tip"))
            Picker(L("toolbox.format.indent"), selection: Binding(get: { useTabs ? 0 : indentWidth }, set: { value in
                if value == 0 {
                    useTabs = true
                } else {
                    useTabs = false
                    indentWidth = value
                }
            })) {
                Text(L("toolbox.format.indent.two")).tag(2)
                Text(L("toolbox.format.indent.four")).tag(4)
                Text(L("toolbox.format.indent.tabs")).tag(0)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(mode == .minify)
            .tip(L("toolbox.format.indent.tip"))
            if kind == .json || kind == .yaml {
                Toggle(L("toolbox.format.sortKeys"), isOn: $sortKeys).toggleStyle(.checkbox)
                    .tip(L("toolbox.format.sortKeys.tip"))
            }
            if kind == .json {
                Toggle(L("toolbox.format.unescape"), isOn: $unescape).toggleStyle(.checkbox)
                    .tip(L("toolbox.format.unescape.tip"))
            }
            Spacer()
            Button(L("toolbox.button.clear")) { input = "" }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.link)
                .tip(L("toolbox.format.clear.tip"))
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func modeTitle(_ mode: FormatMode) -> String {
        switch mode {
        case .format: return L("toolbox.format.mode.format")
        case .minify: return L("toolbox.format.mode.minify")
        }
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
                    .tip(L("toolbox.convert.source.tip"))
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
                .accessibilityLabel(L("toolbox.convert.swap"))
                .tip(L("toolbox.convert.swap.tip"))
                PillPicker(options: DataFormat.allCases, selection: $target) { value in value.rawValue }
                    .frame(width: 240)
                    .tip(L("toolbox.convert.target.tip"))
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider().overlay(Theme.border)
            SplitPanes {
                PaneHeader(title: L("toolbox.convert.input", source.rawValue)) { EmptyView() }
                CodeTextView(text: $input)
            } right: {
                PaneHeader(title: L("toolbox.convert.output", target.rawValue)) { EmptyView() }
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
                Text(L("toolbox.convert.footer"))
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
