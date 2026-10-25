import AppKit
import BugbearCore
import SwiftUI

struct ToolboxView: View {
    let initialTool: ToolKind
    let initialInput: String
    let detectedFromClipboard: Bool

    @State private var selected: ToolKind = .json
    @State private var search = ""
    @State private var inputs: [ToolKind: String] = [:]
    @State private var detectedNote: String?

    private let sections: [(title: String, tools: [ToolKind])] = [
        (title: "Format", tools: [.json, .xml, .yaml, .html, .sql, .graphql]),
        (title: "Decode · Encode", tools: [.jwt, .base64, .url, .htmlEntities]),
        (title: "Convert", tools: [.time, .timeZones, .dataConvert, .quick]),
        (title: "Generate", tools: [.generate, .testData, .length, .qr]),
        (title: "Inspect", tools: [.jsonDiff, .jsonPath, .http, .regex, .cron, .contrast]),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.border)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.window)
        .onAppear {
            selected = initialTool
            if !initialInput.isEmpty {
                inputs[initialTool] = initialInput
            }
            if detectedFromClipboard {
                detectedNote = "Detected from clipboard"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolboxSelect)) { notification in
            guard let raw = notification.userInfo?["tool"] as? String, let tool = ToolKind(rawValue: raw) else { return }
            selected = tool
            if let input = notification.userInfo?["input"] as? String, !input.isEmpty {
                inputs[tool] = input
                detectedNote = "Detected from clipboard"
            }
        }
    }

    private func binding(for tool: ToolKind) -> Binding<String> {
        return Binding(get: { inputs[tool] ?? "" }, set: { value in inputs[tool] = value })
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                TextField("Search tools", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        if let first = filteredSections.first?.tools.first {
                            selected = first
                        }
                    }
                    .tip("Find a tool by name or keyword, Return opens the first match")
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color(hex: 0x26282C))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 12)
            .padding(.top, 40)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredSections, id: \.title) { section in
                        SectionLabel(section.title)
                            .padding(.horizontal, 8)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        ForEach(section.tools) { tool in
                            sidebarRow(tool)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            Button {
                if let clipboard = NSPasteboard.general.string(forType: .string) {
                    if let tool = ContentDetector.detect(clipboard) {
                        selected = tool
                        inputs[tool] = clipboard
                        detectedNote = "Detected from clipboard"
                    } else {
                        inputs[selected] = clipboard
                        detectedNote = "Pasted from clipboard"
                    }
                }
            } label: {
                Label("Paste & detect", systemImage: "doc.on.clipboard")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .tip("Paste the clipboard and open the tool that fits its content, like JSON, JWT or a timestamp")
            .padding(12)
        }
        .frame(width: 230)
        .background(Theme.sidebar)
    }

    private var filteredSections: [(title: String, tools: [ToolKind])] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return sections }
        var result: [(title: String, tools: [ToolKind])] = []
        for section in sections {
            let matching = section.tools.filter { tool in
                tool.rawValue.lowercased().contains(query) || keywords(tool).contains(query)
            }
            if !matching.isEmpty {
                result.append((title: section.title, tools: matching))
            }
        }
        return result
    }

    private func keywords(_ tool: ToolKind) -> String {
        switch tool {
        case .time: return "timestamp unix epoch date iso utc"
        case .timeZones: return "timezone time zone world clock city country offset compare meeting"
        case .quick: return "hex binary color rgb hsl case camel snake kebab size bytes duration"
        case .generate: return "uuid guid md5 sha hash random"
        case .testData: return "fake name email phone card credit luhn iban password edge xss sql unicode emoji"
        case .qr: return "qr barcode scan phone link"
        case .regex: return "regexp regular expression match replace pattern"
        case .jsonDiff: return "compare difference changes response api"
        case .jsonPath: return "query path jq select field"
        case .http: return "request response headers cookie curl devtools har query"
        case .cron: return "schedule crontab job every minute"
        case .length: return "limit max characters bytes counterstring long string"
        case .contrast: return "wcag accessibility a11y color picker eyedropper aa aaa"
        case .dataConvert: return "csv yaml xml json convert"
        case .url: return "percent query"
        case .jwt: return "token bearer"
        default: return ""
        }
    }

    private func icon(_ tool: ToolKind) -> String {
        switch tool {
        case .json: return "{ }"
        case .xml: return "</>"
        case .yaml: return "—:"
        case .html: return "<>"
        case .sql: return "SQL"
        case .graphql: return "gql"
        case .jwt: return "jwt"
        case .base64: return "b64"
        case .url: return "%20"
        case .htmlEntities: return "&;"
        case .time: return "t"
        case .timeZones: return "tz"
        case .dataConvert: return "⇄"
        case .quick: return "0x"
        case .generate: return "id"
        case .testData: return "@"
        case .qr: return "qr"
        case .regex: return ".*"
        case .jsonDiff: return "±"
        case .jsonPath: return "$."
        case .http: return "H"
        case .cron: return "*/5"
        case .length: return "#"
        case .contrast: return "◐"
        }
    }

    private func sidebarRow(_ tool: ToolKind) -> some View {
        let isSelected = tool == selected
        return Button {
            selected = tool
            detectedNote = nil
        } label: {
            HStack(spacing: 10) {
                Text(icon(tool))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isSelected ? Theme.accentSoft : Theme.textSecondary)
                    .frame(width: 26, alignment: .leading)
                Text(tool.rawValue).font(.system(size: 13)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isSelected ? Theme.controlSelected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tip(purpose(tool))
    }

    private func purpose(_ tool: ToolKind) -> String {
        switch tool {
        case .json, .xml, .yaml, .html, .sql, .graphql: return "Format, validate and minify \(tool.rawValue)"
        case .jwt: return "Decode a JWT to read its header, claims and expiry"
        case .base64: return "Encode or decode Base64 text"
        case .url: return "Percent-encode or decode URLs and query strings"
        case .htmlEntities: return "Escape or unescape HTML entities like &amp;"
        case .time: return "Convert Unix timestamps and dates between formats and time zones"
        case .timeZones: return "Compare your time with other cities, for example to plan a call"
        case .dataConvert: return "Convert data between JSON, YAML, XML and CSV"
        case .quick: return "Convert numbers, colors, text case, sizes and durations"
        case .generate: return "Generate UUIDs and hashes like MD5 and SHA"
        case .testData: return "Generate fake names, emails, cards and tricky edge-case strings for testing"
        case .qr: return "Make a QR code from text or a link, or read one from an image"
        case .regex: return "Test a regular expression against text and see the matches"
        case .jsonDiff: return "Compare two JSON documents and see what changed"
        case .jsonPath: return "Query JSON with a JSONPath expression"
        case .http: return "Parse a raw HTTP request or response, headers, cookies and query"
        case .cron: return "Explain a cron expression and show the next run times"
        case .length: return "Count characters and bytes, and make strings of an exact length to test field limits"
        case .contrast: return "Check text and background color contrast against WCAG"
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title(selected)).font(.system(size: 14, weight: .semibold))
                if let note = detectedNote {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: 0x26282C))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .padding(.top, 28)
            Divider().overlay(Theme.border)
            toolView
        }
    }

    private func title(_ tool: ToolKind) -> String {
        switch tool {
        case .json, .xml, .yaml, .html, .sql, .graphql: return "\(tool.rawValue) formatter"
        case .jwt: return "JWT decoder"
        case .base64: return "Base64"
        case .url: return "URL encode / decode"
        case .htmlEntities: return "HTML entities"
        case .time: return "Time & date converter"
        case .timeZones: return "Time zones · you vs the world"
        case .dataConvert: return "Data converter"
        case .quick: return "Quick converters"
        case .generate: return "UUID & hash generator"
        case .testData: return "Test data generator"
        case .qr: return "QR code: make and read"
        case .regex: return "Regex tester"
        case .jsonDiff: return "JSON diff · what changed"
        case .jsonPath: return "JSONPath query"
        case .http: return "HTTP request / response"
        case .cron: return "Cron explainer"
        case .length: return "String length · field limits"
        case .contrast: return "Color & contrast (WCAG)"
        }
    }

    @ViewBuilder
    private var toolView: some View {
        switch selected {
        case .json, .xml, .yaml, .html, .sql, .graphql:
            FormatterTool(kind: selected.formatter ?? .json, input: binding(for: selected))
                .id(selected)
        case .jwt:
            JWTTool(input: binding(for: .jwt))
        case .base64:
            Base64Tool(input: binding(for: .base64))
        case .url:
            URLTool(input: binding(for: .url))
        case .htmlEntities:
            EntitiesTool(input: binding(for: .htmlEntities))
        case .time:
            TimeTool(input: binding(for: .time))
        case .timeZones:
            TimeZonesTool()
        case .dataConvert:
            DataConvertTool(input: binding(for: .dataConvert))
        case .quick:
            QuickConvertTool(input: binding(for: .quick))
        case .generate:
            GenerateTool(input: binding(for: .generate))
        case .testData:
            TestDataTool()
        case .qr:
            QRTool(input: binding(for: .qr))
        case .regex:
            RegexTool(input: binding(for: .regex))
        case .jsonDiff:
            JSONDiffTool(input: binding(for: .jsonDiff))
        case .jsonPath:
            JSONPathTool(input: binding(for: .jsonPath))
        case .http:
            HTTPTool(input: binding(for: .http))
        case .cron:
            CronTool(input: binding(for: .cron))
        case .length:
            LengthTool(input: binding(for: .length))
        case .contrast:
            ColorContrastTool()
        }
    }
}

// MARK: - Shared pieces

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Header for a pane: label on the left, accessory on the right.
struct PaneHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack {
            SectionLabel(title)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
    }
}

/// Input on the left, output on the right.
struct SplitPanes<Left: View, Right: View>: View {
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) { left() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(Theme.border)
            VStack(spacing: 0) { right() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ToolFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            HStack(spacing: 12) {
                content()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .frame(height: 48)
        }
    }
}

struct CopyButton: View {
    let text: String
    var title = "Copy  ⇧⌘C"
    var primary = true
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : title) {
            copyToClipboard(text)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                copied = false
            }
        }
        .buttonStyle(AccentButtonStyle(isEnabled: !text.isEmpty))
        .disabled(text.isEmpty)
        .keyboardShortcut(primary ? KeyboardShortcut("c", modifiers: [.command, .shift]) : nil)
        .tip(primary ? "Copy the result to the clipboard (⇧⌘C)" : "Copy to the clipboard")
    }
}

/// A labeled value with a small copy button; used in result lists.
struct ValueRow: View {
    let label: String
    let value: String
    var mono = true

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(mono ? .system(size: 13, design: .monospaced) : .system(size: 13))
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button {
                copyToClipboard(value)
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .tip("Copy \(label) to the clipboard")
            .accessibilityLabel("Copy \(label)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
