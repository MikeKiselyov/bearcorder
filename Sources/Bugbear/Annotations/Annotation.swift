import AppKit
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable, Codable {
    case select
    case arrow
    case rectangle
    case ellipse
    case line
    case highlighter
    case pen
    case text
    case step
    case blur
    case magnifier
    case crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .highlighter: return "Highlighter"
        case .pen: return "Pen"
        case .text: return "Text"
        case .step: return "Numbered step"
        case .blur: return "Blur"
        case .magnifier: return "Magnifier"
        case .crop: return "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .highlighter: return "highlighter"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .step: return "1.circle"
        case .blur: return "square.grid.3x3.fill"
        case .magnifier: return "plus.magnifyingglass"
        case .crop: return "crop"
        }
    }

    var keyboardShortcut: Character? {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .line: return "l"
        case .highlighter: return "h"
        case .pen: return "p"
        case .text: return "t"
        case .step: return "n"
        case .blur: return "b"
        case .magnifier: return "m"
        case .crop: return "c"
        }
    }
}

enum AnnotationColor: String, CaseIterable, Codable, Identifiable {
    case coral
    case yellow
    case blue
    case green
    case purple
    case white
    case black

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .coral: return NSColor(hex: 0xFF6B4A)
        case .yellow: return NSColor(hex: 0xFFC93C)
        case .blue: return NSColor(hex: 0x4C9BFF)
        case .green: return NSColor(hex: 0x3DD68C)
        case .purple: return NSColor(hex: 0x9B6BFF)
        case .white: return NSColor(hex: 0xF4F4F5)
        case .black: return NSColor(hex: 0x1C1D20)
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Outline around text drawn in this color without a label, so it stays readable.
    var outline: NSColor {
        switch self {
        case .black: return NSColor(hex: 0xF4F4F5)
        default: return NSColor(hex: 0x1A0B06)
        }
    }

    /// Text color that reads on top of this color.
    var contrastingText: NSColor {
        switch self {
        case .yellow, .white, .green: return NSColor(hex: 0x1A0B06)
        case .coral: return NSColor(hex: 0x1A0B06)
        default: return .white
        }
    }
}

/// Line thickness, thinnest first. + and - in the editor step through these.
enum StrokeSize: String, CaseIterable, Codable, Identifiable {
    case hairline
    case thin
    case medium
    case thick
    case heavy
    case huge
    case giant

    var id: String { rawValue }

    /// Base width in points; scaled by the document scale.
    var width: CGFloat {
        switch self {
        case .hairline: return 1
        case .thin: return 2
        case .medium: return 4
        case .thick: return 7
        case .heavy: return 10
        case .huge: return 14
        case .giant: return 20
        }
    }

    /// The next size up (direction 1) or down (-1), staying at the ends.
    func stepped(_ direction: Int) -> StrokeSize {
        let all = StrokeSize.allCases
        let index = all.firstIndex(of: self) ?? 0
        let next = max(0, min(all.count - 1, index + direction))
        return all[next]
    }

    static func nearest(toWidth width: CGFloat) -> StrokeSize {
        var best = StrokeSize.medium
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for size in StrokeSize.allCases {
            let distance = abs(size.width - width)
            if distance < bestDistance {
                best = size
                bestDistance = distance
            }
        }
        return best
    }
}

/// Text sizes in points before the document scale. + and - step through these.
enum TextSizes {
    static let all: [CGFloat] = [12, 14, 16, 19, 22, 26, 30, 36, 44, 54, 66, 80, 100]
    static let standard: CGFloat = 19

    static func stepped(from current: CGFloat, _ direction: Int) -> CGFloat {
        var index = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (candidate, size) in all.enumerated() {
            let distance = abs(size - current)
            if distance < bestDistance {
                index = candidate
                bestDistance = distance
            }
        }
        let next = max(0, min(all.count - 1, index + direction))
        return all[next]
    }
}

/// One drawn mark. Coordinates are in the document's space (image pixels or screen points),
/// origin top-left.
struct Annotation: Identifiable, Codable, Equatable {
    var id = UUID()
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var text: String = ""
    var number: Int = 0
    var color: AnnotationColor
    var lineWidth: CGFloat
    /// Font size for text; radius base for steps.
    var fontSize: CGFloat = 24
    /// Text without the colored label behind it. Optional so older project.json files still load.
    var clearBackground: Bool?

    /// Text drawn in the mark color with an outline, over a transparent background.
    var hasClearBackground: Bool {
        return clearBackground ?? false
    }

    var rect: CGRect {
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Area used for hit-testing and selection outlines.
    var bounds: CGRect {
        switch tool {
        case .pen, .highlighter:
            if points.isEmpty { return rect }
            var minX = points[0].x
            var minY = points[0].y
            var maxX = points[0].x
            var maxY = points[0].y
            for point in points {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
        case .step:
            let radius = stepRadius
            return CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
        case .text:
            let size = AnnotationRenderer.textSize(self)
            return CGRect(x: start.x, y: start.y, width: size.width, height: size.height)
        case .arrow, .line:
            return rect.insetBy(dx: -lineWidth * 3, dy: -lineWidth * 3)
        default:
            return rect
        }
    }

    var stepRadius: CGFloat {
        return fontSize * 0.75
    }

    mutating func move(by delta: CGSize) {
        start.x += delta.width
        start.y += delta.height
        end.x += delta.width
        end.y += delta.height
        for index in 0..<points.count {
            points[index].x += delta.width
            points[index].y += delta.height
        }
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch tool {
        case .arrow, .line:
            return AnnotationRenderer.distance(from: point, toSegment: start, end) <= max(tolerance, lineWidth * 2)
        case .pen, .highlighter:
            if points.count < 2 { return false }
            for index in 1..<points.count {
                if AnnotationRenderer.distance(from: point, toSegment: points[index - 1], points[index]) <= max(tolerance, lineWidth * 2) {
                    return true
                }
            }
            return false
        case .rectangle, .ellipse:
            // Outline shapes: hit near the border or inside small shapes.
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            if !outer.contains(point) { return false }
            if inner.width <= 0 || inner.height <= 0 { return true }
            return !inner.contains(point)
        default:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    var layerName: String {
        switch tool {
        case .text: return text.isEmpty ? "Text" : "Text · \(text.prefix(18))"
        case .step: return "Step \(number)"
        default: return tool.title
        }
    }
}

/// Saved look: color + stroke (the "style preset" in the side panel).
struct StylePreset: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var color: AnnotationColor
    var stroke: StrokeSize

    static let all: [StylePreset] = [
        StylePreset(name: "QA default", color: .coral, stroke: .medium),
        StylePreset(name: "Subtle", color: .yellow, stroke: .thin),
        StylePreset(name: "Bold", color: .coral, stroke: .thick),
        StylePreset(name: "Brand", color: .purple, stroke: .medium),
    ]
}
