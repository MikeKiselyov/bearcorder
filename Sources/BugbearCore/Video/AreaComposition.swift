import CoreGraphics

/// Where each display's picture goes in the clip of a recorded area, which may cross displays.
/// The displays keep their places as arranged in System Settings; the clip has the pixel density of
/// the sharpest display the area touches, and where the area covers no display it stays black.
public enum AreaComposition {
    public struct Source: Equatable {
        /// The display's frame, global AppKit points (origin bottom-left).
        public var frame: CGRect
        /// The size of its recorded picture in pixels.
        public var pixels: CGSize

        public init(frame: CGRect, pixels: CGSize) {
            self.frame = frame
            self.pixels = pixels
        }
    }

    public struct Placement: Equatable {
        /// Which source this is.
        public var index: Int
        /// How much the source's picture is scaled up or down to match the clip.
        public var scale: CGFloat
        /// Where the picture's top-left corner lands, pixels from the clip's top-left corner.
        public var offset: CGPoint

        public var transform: CGAffineTransform {
            CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
        }
    }

    public struct Plan: Equatable {
        /// The clip size in pixels, even on both sides for H.264.
        public var renderSize: CGSize
        /// The sources the area touches.
        public var placements: [Placement]
    }

    /// `area` in global AppKit points. Nil when the area touches no display or is too small.
    public static func plan(area: CGRect, sources: [Source]) -> Plan? {
        var touched: [Int] = []
        var outputScale: CGFloat = 0
        for (index, source) in sources.enumerated() {
            if source.frame.width <= 0 || !source.frame.intersects(area) {
                continue
            }
            touched.append(index)
            let scale = source.pixels.width / source.frame.width
            if scale > outputScale {
                outputScale = scale
            }
        }
        if outputScale <= 0 {
            return nil
        }
        let width = (area.width * outputScale / 2).rounded(.down) * 2
        let height = (area.height * outputScale / 2).rounded(.down) * 2
        if width < 2 || height < 2 {
            return nil
        }
        var placements: [Placement] = []
        for index in touched {
            let source = sources[index]
            let ownScale = source.pixels.width / source.frame.width
            // The clip counts from the area's top-left corner; global points count from the bottom.
            let x = ((source.frame.minX - area.minX) * outputScale).rounded()
            let y = ((area.maxY - source.frame.maxY) * outputScale).rounded()
            placements.append(Placement(index: index, scale: outputScale / ownScale, offset: CGPoint(x: x, y: y)))
        }
        return Plan(renderSize: CGSize(width: width, height: height), placements: placements)
    }

    /// Where a global point (origin bottom-left) lands in the clip, normalized with the origin at the
    /// top-left; nil outside the area.
    public static func normalizedPoint(_ point: CGPoint, area: CGRect) -> CGPoint? {
        if area.width <= 0 || area.height <= 0 || !area.contains(point) {
            return nil
        }
        return CGPoint(x: (point.x - area.minX) / area.width, y: (area.maxY - point.y) / area.height)
    }

    /// The display an area mostly lies on: the one it covers the most of, the first on a tie.
    public static func mainDisplay(of area: CGRect, frames: [CGRect]) -> Int? {
        var best: Int?
        var bestCovered: CGFloat = 0
        for (index, frame) in frames.enumerated() {
            let overlap = frame.intersection(area)
            if overlap.isNull {
                continue
            }
            let covered = overlap.width * overlap.height
            if best == nil || covered > bestCovered {
                best = index
                bestCovered = covered
            }
        }
        return best
    }
}
