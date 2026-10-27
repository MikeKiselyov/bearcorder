import BugbearCore
import SwiftUI

/// Multi-track timeline in source time: video with trim, clicks, keys, overlays, blur, speed.
struct TimelineEditor: View {
    @Bindable var model: VideoEditorModel
    @State private var rangeStart: Double?
    @State private var trimDragOriginal: TimeSpan?
    /// A drag on the ruler: from the playhead it moves it, elsewhere it selects a range.
    @State private var rulerDrag = RulerDrag()

    private let labelWidth: CGFloat = 84
    private let horizontalPadding: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(100, proxy.size.width - labelWidth - horizontalPadding * 2 - 12)
            let scale = trackWidth / max(model.duration, 0.1)
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    ruler(width: trackWidth, scale: scale)
                    track("Video", height: 46) { videoTrack(width: trackWidth, scale: scale) }
                    track("Clicks", height: 16) { clicksTrack(scale: scale) }
                    track("Keys", height: 18) { keysTrack(scale: scale) }
                    track("Marks", height: 22) { overlayTrack(kinds: [.text, .arrow, .rectangle], scale: scale) }
                    track("Blur", height: 22) { overlayTrack(kinds: [.blur], scale: scale) }
                    track("Speed", height: 22) { speedTrack(scale: scale) }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 8)

                // Range selection band and playhead across every track.
                let left = labelWidth + horizontalPadding + 12
                if let selected = model.range {
                    Rectangle()
                        .fill(Theme.link.opacity(0.12))
                        .overlay(Rectangle().stroke(Theme.link.opacity(0.6), lineWidth: 1))
                        .frame(width: max(2, selected.duration * scale), height: proxy.size.height - 12)
                        .offset(x: left + selected.start * scale, y: 6)
                        .allowsHitTesting(false)
                }
                Rectangle()
                    .fill(Theme.text)
                    .frame(width: 2, height: proxy.size.height - 10)
                    .offset(x: left + model.playhead * scale - 1, y: 6)
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.text)
                    .frame(width: 12, height: 10)
                    .offset(x: left + model.playhead * scale - 6, y: 4)
                    .allowsHitTesting(false)
            }
        }
        .background(Theme.sidebar)
    }

    private func track<Content: View>(_ label: String, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height)
        }
    }

    // MARK: Ruler: click to seek, drag to select a range

    private func ruler(width: CGFloat, scale: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text(model.range.map { selected in "Sel " + TimeFormat.clock(selected.duration, tenths: true) } ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.link)
                .frame(width: labelWidth, alignment: .leading)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.clear)
                let step = rulerStep(scale: scale)
                let count = Int(model.duration / step)
                ForEach(0...max(0, count), id: \.self) { index in
                    let time = Double(index) * step
                    VStack(alignment: .leading, spacing: 1) {
                        Rectangle().fill(Theme.textTertiary).frame(width: 1, height: 5)
                        Text(TimeFormat.clock(time))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize()
                    }
                    .offset(x: time * scale)
                }
            }
            .frame(width: width, height: 22, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let action = rulerDrag.changed(startX: value.startLocation.x, x: value.location.x, playheadX: model.playhead * scale, scale: scale)
                        switch action {
                        case .seek(let time):
                            model.seek(toSource: clampTime(time))
                        case .select(let start, let end):
                            model.range = TimeSpan(start: clampTime(start), end: clampTime(end))
                        }
                    }
                    .onEnded { value in
                        if rulerDrag.ended(startX: value.startLocation.x, x: value.location.x) {
                            model.range = nil
                        }
                    }
            )
        }
    }

    /// Extra grab area on each side of a trim handle, in points.
    static let trimGrabPadding: CGFloat = 8

    private func rulerStep(scale: CGFloat) -> Double {
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60]
        for candidate in candidates where candidate * scale >= 60 {
            return candidate
        }
        return 120
    }

    private func clampTime(_ time: Double) -> Double {
        return max(0, min(model.duration, time))
    }

    // MARK: Video track with trim handles

    private func videoTrack(width: CGFloat, scale: CGFloat) -> some View {
        let trim = model.project.timeline.trim
        return ZStack(alignment: .leading) {
            HStack(spacing: 2) {
                if model.thumbnails.isEmpty {
                    Rectangle().fill(Theme.control)
                } else {
                    ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            // Dragging along the frames moves the playhead; the trim handles and cuts on top
            // keep their own gestures.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.seek(toSource: clampTime(value.location.x / scale))
                    }
            )

            // Trimmed-away areas.
            Rectangle().fill(Color(hex: 0x0E0F11, alpha: 0.72))
                .frame(width: trim.start * scale)
                .allowsHitTesting(false)
            Rectangle().fill(Color(hex: 0x0E0F11, alpha: 0.72))
                .frame(width: max(0, (model.duration - trim.end) * scale))
                .offset(x: trim.end * scale)
                .allowsHitTesting(false)

            // Cuts, hatched.
            ForEach(Array(model.project.timeline.cuts.enumerated()), id: \.offset) { index, cut in
                let isSelected = model.selection == .cut(index)
                HatchedRectangle(color: Theme.accent)
                    .frame(width: max(3, cut.duration * scale))
                    .overlay(Rectangle().stroke(isSelected ? Theme.text : Theme.accent, lineWidth: isSelected ? 2 : 1))
                    // The tip goes before the offset, so it moves with the bar.
                    .tip("Cut \(TimeFormat.clock(cut.start, tenths: true))–\(TimeFormat.clock(cut.end, tenths: true)). Delete to restore.")
                    .offset(x: cut.start * scale)
                    .onTapGesture { model.selection = .cut(index) }
            }

            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.accent, lineWidth: 2)
                .frame(width: max(4, trim.duration * scale))
                .offset(x: trim.start * scale)
                .allowsHitTesting(false)

            trimHandle(at: trim.start, scale: scale, isStart: true)
            trimHandle(at: trim.end, scale: scale, isStart: false)
        }
        .frame(width: width)
    }

    private func trimHandle(at time: Double, scale: CGFloat, isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.accent)
            .frame(width: 10, height: 30)
            .overlay(Rectangle().fill(Theme.accentText.opacity(0.6)).frame(width: 2, height: 12))
            // A wider area to grab than the handle looks.
            .padding(.horizontal, TimelineEditor.trimGrabPadding)
            .frame(height: 46)
            .contentShape(Rectangle())
            .tip(isStart ? "Trim start (I)" : "Trim end (O)")
            .offset(x: time * scale - 5 - TimelineEditor.trimGrabPadding)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if trimDragOriginal == nil {
                            trimDragOriginal = model.project.timeline.trim
                            model.checkpoint()
                        }
                        guard let original = trimDragOriginal else { return }
                        let delta = value.translation.width / scale
                        if isStart {
                            model.setTrimStart(original.start + delta)
                            model.seek(toSource: model.project.timeline.trim.start)
                        } else {
                            model.setTrimEnd(original.end + delta)
                            model.seek(toSource: model.project.timeline.trim.end - 0.05)
                        }
                    }
                    .onEnded { _ in trimDragOriginal = nil }
            )
            .accessibilityLabel(isStart ? "Trim start" : "Trim end")
    }

    // MARK: Clicks and keys

    private func clicksTrack(scale: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.clear)
            ForEach(Array(model.capture.events.enumerated()), id: \.offset) { _, event in
                if event.kind == .click {
                    Circle()
                        .fill(model.project.showClicks ? Theme.warning : Theme.textTertiary)
                        .frame(width: 8, height: 8)
                        .offset(x: event.time * scale - 4)
                }
                if event.kind == .marker {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accentSoft)
                        .tip("Marked moment (\(HotKeySettings.shared.readable(for: .mark)))")
                        .offset(x: event.time * scale - 2)
                        .onTapGesture { model.seek(toSource: event.time) }
                }
            }
        }
    }

    private func keysTrack(scale: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.clear)
            ForEach(Array(model.capture.events.enumerated()), id: \.offset) { _, event in
                if event.kind == .key {
                    Text(event.label)
                        .font(.system(size: 10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(hex: 0x34373C))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .fixedSize()
                        .opacity(model.project.showKeys ? 1 : 0.4)
                        .offset(x: event.time * scale)
                }
            }
        }
        .clipped()
    }

    // MARK: Overlays

    private func overlayTrack(kinds: [VideoOverlay.Kind], scale: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.clear)
            ForEach(model.project.overlays.filter { overlay in kinds.contains(overlay.kind) }) { overlay in
                SpanBar(
                    span: overlay.span,
                    scale: scale,
                    maxTime: model.duration,
                    label: overlay.kind == .text && !overlay.text.isEmpty ? overlay.text : overlay.kind.title,
                    fill: overlay.kind == .blur ? Color(hex: 0x5A5E66) : overlay.color.color,
                    textColor: overlay.kind == .blur ? Theme.text : Color(nsColor: overlay.color.contrastingText),
                    isSelected: model.selection == .overlay(overlay.id),
                    onBegin: { model.checkpoint() },
                    onChange: { span in
                        var updated = overlay
                        updated.span = span
                        model.updateOverlay(updated)
                    },
                    onSelect: {
                        model.selection = .overlay(overlay.id)
                        if !overlay.span.contains(model.playhead) {
                            model.seek(toSource: overlay.span.start)
                        }
                    }
                )
            }
        }
        .coordinateSpace(name: SpanBar.trackSpace)
    }

    private func speedTrack(scale: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.clear)
            ForEach(Array(model.project.timeline.speeds.enumerated()), id: \.offset) { index, edit in
                SpanBar(
                    span: edit.span,
                    scale: scale,
                    maxTime: model.duration,
                    label: String(format: "%.1f×", edit.factor),
                    fill: Theme.warning,
                    textColor: Theme.accentText,
                    isSelected: model.selection == .speed(index),
                    onBegin: { model.checkpoint() },
                    onChange: { span in
                        model.project.timeline.speeds[index].span = span
                        model.projectChanged()
                    },
                    onSelect: { model.selection = .speed(index) }
                )
            }
            ForEach(Array(model.project.timeline.freezes.enumerated()), id: \.offset) { index, freeze in
                let isSelected = model.selection == .freeze(index)
                HStack(spacing: 3) {
                    Image(systemName: "pause.fill").font(.system(size: 8))
                    Text(String(format: "%.0fs", freeze.duration)).font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 5)
                .frame(height: 20)
                .background(Theme.link)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.text, lineWidth: isSelected ? 2 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .tip("Freeze frame. Select and press Delete to remove.")
                .offset(x: freeze.at * scale - 4)
                .onTapGesture { model.selection = .freeze(index) }
            }
        }
        .coordinateSpace(name: SpanBar.trackSpace)
    }
}

/// A draggable bar for a time span: drag the body to move, the edges to resize. One drag gesture
/// decides by where it starts: separate gestures on the edges lost to the bar's own, so the
/// edges never resized.
private struct SpanBar: View {
    let span: TimeSpan
    let scale: CGFloat
    let maxTime: Double
    let label: String
    let fill: Color
    let textColor: Color
    let isSelected: Bool
    let onBegin: () -> Void
    let onChange: (TimeSpan) -> Void
    let onSelect: () -> Void

    private enum DragPart {
        case start
        case end
        case body
    }

    @State private var original: TimeSpan?
    @State private var part: DragPart = .body

    var body: some View {
        let width = max(10, span.duration * scale)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.text, lineWidth: isSelected ? 2 : 0))
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
            // The edges show the resize cursor; the drag below does the resizing.
            HStack {
                edgeCursor(width: SpanBar.edgeWidth(barWidth: width))
                Spacer(minLength: 0)
                edgeCursor(width: SpanBar.edgeWidth(barWidth: width))
            }
        }
        .frame(width: width, height: 20)
        // A name the tests find the bar by, to drag it and its edges with the real mouse.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bar: \(label)")
        .accessibilityAddTraits(.isButton)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .gesture(
            // Measured on the track, which stays put: measured on the bar, which follows the
            // pointer, a move came out shorter than the drag.
            DragGesture(minimumDistance: 2, coordinateSpace: .named(SpanBar.trackSpace))
                .onChanged { value in
                    if original == nil {
                        original = span
                        part = SpanBar.part(at: value.startLocation.x - span.start * scale, barWidth: width)
                        onSelect()
                        onBegin()
                    }
                    guard let start = original else { return }
                    let delta = value.translation.width / scale
                    switch part {
                    case .start:
                        let newStart = max(0, min(start.end - 0.1, start.start + delta))
                        onChange(TimeSpan(start: newStart, end: start.end))
                    case .end:
                        let newEnd = min(maxTime, max(start.start + 0.1, start.end + delta))
                        onChange(TimeSpan(start: start.start, end: newEnd))
                    case .body:
                        var newStart = start.start + delta
                        newStart = max(0, min(maxTime - start.duration, newStart))
                        onChange(TimeSpan(start: newStart, end: newStart + start.duration))
                    }
                }
                .onEnded { _ in original = nil }
        )
        .offset(x: span.start * scale)
    }

    /// The coordinate space of the track the bars sit on.
    static let trackSpace = "spanBarTrack"

    /// How much of each end resizes: 10 pt, less on a short bar so its middle still moves it.
    static func edgeWidth(barWidth: CGFloat) -> CGFloat {
        return min(10, barWidth / 3)
    }

    private static func part(at x: CGFloat, barWidth: CGFloat) -> DragPart {
        let edge = edgeWidth(barWidth: barWidth)
        if x <= edge {
            return .start
        }
        if x >= barWidth - edge {
            return .end
        }
        return .body
    }

    private func edgeCursor(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: width)
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

/// Diagonal stripes used for cut ranges.
struct HatchedRectangle: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0E0F11, alpha: 0.6)))
            var x: CGFloat = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color.opacity(0.55)), lineWidth: 3)
                x += 8
            }
        }
    }
}
