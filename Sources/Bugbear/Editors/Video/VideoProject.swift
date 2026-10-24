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
            case .text: return "Text"
            case .arrow: return "Arrow"
            case .rectangle: return "Box"
            case .blur: return "Blur"
            }
        }

        var symbol: String {
            switch self {
            case .text: return "textformat"
            case .arrow: return "arrow.up.right"
            case .rectangle: return "rectangle"
            case .blur: return "square.grid.3x3.fill"
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
        var index = 2
        var bestDistance = Double.greatestFiniteMagnitude
        for (candidate, value) in VideoOverlay.scales.enumerated() {
            let distance = abs(value - effectiveScale)
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

    var id: String { rawValue }

    var maxHeight: Double? {
        switch self {
        case .original: return nil
        case .p1080: return 1080
        case .p720: return 720
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

    init(duration: Double) {
        timeline = EditTimeline(sourceDuration: duration)
    }
}
