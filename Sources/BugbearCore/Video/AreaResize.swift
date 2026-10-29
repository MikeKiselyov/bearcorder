import CoreGraphics

/// Which sides of an area a drag moves: a corner moves two, an edge one, a drag inside all four.
public struct AreaEdges: Equatable {
    public var minX: Bool
    public var minY: Bool
    public var maxX: Bool
    public var maxY: Bool

    public init(minX: Bool = false, minY: Bool = false, maxX: Bool = false, maxY: Bool = false) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// The four corners and four edge middles, in that order.
    public static let handles: [AreaEdges] = [
        AreaEdges(minX: true, minY: true),
        AreaEdges(minY: true, maxX: true),
        AreaEdges(minX: true, maxY: true),
        AreaEdges(maxX: true, maxY: true),
        AreaEdges(minX: true),
        AreaEdges(maxX: true),
        AreaEdges(minY: true),
        AreaEdges(maxY: true),
    ]

    /// All four sides: the whole area moves.
    public static let all = AreaEdges(minX: true, minY: true, maxX: true, maxY: true)

    /// What a press at `point` takes hold of: a handle within `reach` of it (corners before edges),
    /// the whole area inside it, nothing outside.
    public static func grabbed(at point: CGPoint, area: CGRect, reach: CGFloat) -> AreaEdges? {
        for edges in handles {
            let handle = edges.point(on: area)
            if hypot(point.x - handle.x, point.y - handle.y) <= reach {
                return edges
            }
        }
        if area.contains(point) {
            return .all
        }
        return nil
    }

    /// The pointer that says what a drag from here does.
    public var cursor: AreaCursor {
        if self == .all {
            return .move
        }
        let horizontal = minX || maxX
        let vertical = minY || maxY
        if horizontal && vertical {
            return .corner
        }
        if horizontal {
            return .leftRight
        }
        return .upDown
    }

    /// Where this handle sits on `area`.
    public func point(on area: CGRect) -> CGPoint {
        var x = area.midX
        var y = area.midY
        if minX { x = area.minX }
        if maxX { x = area.maxX }
        if minY { y = area.minY }
        if maxY { y = area.maxY }
        return CGPoint(x: x, y: y)
    }
}

/// The pointer over a picked area: a hand to move it, arrows on the handles, a crosshair to draw a new one.
public enum AreaCursor: Equatable {
    case move
    case leftRight
    case upDown
    case corner
    case draw

    /// For a press at `point`: what `AreaEdges.grabbed` takes hold of, or a crosshair outside.
    public static func at(_ point: CGPoint, area: CGRect, reach: CGFloat) -> AreaCursor {
        guard let edges = AreaEdges.grabbed(at: point, area: area, reach: reach) else {
            return .draw
        }
        return edges.cursor
    }
}

/// Resizing and moving a picked area by its edges: the recording area while recording and the
/// part of a clip the video editor keeps. Works in any coordinates: the area stays inside
/// `bounds` and never gets smaller than `minimum` on either side.
public enum AreaResize {
    public static func resized(_ area: CGRect, edges: AreaEdges, dx: CGFloat, dy: CGFloat, bounds: CGRect, minimum: CGFloat) -> CGRect {
        var minX = area.minX
        var minY = area.minY
        var maxX = area.maxX
        var maxY = area.maxY
        if edges.minX {
            minX = clamp(minX + dx, low: bounds.minX, high: maxX - minimum)
        }
        if edges.maxX {
            maxX = clamp(maxX + dx, low: minX + minimum, high: bounds.maxX)
        }
        if edges.minY {
            minY = clamp(minY + dy, low: bounds.minY, high: maxY - minimum)
        }
        if edges.maxY {
            maxY = clamp(maxY + dy, low: minY + minimum, high: bounds.maxY)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// A drag on what `AreaEdges.grabbed` took hold of: all four sides move the area, the others resize it.
    public static func dragged(_ area: CGRect, edges: AreaEdges, dx: CGFloat, dy: CGFloat, bounds: CGRect, minimum: CGFloat) -> CGRect {
        if edges == .all {
            return moved(area, dx: dx, dy: dy, bounds: bounds)
        }
        return resized(area, edges: edges, dx: dx, dy: dy, bounds: bounds, minimum: minimum)
    }

    /// A drag across several screens: the area stays in their bounding box and keeps a part on one
    /// of them. Between screens of different sizes part of that box is no screen; there the area
    /// slides along the edge (only across, or only up and down) instead of stopping. Nil when no
    /// part of the drag can stay on a screen.
    public static func dragged(_ area: CGRect, edges: AreaEdges, dx: CGFloat, dy: CGFloat, screens: [CGRect], minimum: CGFloat) -> CGRect? {
        var reach = CGRect.null
        for screen in screens {
            reach = reach.union(screen)
        }
        if reach.isNull {
            return nil
        }
        let tries = [(dx, dy), (dx, 0), (0, dy)]
        for (tryX, tryY) in tries {
            let candidate = dragged(area, edges: edges, dx: tryX, dy: tryY, bounds: reach, minimum: minimum)
            for screen in screens where screen.intersects(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// A size label next to the grip that moves the area: moved left when they would overlap, as
    /// on a narrow area.
    public static func label(_ label: CGRect, clearOf grip: CGRect, gap: CGFloat) -> CGRect {
        if !label.insetBy(dx: -gap, dy: -gap).intersects(grip) {
            return label
        }
        var moved = label
        moved.origin.x = grip.minX - gap - label.width
        return moved
    }

    /// The whole area shifted, stopping at the edges of `bounds`.
    public static func moved(_ area: CGRect, dx: CGFloat, dy: CGFloat, bounds: CGRect) -> CGRect {
        let x = clamp(area.minX + dx, low: bounds.minX, high: bounds.maxX - area.width)
        let y = clamp(area.minY + dy, low: bounds.minY, high: bounds.maxY - area.height)
        return CGRect(x: x, y: y, width: area.width, height: area.height)
    }

    /// The area drawn from `start` to `end`, inside `bounds`.
    public static func drawn(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect {
        let minX = clamp(min(start.x, end.x), low: bounds.minX, high: bounds.maxX)
        let maxX = clamp(max(start.x, end.x), low: bounds.minX, high: bounds.maxX)
        let minY = clamp(min(start.y, end.y), low: bounds.minY, high: bounds.maxY)
        let maxY = clamp(max(start.y, end.y), low: bounds.minY, high: bounds.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        if high < low {
            return low
        }
        return max(low, min(high, value))
    }
}

/// The part of a clip's frame that ends up in the video, in 0…1 frame coordinates with the
/// origin top-left. Marks, clicks and blur stay on the picture: they are kept in whole-frame
/// coordinates and only shown through the crop.
public enum VideoCrop {
    public static let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// A crop keeps at least this part of each side.
    public static let minimumSize: CGFloat = 0.05

    /// Nil for (almost) the whole frame, so an untouched clip has no crop.
    public static func normalized(_ crop: CGRect?) -> CGRect? {
        guard let area = crop else { return nil }
        let inside = area.intersection(whole)
        if inside.isNull || inside.width < minimumSize || inside.height < minimumSize {
            return nil
        }
        let margin: CGFloat = 0.002
        if inside.minX <= margin && inside.minY <= margin && inside.maxX >= 1 - margin && inside.maxY >= 1 - margin {
            return nil
        }
        return inside
    }

    /// A point on the cropped picture (0…1) to whole-frame coordinates.
    public static func toFrame(_ point: CGPoint, crop: CGRect) -> CGPoint {
        return CGPoint(x: crop.minX + point.x * crop.width, y: crop.minY + point.y * crop.height)
    }

    /// A whole-frame point to the cropped picture (0…1, outside it when not in the crop).
    public static func toPicture(_ point: CGPoint, crop: CGRect) -> CGPoint {
        return CGPoint(x: (point.x - crop.minX) / crop.width, y: (point.y - crop.minY) / crop.height)
    }

    public static func toPicture(_ rect: CGRect, crop: CGRect) -> CGRect {
        let origin = toPicture(rect.origin, crop: crop)
        return CGRect(x: origin.x, y: origin.y, width: rect.width / crop.width, height: rect.height / crop.height)
    }

    /// The crop in pixels of a `width` × `height` frame (origin top-left), on even numbers as
    /// video encoders want, and at least 2 × 2.
    public static func pixelRect(_ crop: CGRect, width: Int, height: Int) -> CGRect {
        var minX = evenDown(crop.minX * CGFloat(width))
        var minY = evenDown(crop.minY * CGFloat(height))
        var maxX = evenDown(crop.maxX * CGFloat(width) + 1)
        var maxY = evenDown(crop.maxY * CGFloat(height) + 1)
        maxX = min(maxX, evenDown(CGFloat(width)))
        maxY = min(maxY, evenDown(CGFloat(height)))
        minX = min(max(0, minX), maxX - 2)
        minY = min(max(0, minY), maxY - 2)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func evenDown(_ value: CGFloat) -> CGFloat {
        return CGFloat(Int(value) / 2 * 2)
    }
}

extension CGRect {
    /// A 0…1 crop moved onto the even pixels it is rendered with in a frame of `size`; unchanged
    /// for the whole frame or without a size.
    public func pixelAligned(to size: CGSize?) -> CGRect {
        guard let frame = size, frame.width > 0, frame.height > 0 else { return self }
        if self == VideoCrop.whole { return self }
        let pixels = VideoCrop.pixelRect(self, width: Int(frame.width), height: Int(frame.height))
        return CGRect(x: pixels.minX / frame.width, y: pixels.minY / frame.height, width: pixels.width / frame.width, height: pixels.height / frame.height)
    }
}
