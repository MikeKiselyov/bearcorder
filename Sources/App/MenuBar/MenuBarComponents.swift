import AppKit
import AppCore
import SwiftUI

struct MenuRow: View {
    let systemImage: String
    var tint: TileTint = .gray
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconTile(systemImage: systemImage, tint: tint, size: 24)
                Text(title).font(.system(size: 13))
                Spacer()
                Text(shortcut).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(hovering ? Theme.controlSelected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovering = inside }
    }
}

struct ToggleChip: View {
    let systemImage: String
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11))
                Text(title).font(.system(size: 12))
            }
            .foregroundStyle(isOn ? Theme.accentText : Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.control))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isOn ? Color.clear : Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? L("menubar.chip.on") : L("menubar.chip.off"))
    }
}

/// Wrapping row of small tool chips.
struct FlowChips<Trailing: View>: View {
    let items: [(String, ToolKind)]
    let action: (ToolKind) -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.0) { item in
                Button {
                    action(item.1)
                } label: {
                    Text(item.0)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Theme.control)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tip(L("menubar.toolbox.chip.tip", item.0))
            }
            trailing()
        }
    }
}

/// Minimal flow layout: places children left to right and wraps.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct CaptureThumbnail: View {
    @Environment(AppState.self) private var app
    let capture: Capture
    var height: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                if let image = app.store.thumbnail(for: capture) {
                    // The cell sets the size and the picture fills it: an image sized by itself
                    // made wide captures (two displays) push the grid past the panel's edge.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .overlay {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipped()
                } else {
                    Rectangle().fill(Color(hex: 0x2E3136)).frame(height: height)
                }
                if capture.kind == .video {
                    Text(TimeFormat.clock(capture.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(hex: 0x111214))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(relative(capture.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return L("menubar.recent.age.justNow") }
        if seconds < 3600 { return L("menubar.recent.age.minutes", Int(seconds / 60)) }
        if seconds < 86400 { return L("menubar.recent.age.hours", Int(seconds / 3600)) }
        return L("menubar.recent.age.days", Int(seconds / 86400))
    }
}

/// Compact world clock in the Tools tab: saved zones next to your time.
struct WorldClockSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TimelineView(.everyMinute) { context in
            let reference = TimeZone.current
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(L("menubar.worldClock.title"))
                    Spacer()
                    Button(L("menubar.worldClock.compare")) { app.openToolbox(tool: .timeZones) }
                        .buttonStyle(.plain)
                        .tip(L("menubar.worldClock.compare.tip"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.link)
                }
                HStack {
                    Text(L("menubar.worldClock.you", WorldClock.city(of: reference.identifier))).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(TimeConverter.format(context.date, pattern: "HH:mm", timeZone: reference))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                ForEach(app.settings.timeZones.prefix(5), id: \.self) { identifier in
                    if let info = WorldClock.compare(identifier, at: context.date, reference: reference) {
                        HStack(spacing: 8) {
                            Text(info.city).font(.system(size: 12)).lineLimit(1)
                            Text(info.differenceText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(info.differenceSeconds == 0 ? Theme.textSecondary : (info.differenceSeconds > 0 ? Theme.warning : Theme.link))
                            Spacer()
                            if info.dayPart != .work {
                                Image(systemName: info.dayPart == .night ? "moon.fill" : "sun.haze")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textSecondary)
                                    .tip(info.dayPart.title)
                            }
                            Text(info.time + (info.dayHint.isEmpty ? "" : " ·"))
                                .font(.system(size: 13, design: .monospaced))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
