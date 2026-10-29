import Foundation
import BugbearCore

/// A timed mark on the video. Positions are normalized (0…1, origin top-left).
struct VideoOverlay: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case text
        case arrow
        case rectangle
        case blur

        var title: String {
            switch self {
            case .text: return L("video.overlay.text")
            case .arrow: return L("video.overlay.arrow")
            case .rectangle: return L("video.overlay.rectangle")
            case .blur: return L("video.overlay.blur")
            }
        }

        var symbol: String {
            switch self {
            case .text: return "textformat"
            case .arrow: return "arrow.up.right"
            case .rectangle: return "rectangle"
            case .blur: return "eye.slash"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var span: TimeSpan
    var start: CGPoint
    var end: CGPoint
    var text: String = ""
    var color: AnnotationColor = .coral
    /// Line and text size, 1 = standard. Optional so older project.json files still load.
    var scale: Double?
    /// Text without the colored label behind it. Optional so older project.json files still load.
    var clearBackground: Bool?

    /// Sizes + and - step through, from half to four times the standard size.
    static let scales: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3, 4]

    var effectiveScale: Double {
        return scale ?? 1
    }

    func steppedScale(_ direction: Int) -> Double {
        return VideoOverlay.stepped(effectiveScale, direction)
    }

    /// The size one step bigger (1) or smaller (-1) than `scale`, within `scales`.
    static func stepped(_ scale: Double, _ direction: Int) -> Double {
        var index = 2
        var bestDistance = Double.greatestFiniteMagnitude
        for (candidate, value) in VideoOverlay.scales.enumerated() {
            let distance = abs(value - scale)
            if distance < bestDistance {
                index = candidate
                bestDistance = distance
            }
        }
        let next = max(0, min(VideoOverlay.scales.count - 1, index + direction))
        return VideoOverlay.scales[next]
    }

    var rect: CGRect {
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

enum VideoExportFormat: String, CaseIterable, Identifiable, Codable {
    case mp4 = "MP4"
    case gif = "GIF"

    var id: String { rawValue }
}

enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case original = "Original"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: String { rawValue }

    /// The name in the quality menu. The raw value is saved in project.json, so it stays English.
    var title: String {
        if self == .original {
            return L("video.quality.original")
        }
        return rawValue
    }

    var maxHeight: Double? {
        switch self {
        case .original: return nil
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        }
    }
}

/// Everything the video editor can change, saved as project.json next to the clip.
struct VideoProject: Codable, Equatable {
    var timeline: EditTimeline
    var overlays: [VideoOverlay] = []
    var showClicks = true
    var showKeys = true
    var showBadge = false
    var badgeCorner: BadgeCorner = .topRight
    var format: VideoExportFormat = .mp4
    var quality: VideoQuality = .p1080
    var gifFramesPerSecond = 12
    /// MP4 size limit in MB, nil for no limit. Optional so older project.json files still load.
    var sizeLimitMB: Int?
    /// The current step ("3. Click "Pay" button") as a caption at the bottom. Optional so older
    /// project.json files still load.
    var showSteps: Bool?
    /// The part of the frame in the video (0…1, origin top-left), nil for all of it. Marks stay in
    /// whole-frame coordinates. Optional so older project.json files still load.
    var crop: CGRect?

    var isShowingSteps: Bool {
        return showSteps ?? false
    }

    init(duration: Double) {
        timeline = EditTimeline(sourceDuration: duration)
    }
}

extension VideoProject {
    /// Marks saved before the fixes: dragged off the frame, or added at the last frame and only a
    /// few microseconds long. They are put back in the frame and made a few seconds long.
    func repairingMarks() -> VideoProject {
        var fixed = self
        for index in fixed.overlays.indices {
            var overlay = fixed.overlays[index]
            var box = overlay.rect
            if overlay.kind == .text {
                box = CGRect(origin: overlay.start, size: .zero)
            }
            let shift = MarkMove.keepInside(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY, dx: 0, dy: 0)
            overlay.start = CGPoint(x: overlay.start.x + shift.dx, y: overlay.start.y + shift.dy)
            overlay.end = CGPoint(x: overlay.end.x + shift.dx, y: overlay.end.y + shift.dy)
            if overlay.span.duration < 0.1 {
                overlay.span = TimeSpan.mark(at: overlay.span.start, length: 3, inside: fixed.timeline.trim)
            }
            fixed.overlays[index] = overlay
        }
        return fixed
    }
}

extension VideoOverlay {
    /// The area text covers in 0…1 frame coordinates, growing with its words and size, for picking
    /// and moving it on the video.
    static func textBox(_ overlay: VideoOverlay) -> CGRect {
        let letters = max(4, overlay.text.count)
        let scale = max(0.5, overlay.effectiveScale)
        let width = min(0.9, (0.012 * Double(letters) + 0.03) * scale)
        let height = 0.05 * scale
        return CGRect(x: overlay.start.x, y: overlay.start.y, width: width, height: height)
    }
}
