import AppKit
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable, Codable {
    case select
    case arrow
    /// An arrow with a note at its tail: drag to the problem, then type what is wrong.
    case callout
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
    /// A picture placed on the screenshot (pasted, dropped or picked). Not a drawing tool.
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return L("annotations.tool.select")
        case .arrow: return L("annotations.tool.arrow")
        case .callout: return L("annotations.tool.callout")
        case .rectangle: return L("annotations.tool.rectangle")
        case .ellipse: return L("annotations.tool.ellipse")
        case .line: return L("annotations.tool.line")
        case .highlighter: return L("annotations.tool.highlighter")
        case .pen: return L("annotations.tool.pen")
        case .text: return L("annotations.tool.text")
        case .step: return L("annotations.tool.step")
        case .blur: return L("annotations.tool.blur")
        case .magnifier: return L("annotations.tool.magnifier")
        case .crop: return L("annotations.tool.crop")
        case .image: return L("annotations.tool.image")
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .callout: return ToolIcon.arrowWithText
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .highlighter: return "highlighter"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .step: return "1.circle"
        case .blur: return "eye.slash"
        case .magnifier: return "plus.magnifyingglass"
        case .crop: return "crop"
        case .image: return "photo"
        }
    }

    /// What the tool is for, for tooltips.
    var purpose: String {
        switch self {
        case .select: return L("annotations.tool.select.purpose")
        case .arrow: return L("annotations.tool.arrow.purpose")
        case .callout: return L("annotations.tool.callout.purpose")
        case .rectangle: return L("annotations.tool.rectangle.purpose")
        case .ellipse: return L("annotations.tool.ellipse.purpose")
        case .line: return L("annotations.tool.line.purpose")
        case .highlighter: return L("annotations.tool.highlighter.purpose")
        case .pen: return L("annotations.tool.pen.purpose")
        case .text: return L("annotations.tool.text.purpose")
        case .step: return L("annotations.tool.step.purpose")
        case .blur: return L("annotations.tool.blur.purpose")
        case .magnifier: return L("annotations.tool.magnifier.purpose")
        case .crop: return L("annotations.tool.crop.purpose")
        case .image: return L("annotations.tool.image.purpose")
        }
    }

    /// The tool buttons of the screenshot editor, in order.
    static let screenshotEditorTools: [AnnotationTool] = [.select, .arrow, .callout, .rectangle, .ellipse, .line, .highlighter, .pen, .text, .step, .blur, .magnifier, .crop]

    /// Marks with a text label: text, and the arrow with text. Their size is the text size and
    /// their fill is the label behind the text.
    var hasLabel: Bool {
        return self == .text || self == .callout
    }

    var keyboardShortcut: Character? {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .callout: return "k"
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
        case .image: return nil
        }
    }
}

/// A mark color: one of the palette colors or any color picked in the color panel.
/// Saved as the palette name ("coral") or as "#RRGGBB" for a picked color, so older projects load.
struct AnnotationColor: Codable, Hashable, Identifiable {
    var hex: UInt32

    static let coral = AnnotationColor(hex: 0xFF6B4A)
    static let yellow = AnnotationColor(hex: 0xFFC93C)
    static let blue = AnnotationColor(hex: 0x4C9BFF)
    static let green = AnnotationColor(hex: 0x3DD68C)
    static let purple = AnnotationColor(hex: 0x9B6BFF)
    static let white = AnnotationColor(hex: 0xF4F4F5)
    static let black = AnnotationColor(hex: 0x1C1D20)

    /// The swatches in the editors, in order.
    static let palette: [AnnotationColor] = [.coral, .yellow, .blue, .green, .purple, .white, .black]
    private static let paletteNames = ["coral", "yellow", "blue", "green", "purple", "white", "black"]

    var id: UInt32 { hex }

    /// The palette name, or "#RRGGBB" for a picked color.
    var name: String {
        for (index, color) in AnnotationColor.palette.enumerated() where color == self {
            return AnnotationColor.paletteNames[index]
        }
        return String(format: "#%06X", hex)
    }

    /// The same as `name`, for code that still reads it like the old enum.
    var rawValue: String { name }

    var isInPalette: Bool {
        return AnnotationColor.palette.contains(self)
    }

    init(hex: UInt32) {
        self.hex = hex
    }

    /// A color picked in the color panel, rounded to 8 bits per channel.
    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? NSColor(hex: 0xFF6B4A)
        let red = UInt32((srgb.redComponent * 255).rounded())
        let green = UInt32((srgb.greenComponent * 255).rounded())
        let blue = UInt32((srgb.blueComponent * 255).rounded())
        self.hex = (red << 16) | (green << 8) | blue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.hex = AnnotationColor.coral.hex
        if value.hasPrefix("#"), let parsed = UInt32(value.dropFirst(), radix: 16) {
            self.hex = parsed
            return
        }
        for (index, name) in AnnotationColor.paletteNames.enumerated() where name == value {
            self.hex = AnnotationColor.palette[index].hex
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    var nsColor: NSColor { NSColor(hex: hex) }

    var color: Color { Color(nsColor: nsColor) }

    /// How light the color looks, 0 (black) to 1 (white).
    private var brightness: CGFloat {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return red * 0.299 + green * 0.587 + blue * 0.114
    }

    /// Outline around text drawn in this color without a label, so it stays readable.
    var outline: NSColor {
        if brightness < 0.25 {
            return NSColor(hex: 0xF4F4F5)
        }
        return NSColor(hex: 0x1A0B06)
    }

    /// Text color that reads on top of this color.
    var contrastingText: NSColor {
        if self == .coral || self == .yellow || self == .white || self == .green {
            return NSColor(hex: 0x1A0B06)
        }
        if isInPalette {
            return .white
        }
        if brightness > 0.6 {
            return NSColor(hex: 0x1A0B06)
        }
        return .white
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

    /// Rectangles and ellipses filled with a see-through tint of their color. Optional so older
    /// project.json files still load.
    var fill: Bool?

    var isFilled: Bool {
        return fill ?? false
    }

    /// The picture file of an image mark, saved next to the screenshot.
    var imagePath: String?

    /// The picture's area, for an arrow with text: its note is kept inside it, also when the arrow
    /// starts at an edge. Optional so older project.json files still load.
    var labelArea: CGRect?

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
        case .callout:
            return rect.insetBy(dx: -lineWidth * 3, dy: -lineWidth * 3).union(AnnotationRenderer.calloutLabelBox(self))
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
        case .callout:
            if AnnotationRenderer.calloutLabelBox(self).insetBy(dx: -tolerance, dy: -tolerance).contains(point) {
                return true
            }
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
            // Outline shapes: hit near the border or inside small shapes. Filled ones anywhere inside.
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            if isFilled {
                return outer.contains(point)
            }
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
        case .text: return text.isEmpty ? L("annotations.tool.text") : L("annotations.layer.text", String(text.prefix(18)))
        case .callout: return text.isEmpty ? L("annotations.tool.callout") : L("annotations.layer.callout", String(text.prefix(18)))
        case .step: return L("annotations.layer.step", number)
        default: return tool.title
        }
    }
}
