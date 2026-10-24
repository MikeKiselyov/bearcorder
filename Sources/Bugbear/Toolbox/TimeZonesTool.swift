import BugbearCore
import SwiftUI

/// Compare your time with other zones: search, differences, day/night strips, meeting window.
struct TimeZonesTool: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    /// Offset from now in minutes, picked with the slider. 0 = live.
    @State private var shiftMinutes: Double = 0
    @State private var now = Date()

    private let reference = TimeZone.current
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var moment: Date {
        return now.addingTimeInterval(shiftMinutes * 60)
    }

    private var savedZones: [String] {
        var zones: [String] = []
        for identifier in app.settings.timeZones where TimeZone(identifier: identifier) != nil {
            zones.append(identifier)
        }
        // West to east, so the list reads like a map.
        return zones.sorted { first, second in
            let firstOffset = TimeZone(identifier: first)?.secondsFromGMT(for: moment) ?? 0
            let secondOffset = TimeZone(identifier: second)?.secondsFromGMT(for: moment) ?? 0
            return firstOffset < secondOffset
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    yourTime
                    searchSection
                    comparison
                }
                .padding(16)
            }
            ToolFooter {
                Text(meetingWindowText).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer()
                CopyButton(text: summaryText, title: "Copy summary", primary: false)
            }
        }
        .onReceive(ticker) { value in now = value }
    }

    // MARK: Your time and the time slider

    private var yourTime: some View {
        let local = WorldClock.compare(reference.identifier, at: moment, reference: reference)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Your time · \(WorldClock.city(of: reference.identifier))")
                    Text(TimeConverter.format(moment, pattern: "HH:mm:ss", timeZone: reference))
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(TimeConverter.format(moment, pattern: "EEEE, d MMMM yyyy", timeZone: reference))
                        .font(.system(size: 13))
                    Text("\(local?.offsetText ?? "") · \(local?.abbreviation ?? "")\(local?.isDaylightSaving == true ? " · DST" : "")")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Text("Compare at").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Slider(value: $shiftMinutes, in: -720...720, step: 30)
                    .tint(Theme.accent)
                Text(shiftLabel)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 90, alignment: .trailing)
                Button("Now") { shiftMinutes = 0 }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(shiftMinutes == 0)
            }
        }
        .padding(14)
        .background(Color(hex: 0x1F2023))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var shiftLabel: String {
        if shiftMinutes == 0 { return "now" }
        let hours = Int(abs(shiftMinutes)) / 60
        let minutes = Int(abs(shiftMinutes)) % 60
        let sign = shiftMinutes > 0 ? "+" : "−"
        if minutes == 0 { return "\(sign)\(hours)h" }
        return "\(sign)\(hours)h \(minutes)m"
    }

    // MARK: Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search a city, country, abbreviation (PST) or offset (+5:30)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit {
                        if let first = results.first { add(first) }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.well)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                if results.isEmpty {
                    Text("No time zone matches “\(query)”").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(spacing: 2) {
                        ForEach(results, id: \.self) { identifier in
                            searchRow(identifier)
                        }
                    }
                    .padding(4)
                    .background(Theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var results: [String] {
        return WorldClock.search(query, at: moment, limit: 10)
    }

    private func searchRow(_ identifier: String) -> some View {
        let info = WorldClock.compare(identifier, at: moment, reference: reference)
        let isSaved = app.settings.timeZones.contains(identifier)
        return Button {
            add(identifier)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(WorldClock.city(of: identifier)).font(.system(size: 13, weight: .semibold))
                    Text(identifier).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(info?.time ?? "").font(.system(size: 13, design: .monospaced))
                Text(info?.offsetText ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .trailing)
                DifferenceBadge(text: info?.differenceText ?? "", seconds: info?.differenceSeconds ?? 0)
                    .frame(width: 84, alignment: .trailing)
                Image(systemName: isSaved ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSaved ? Theme.success : Theme.link)
                    .frame(width: 18)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "\(identifier), added" : "Add \(identifier)")
    }

    private func add(_ identifier: String) {
        if !app.settings.timeZones.contains(identifier) {
            app.settings.timeZones.append(identifier)
        }
        query = ""
    }

    // MARK: Comparison

    private var comparison: some View {
        let zones = savedZones
        let referenceStrip = WorldClock.hourStrip(for: reference, on: moment, reference: reference)
        let shared = Set(WorldClock.sharedWorkingHours(zones: [reference] + zones.compactMap { TimeZone(identifier: $0) }, on: moment, reference: reference))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reference
        let selectedHour = calendar.component(.hour, from: moment)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Compared zones · \(zones.count)")
                Spacer()
                Legend()
            }
            ZoneRow(
                title: "You · \(WorldClock.city(of: reference.identifier))",
                subtitle: reference.identifier,
                info: WorldClock.compare(reference.identifier, at: moment, reference: reference),
                strip: referenceStrip,
                shared: shared,
                selectedHour: selectedHour,
                isReference: true,
                onRemove: nil
            )
            if zones.isEmpty {
                Text("Search above to add zones to compare.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 8)
            }
            ForEach(zones, id: \.self) { identifier in
                if let zone = TimeZone(identifier: identifier) {
                    ZoneRow(
                        title: WorldClock.city(of: identifier),
                        subtitle: identifier,
                        info: WorldClock.compare(identifier, at: moment, reference: reference),
                        strip: WorldClock.hourStrip(for: zone, on: moment, reference: reference),
                        shared: shared,
                        selectedHour: selectedHour,
                        isReference: false,
                        onRemove: {
                            app.settings.timeZones.removeAll { item in item == identifier }
                        }
                    )
                }
            }
        }
    }

    private var meetingWindowText: String {
        let zones = [reference] + savedZones.compactMap { TimeZone(identifier: $0) }
        let shared = WorldClock.sharedWorkingHours(zones: zones, on: moment, reference: reference)
        guard let first = shared.first, let last = shared.last else {
            return savedZones.isEmpty ? "Add zones to find a shared meeting window" : "No hours where everyone is at work (9–18)"
        }
        return String(format: "Everyone at work: %02d:00–%02d:00 your time (%d h)", first, last + 1, shared.count)
    }

    private var summaryText: String {
        var lines: [String] = []
        let localTime = TimeConverter.format(moment, pattern: "yyyy-MM-dd HH:mm", timeZone: reference)
        lines.append("\(localTime) \(WorldClock.city(of: reference.identifier)) (you)")
        for identifier in savedZones {
            guard let info = WorldClock.compare(identifier, at: moment, reference: reference) else { continue }
            var line = "\(info.time) \(info.city) · \(info.offsetText) · \(info.differenceText)"
            if !info.dayHint.isEmpty { line += " · \(info.dayHint)" }
            lines.append(line)
        }
        lines.append(meetingWindowText)
        return lines.joined(separator: "\n")
    }
}

private struct DifferenceBadge: View {
    let text: String
    let seconds: Int

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(seconds == 0 ? Theme.textSecondary : (seconds > 0 ? Theme.warning : Theme.link))
    }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 10) {
            item(color: ZoneRow.color(for: .work), title: "Work 9–18")
            item(color: ZoneRow.color(for: .morning), title: "Morning")
            item(color: ZoneRow.color(for: .evening), title: "Evening")
            item(color: ZoneRow.color(for: .night), title: "Night")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.textSecondary)
    }

    private func item(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}

/// One zone: name, current time, difference, and its 24 hours lined up under yours.
private struct ZoneRow: View {
    let title: String
    let subtitle: String
    let info: WorldClock.Comparison?
    let strip: [Int]
    let shared: Set<Int>
    let selectedHour: Int
    let isReference: Bool
    let onRemove: (() -> Void)?

    static func color(for part: WorldClock.DayPart) -> Color {
        switch part {
        case .work: return Color(hex: 0x2E7D5B)
        case .morning: return Color(hex: 0x6B5A2A)
        case .evening: return Color(hex: 0x4A3F6B)
        case .night: return Color(hex: 0x24262B)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(Self.color(for: info?.dayPart ?? .night).opacity(1.6)).frame(width: 8, height: 8)
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(info?.time ?? "--:--").font(.system(size: 18, weight: .semibold, design: .monospaced))
                    if let hint = info?.dayHint, !hint.isEmpty {
                        Text(hint).font(.system(size: 10)).foregroundStyle(Theme.warning)
                    }
                }
                Text("\(info?.date ?? "") · \(info?.abbreviation ?? "")").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 120, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                DifferenceBadge(text: isReference ? "you" : (info?.differenceText ?? ""), seconds: isReference ? 0 : (info?.differenceSeconds ?? 0))
                Text(info?.offsetText ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 80, alignment: .trailing)

            // 24 cells, one per hour of your day, showing the hour in this zone.
            HStack(spacing: 2) {
                ForEach(0..<strip.count, id: \.self) { index in
                    let hour = strip[index]
                    let part = WorldClock.dayPart(hour: hour)
                    Text("\(hour)")
                        .font(.system(size: 9, weight: index == selectedHour ? .bold : .regular, design: .monospaced))
                        .foregroundStyle(index == selectedHour ? Theme.text : Theme.text.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Self.color(for: part))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(index == selectedHour ? Theme.accent : (shared.contains(index) ? Theme.success.opacity(0.7) : Color.clear), lineWidth: index == selectedHour ? 2 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(minWidth: 380)

            if let remove = onRemove {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16)
                .accessibilityLabel("Remove \(title)")
            } else {
                Color.clear.frame(width: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isReference ? Theme.controlSelected.opacity(0.6) : Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
