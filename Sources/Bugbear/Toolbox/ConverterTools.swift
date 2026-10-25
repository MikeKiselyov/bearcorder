import BugbearCore
import SwiftUI

struct TimeTool: View {
    @Binding var input: String
    @Environment(AppState.self) private var app
    @State private var now = Date()
    @State private var newZone = ""

    var body: some View {
        let parsed = TimeConverter.parse(input, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionLabel("Input · any format")
                        Spacer()
                        Button("Now") {
                            now = Date()
                            input = String(Int(now.timeIntervalSince1970))
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Use the current time as a Unix timestamp")
                    }
                    HStack(spacing: 10) {
                        TextField("1792839492, 2026-10-24T10:58:12Z, in 3 days…", text: $input)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, design: .monospaced))
                            .help("Type a timestamp or date in any format to see it in every other format")
                        if let result = parsed {
                            Text(result.format)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.accentText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        } else if !input.isEmpty {
                            Text("Not recognised")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accentSoft)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Theme.well)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Also understands: ms, µs, ns, ISO 8601, RFC 2822, “2026-10-24 13:58”, “in 3 days”, “-90m”, MongoDB ObjectId, UUID v1/v7")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                if let date = parsed?.date {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(TimeConverter.representations(of: date, now: now)) { item in
                            ValueRow(label: item.label, value: item.value, mono: item.label != "Human" && item.label != "Relative")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Time zones")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(app.settings.timeZones, id: \.self) { identifier in
                                if let zone = TimeZone(identifier: identifier) {
                                    zoneCard(date: date, identifier: identifier, zone: zone)
                                }
                            }
                            addZoneCard
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            if input.isEmpty {
                input = String(Int(Date().timeIntervalSince1970))
            }
        }
    }

    private func zoneCard(date: Date, identifier: String, zone: TimeZone) -> some View {
        let value = TimeConverter.zoneTime(date, zone: zone)
        let city = identifier.split(separator: "/").last.map { part in part.replacingOccurrences(of: "_", with: " ") } ?? identifier
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(city).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    app.settings.timeZones.removeAll { item in item == identifier }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityLabel("Remove \(city)")
                .help("Remove \(city) from your time zones")
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.time).font(.system(size: 15, design: .monospaced))
                Text(value.dayHint).font(.system(size: 10)).foregroundStyle(Theme.warning)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x33353A), lineWidth: 1))
    }

    private var addZoneCard: some View {
        Menu {
            Button("Search all zones & compare…") {
                NotificationCenter.default.post(name: .toolboxSelect, object: nil, userInfo: ["tool": ToolKind.timeZones.rawValue])
            }
            Divider()
            ForEach(commonZones, id: \.self) { identifier in
                Button(identifier) {
                    if !app.settings.timeZones.contains(identifier) {
                        app.settings.timeZones.append(identifier)
                    }
                }
            }
        } label: {
            Text("+ Add zone").font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, minHeight: 50)
        .help("Add a time zone to compare this time with")
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x45484F), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var commonZones: [String] {
        return [
            "UTC", "Europe/London", "Europe/Lisbon", "Europe/Berlin", "Europe/Warsaw", "Europe/Minsk",
            "Europe/Istanbul", "Europe/Moscow", "Asia/Dubai", "Asia/Tbilisi", "Asia/Almaty", "Asia/Kolkata",
            "Asia/Singapore", "Asia/Tokyo", "Australia/Sydney", "America/New_York", "America/Chicago",
            "America/Denver", "America/Los_Angeles", "America/Sao_Paulo",
        ]
    }
}

/// Number bases, colors, naming case, sizes and durations.
struct QuickConvertTool: View {
    @Binding var input: String
    @State private var number = "255"
    @State private var color = "#FF6B4A"
    @State private var caseText = "orderTotalAmount"
    @State private var size = "5 MiB"
    @State private var duration = "93784"

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                card("Number base", text: $number, placeholder: "255, 0xFF, 0b1010") {
                    if let bases = NumberBaseConverter.convert(number) {
                        ValueRow(label: "Decimal", value: bases.decimal)
                        ValueRow(label: "Hex", value: bases.hex)
                        ValueRow(label: "Binary", value: bases.binary)
                        ValueRow(label: "Octal", value: bases.octal)
                    } else {
                        invalid
                    }
                }
                card("Color", text: $color, placeholder: "#FF6B4A, rgb(…), hsl(…)") {
                    if let parsed = ColorConverter.parse(color) {
                        let formats = ColorConverter.formats(parsed)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.sRGB, red: parsed.red, green: parsed.green, blue: parsed.blue, opacity: parsed.alpha))
                            .frame(height: 28)
                        ValueRow(label: "Hex", value: formats.hex)
                        ValueRow(label: "RGB", value: formats.rgb)
                        ValueRow(label: "HSL", value: formats.hsl)
                        ValueRow(label: "SwiftUI", value: formats.swiftUI)
                        ValueRow(label: "UIKit", value: formats.uiKit)
                        ValueRow(label: "Android", value: formats.android)
                    } else {
                        invalid
                    }
                }
                card("Case", text: $caseText, placeholder: "any identifier or phrase") {
                    let variants = CaseConverter.variants(caseText)
                    ValueRow(label: "camelCase", value: variants.camel)
                    ValueRow(label: "PascalCase", value: variants.pascal)
                    ValueRow(label: "snake_case", value: variants.snake)
                    ValueRow(label: "kebab-case", value: variants.kebab)
                    ValueRow(label: "CONSTANT_CASE", value: variants.constant)
                    ValueRow(label: "Title Case", value: variants.title, mono: false)
                }
                VStack(spacing: 12) {
                    card("Data size", text: $size, placeholder: "5242880, 5 MB, 1.5 GiB") {
                        if let bytes = DataSizeConverter.parseBytes(size) {
                            let described = DataSizeConverter.describe(bytes)
                            ValueRow(label: "Binary", value: described.binary)
                            ValueRow(label: "Decimal", value: described.decimal)
                            ValueRow(label: "Bytes", value: described.bytes)
                        } else {
                            invalid
                        }
                    }
                    card("Duration", text: $duration, placeholder: "93784, PT26H3M4S, 1d 2h") {
                        if let seconds = DurationConverter.parseSeconds(duration) {
                            let described = DurationConverter.describe(seconds)
                            ValueRow(label: "Components", value: described.components)
                            ValueRow(label: "ISO 8601", value: described.iso)
                            ValueRow(label: "Seconds", value: String(format: "%.0f", seconds))
                            ValueRow(label: "Milliseconds", value: described.milliseconds)
                        } else {
                            invalid
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            // Route clipboard input to the card it fits.
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return }
            if ColorConverter.parse(text) != nil && (text.hasPrefix("#") || text.lowercased().hasPrefix("rgb") || text.lowercased().hasPrefix("hsl")) {
                color = text
            } else if NumberBaseConverter.parse(text) != nil {
                number = text
            } else {
                caseText = text
            }
        }
    }

    private var invalid: some View {
        Text("Not recognised").font(.system(size: 12)).foregroundStyle(Theme.accentSoft)
    }

    private func card<Content: View>(_ title: String, text: Binding<String>, placeholder: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .help("Type a value to see it in other formats, for example \(placeholder)")
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Theme.well)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            content()
        }
        .padding(12)
        .background(Color(hex: 0x1F2023))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct GenerateTool: View {
    @Binding var input: String
    @State private var version = 4
    @State private var count = 5
    @State private var uppercase = false
    @State private var uuids: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("UUID")
                    HStack(spacing: 12) {
                        PillPicker(options: [4, 7], selection: $version) { value in "v\(value)" }
                            .frame(width: 120)
                            .help("v4 is fully random, v7 starts with a timestamp so IDs sort by creation time")
                        Stepper("Count: \(count)", value: $count, in: 1...50)
                            .font(.system(size: 12))
                            .help("How many UUIDs to generate")
                        Toggle("Uppercase", isOn: $uppercase).toggleStyle(.checkbox).font(.system(size: 12))
                            .help("Use uppercase hex letters in the UUIDs")
                        Spacer()
                        Button("Generate") { generate() }
                            .buttonStyle(SecondaryButtonStyle())
                            .help("Generate a new batch of UUIDs")
                        CopyButton(text: uuids.joined(separator: "\n"), title: "Copy all", primary: false)
                    }
                    VStack(spacing: 6) {
                        ForEach(uuids, id: \.self) { uuid in
                            ValueRow(label: version == 7 ? "v7 · time ordered" : "v4 · random", value: uuid)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Hash of text")
                    CodeTextView(text: $input)
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    ForEach(HashGenerator.hashes(of: input)) { hash in
                        ValueRow(label: hash.name, value: hash.value)
                    }
                }
            }
            .padding(16)
        }
        .onAppear { generate() }
        .onChange(of: version) { generate() }
        .onChange(of: count) { generate() }
        .onChange(of: uppercase) { generate() }
    }

    private func generate() {
        var list: [String] = []
        for _ in 0..<count {
            var value = version == 7 ? UUIDGenerator.v7() : UUIDGenerator.v4()
            if uppercase {
                value = value.uppercased()
            }
            list.append(value)
        }
        uuids = list
    }
}
