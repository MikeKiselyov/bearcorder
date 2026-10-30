import CoreGraphics

/// A display's buffer can hold segments of two sizes: it went to native resolution in the middle of an
/// area recording and its writer started a new segment. In the clip each part of that display's picture
/// is scaled by its own size, from the clip time where it starts.
public enum SegmentSizes {
    /// One segment of the buffer, host times.
    public struct Segment: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var pixels: CGSize

        public init(start: Double, end: Double, pixels: CGSize) {
            self.start = start
            self.end = end
            self.pixels = pixels
        }
    }

    /// A kept host-time range and where it starts in the clip.
    public struct Piece: Equatable, Sendable {
        public var hostStart: Double
        public var hostEnd: Double
        public var outputStart: Double

        public init(hostStart: Double, hostEnd: Double, outputStart: Double) {
            self.hostStart = hostStart
            self.hostEnd = hostEnd
            self.outputStart = outputStart
        }
    }

    /// From `outputStart` (clip seconds) on, the picture is `pixels` big.
    public struct Span: Equatable, Sendable {
        public var outputStart: Double
        public var pixels: CGSize

        public init(outputStart: Double, pixels: CGSize) {
            self.outputStart = outputStart
            self.pixels = pixels
        }
    }

    /// Where the picture size changes in the clip, in clip order; a new span only where the size differs
    /// from the one before.
    public static func spans(segments: [Segment], pieces: [Piece]) -> [Span] {
        var parts: [Span] = []
        for piece in pieces {
            for segment in segments {
                let from = max(segment.start, piece.hostStart)
                let to = min(segment.end, piece.hostEnd)
                if to <= from {
                    continue
                }
                parts.append(Span(outputStart: piece.outputStart + (from - piece.hostStart), pixels: segment.pixels))
            }
        }
        parts.sort { first, second in first.outputStart < second.outputStart }
        var spans: [Span] = []
        for part in parts {
            if let previous = spans.last, previous.pixels == part.pixels {
                continue
            }
            spans.append(part)
        }
        return spans
    }

    /// The biggest picture among the spans (the widest), which sets the display's density in the clip.
    public static func largest(_ spans: [Span]) -> CGSize? {
        var best: CGSize?
        for span in spans {
            if let current = best, current.width >= span.pixels.width {
                continue
            }
            best = span.pixels
        }
        return best
    }
}
