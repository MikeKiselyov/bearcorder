import QAHelperCore
import SwiftUI

enum CodecDirection: String, CaseIterable, Identifiable {
    case decode = "Decode"
    case encode = "Encode"

    var id: String { rawValue }
}

struct JWTTool: View {
    @Binding var input: String

    var body: some View {
        let decoded = Result { try JWTDecoder.decode(input) }
        VStack(spacing: 0) {
            PaneHeader(title: "Token") {
                Text("Bearer prefix is fine").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            CodeTextView(text: $input)
                .frame(height: 110)
            Divider().overlay(Theme.border)
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                placeholder("Paste a JWT to see its header, payload and claim dates.")
            } else {
                switch decoded {
                case .success(let token):
                    decodedView(token)
                case .failure(let error):
                    placeholder("\(error)")
                        .foregroundStyle(Theme.accentSoft)
                }
            }
        }
    }

    private func decodedView(_ token: DecodedJWT) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("alg: \(token.algorithm)").font(.system(size: 12, design: .monospaced))
                if let expired = token.isExpired {
                    Text(expired ? "Expired" : "Not expired")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(expired ? Theme.accentText : Theme.accentText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(expired ? Theme.accent : Theme.success)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                ForEach(token.claims, id: \.name) { claim in
                    Text("\(claim.name): \(claim.value)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            SplitPanes {
                PaneHeader(title: "Header") { CopyButton(text: token.header, title: "Copy", primary: false) }
                CodeTextView(text: .constant(token.header), isEditable: false, highlight: SyntaxHighlighter.json)
            } right: {
                PaneHeader(title: "Payload") { CopyButton(text: token.payload, title: "Copy", primary: false) }
                CodeTextView(text: .constant(token.payload), isEditable: false, highlight: SyntaxHighlighter.json)
            }
            ToolFooter {
                Text("The signature is not verified; decoding only.").foregroundStyle(Theme.textSecondary)
                Spacer()
                CopyButton(text: token.payload)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct Base64Tool: View {
    @Binding var input: String
    @State private var direction: CodecDirection = .decode
    @State private var urlSafe = false

    var body: some View {
        let output = convert()
        CodecLayout(direction: $direction, input: $input, output: output.text, error: output.error) {
            Toggle("URL-safe alphabet (encode)", isOn: $urlSafe).toggleStyle(.checkbox)
        } footer: {
            Text(direction == .decode ? "Accepts standard and URL-safe Base64, with or without padding." : "UTF-8 text in, Base64 out.")
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func convert() -> (text: String, error: String?) {
        if input.isEmpty { return (text: "", error: nil) }
        if direction == .encode {
            return (text: Base64Codec.encode(input, urlSafe: urlSafe), error: nil)
        }
        do {
            return (text: try Base64Codec.decode(input), error: nil)
        } catch {
            return (text: "", error: "\(error)")
        }
    }
}

struct URLTool: View {
    @Binding var input: String
    @State private var direction: CodecDirection = .decode
    @State private var componentOnly = true

    var body: some View {
        let output = direction == .decode ? URLCodec.decode(input) : URLCodec.encode(input, componentOnly: componentOnly)
        let items = URLCodec.queryItems(input)
        CodecLayout(direction: $direction, input: $input, output: output, error: nil) {
            Toggle("Encode as a query component (also / ? & =)", isOn: $componentOnly).toggleStyle(.checkbox)
        } footer: {
            if input.contains("=") && !items.isEmpty {
                Menu("Query parameters (\(items.count))") {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button("\(item.name) = \(item.value)") {
                            copyToClipboard(item.value)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Text("Click a parameter to copy its value").foregroundStyle(Theme.textSecondary)
            } else {
                Text("Decodes %XX and + as space.").foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct EntitiesTool: View {
    @Binding var input: String
    @State private var direction: CodecDirection = .decode
    @State private var nonASCII = false

    var body: some View {
        let output = direction == .decode ? HTMLEntityCodec.decode(input) : HTMLEntityCodec.encode(input, nonASCII: nonASCII)
        CodecLayout(direction: $direction, input: $input, output: output, error: nil) {
            Toggle("Encode non-ASCII as &#…;", isOn: $nonASCII).toggleStyle(.checkbox)
        } footer: {
            Text("Named entities like &amp;copy; plus decimal and hex references.").foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Shared layout for the two-way text codecs.
struct CodecLayout<Options: View, Footer: View>: View {
    @Binding var direction: CodecDirection
    @Binding var input: String
    let output: String
    let error: String?
    @ViewBuilder let options: () -> Options
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                PillPicker(options: CodecDirection.allCases, selection: $direction) { value in value.rawValue }
                    .frame(width: 170)
                options()
                Spacer()
                Button {
                    input = output
                    direction = direction == .decode ? .encode : .decode
                } label: {
                    Label("Swap", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.link)
                .disabled(output.isEmpty)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider().overlay(Theme.border)
            SplitPanes {
                PaneHeader(title: "Input") { EmptyView() }
                CodeTextView(text: $input)
            } right: {
                PaneHeader(title: "Output") { EmptyView() }
                if let message = error {
                    Text(message)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.accentSoft)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Theme.well)
                } else {
                    CodeTextView(text: .constant(output), isEditable: false)
                }
            }
            ToolFooter {
                footer()
                Spacer()
                CopyButton(text: error == nil ? output : "")
            }
        }
    }
}
