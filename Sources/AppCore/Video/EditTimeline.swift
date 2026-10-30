import Foundation

public struct TimeSpan: Equatable, Codable, Hashable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public var duration: Double { end - start }

    public func contains(_ time: Double) -> Bool {
        return time >= start && time < end
    }

    /// A new mark of `length` seconds at the playhead, inside `area` (the part of the clip that is
    /// kept). Near the end it starts earlier: a mark added at the last frame came out a few
    /// microseconds long and never showed.
    public static func mark(at playhead: Double, length: Double, inside area: TimeSpan) -> TimeSpan {
        let markLength = min(length, area.duration)
        var start = max(area.start, min(playhead, area.end))
        if start + markLength > area.end {
            start = area.end - markLength
        }
        return TimeSpan(start: start, end: start + markLength)
    }
}

/// Moving a mark on the video, in 0…1 coordinates of the frame.
public enum MarkMove {
    /// The shift that keeps the mark's box (`minX`…`maxX`, `minY`…`maxY`) inside the frame: a mark
    /// dragged past the edge stops there instead of leaving the picture.
    public static func keepInside(minX: Double, minY: Double, maxX: Double, maxY: Double, dx: Double, dy: Double) -> (dx: Double, dy: Double) {
        var shiftX = dx
        var shiftY = dy
        if minX + shiftX < 0 {
            shiftX = -minX
        }
        if maxX + shiftX > 1 {
            shiftX = 1 - maxX
        }
        if minY + shiftY < 0 {
            shiftY = -minY
        }
        if maxY + shiftY > 1 {
            shiftY = 1 - maxY
        }
        return (dx: shiftX, dy: shiftY)
    }
}

public struct SpeedEdit: Equatable, Codable, Hashable {
    public var span: TimeSpan
    /// 0.5 means half speed (slow motion).
    public var factor: Double

    public init(span: TimeSpan, factor: Double) {
        self.span = span
        self.factor = factor
    }
}

public struct FreezeEdit: Equatable, Codable, Hashable {
    public var at: Double
    public var duration: Double

    public init(at: Double, duration: Double) {
        self.at = at
        self.duration = duration
    }
}

/// One continuous piece of the output video.
public struct TimelinePiece: Equatable, Sendable {
    public var sourceStart: Double
    public var sourceDuration: Double
    public var outputStart: Double
    public var outputDuration: Double
    public var isFreeze: Bool

    public var outputEnd: Double { outputStart + outputDuration }
    public var sourceEnd: Double { sourceStart + sourceDuration }
}

/// The non-overlay edits of a clip: trim, cuts, speed changes and freeze frames.
/// All times are in seconds on the source clip.
public struct EditTimeline: Equatable, Codable {
    public var sourceDuration: Double
    public var trim: TimeSpan
    public var cuts: [TimeSpan]
    public var speeds: [SpeedEdit]
    public var freezes: [FreezeEdit]
    public var frameDuration: Double

    public init(sourceDuration: Double, frameDuration: Double = 1.0 / 30.0) {
        self.sourceDuration = sourceDuration
        self.trim = TimeSpan(start: 0, end: sourceDuration)
        self.cuts = []
        self.speeds = []
        self.freezes = []
        self.frameDuration = frameDuration
    }

    func isCut(_ time: Double) -> Bool {
        for cut in cuts where cut.contains(time) {
            return true
        }
        return false
    }

    func speed(at time: Double) -> Double {
        // Later edits win when they overlap.
        var factor = 1.0
        for edit in speeds where edit.span.contains(time) {
            factor = edit.factor
        }
        return factor
    }

    public func pieces() -> [TimelinePiece] {
        var boundaries: [Double] = [trim.start, trim.end]
        for cut in cuts {
            boundaries.append(cut.start)
            boundaries.append(cut.end)
        }
        for edit in speeds {
            boundaries.append(edit.span.start)
            boundaries.append(edit.span.end)
        }
        for freeze in freezes {
            boundaries.append(freeze.at)
        }
        var points: [Double] = []
        for boundary in boundaries.sorted() {
            if boundary < trim.start || boundary > trim.end { continue }
            if let last = points.last, abs(last - boundary) < 0.0005 { continue }
            points.append(boundary)
        }

        var result: [TimelinePiece] = []
        var outputTime = 0.0
        var usedFreezes: [Int] = []

        func addFreezes(at time: Double) {
            for (index, freeze) in freezes.enumerated() {
                if usedFreezes.contains(index) { continue }
                if abs(freeze.at - time) > 0.0005 { continue }
                if freeze.duration <= 0 || isCut(time) { continue }
                usedFreezes.append(index)
                var frameStart = time
                // A freeze at the very end shows the last frame.
                if frameStart + frameDuration > sourceDuration {
                    frameStart = max(0, sourceDuration - frameDuration)
                }
                let piece = TimelinePiece(sourceStart: frameStart, sourceDuration: frameDuration, outputStart: outputTime, outputDuration: freeze.duration, isFreeze: true)
                result.append(piece)
                outputTime += freeze.duration
            }
        }

        if points.count < 2 {
            return result
        }
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            addFreezes(at: start)
            let middle = (start + end) / 2
            if isCut(middle) { continue }
            let factor = speed(at: middle)
            let sourceLength = end - start
            let outputLength = sourceLength / factor
            let piece = TimelinePiece(sourceStart: start, sourceDuration: sourceLength, outputStart: outputTime, outputDuration: outputLength, isFreeze: false)
            result.append(piece)
            outputTime += outputLength
        }
        addFreezes(at: points[points.count - 1])
        return result
    }

    public var outputDuration: Double {
        var total = 0.0
        for piece in pieces() {
            total += piece.outputDuration
        }
        return total
    }

    public var hasEdits: Bool {
        let trimmed = trim.start > 0.001 || trim.end < sourceDuration - 0.001
        return trimmed || !cuts.isEmpty || !speeds.isEmpty || !freezes.isEmpty
    }
}

/// Maps between output time and source time for a list of pieces.
public struct TimeMap: Sendable {
    public let pieces: [TimelinePiece]

    public init(pieces: [TimelinePiece]) {
        self.pieces = pieces
    }

    public func sourceTime(forOutput time: Double) -> Double {
        guard let last = pieces.last else { return time }
        for piece in pieces {
            if time >= piece.outputStart && time < piece.outputEnd {
                if piece.isFreeze { return piece.sourceStart }
                let progress = (time - piece.outputStart) / piece.outputDuration
                return piece.sourceStart + progress * piece.sourceDuration
            }
        }
        if time < 0 { return pieces[0].sourceStart }
        return last.sourceEnd
    }

    /// Output time for a source time. Times inside cuts snap to the next kept piece.
    public func outputTime(forSource time: Double) -> Double {
        for piece in pieces where !piece.isFreeze {
            if time >= piece.sourceStart && time < piece.sourceEnd {
                let progress = (time - piece.sourceStart) / piece.sourceDuration
                return piece.outputStart + progress * piece.outputDuration
            }
        }
        for piece in pieces where !piece.isFreeze {
            if piece.sourceStart >= time {
                return piece.outputStart
            }
        }
        return pieces.last?.outputEnd ?? time
    }

    /// Whether a source time survives the edit (is not trimmed away or cut).
    public func isVisible(source time: Double) -> Bool {
        for piece in pieces where time >= piece.sourceStart && time <= piece.sourceEnd {
            return true
        }
        return false
    }
}
