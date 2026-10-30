import Foundation

/// Pauses of a recording in host time: what was recorded, and which ranges a clip keeps.
public struct PauseTimeline: Equatable {
    public struct Pause: Equatable {
        public var start: Double
        /// Nil while still paused.
        public var end: Double?
    }

    public let startTime: Double
    public private(set) var pauses: [Pause] = []

    public init(startTime: Double) {
        self.startTime = startTime
    }

    public var isPaused: Bool {
        if let last = pauses.last {
            return last.end == nil
        }
        return false
    }

    public mutating func pause(at time: Double) {
        if isPaused { return }
        pauses.append(Pause(start: time, end: nil))
    }

    public mutating func resume(at time: Double) {
        if !isPaused { return }
        pauses[pauses.count - 1].end = time
    }

    /// Recorded seconds, not counting pauses.
    public func elapsed(now: Double) -> Double {
        var paused = 0.0
        for pause in pauses {
            paused += (pause.end ?? now) - pause.start
        }
        return max(0, now - startTime - paused)
    }

    /// Host-time ranges to keep, in order. A pause still open at `end` keeps nothing after it.
    public func keptRanges(until end: Double) -> [(start: Double, end: Double)] {
        var ranges: [(start: Double, end: Double)] = []
        var cursor = startTime
        for pause in pauses {
            if pause.start > cursor {
                ranges.append((start: cursor, end: min(pause.start, end)))
            }
            cursor = pause.end ?? end
        }
        if end > cursor {
            ranges.append((start: cursor, end: end))
        }
        return ranges
    }
}
