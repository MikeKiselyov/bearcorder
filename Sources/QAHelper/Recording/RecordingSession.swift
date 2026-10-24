import Foundation
import Observation
import QuartzCore

/// An explicit recording ("record from now") on top of the rolling buffer, with pauses.
/// The buffer keeps every segment from `startTime` on; stopping exports only the
/// non-paused ranges.
@MainActor
@Observable
final class RecordingSession {
    enum State {
        case recording
        case paused
    }

    private(set) var state: State = .recording
    let startTime: Double
    private(set) var pauses: [(start: Double, end: Double?)] = []

    init(startTime: Double = CACurrentMediaTime()) {
        self.startTime = startTime
    }

    var isPaused: Bool {
        return state == .paused
    }

    func pause() {
        if state == .paused { return }
        pauses.append((start: CACurrentMediaTime(), end: nil))
        state = .paused
    }

    func resume() {
        if state == .recording { return }
        if let last = pauses.indices.last {
            pauses[last].end = CACurrentMediaTime()
        }
        state = .recording
    }

    func togglePause() {
        if state == .paused {
            resume()
        } else {
            pause()
        }
    }

    /// Recorded seconds, not counting pauses.
    func elapsed(now: Double = CACurrentMediaTime()) -> Double {
        var paused = 0.0
        for pause in pauses {
            paused += (pause.end ?? now) - pause.start
        }
        return max(0, now - startTime - paused)
    }

    /// Host-time ranges to keep, in order.
    func keptRanges(until end: Double) -> [(start: Double, end: Double)] {
        var ranges: [(start: Double, end: Double)] = []
        var cursor = startTime
        for pause in pauses {
            if pause.start > cursor {
                ranges.append((start: cursor, end: pause.start))
            }
            cursor = pause.end ?? end
        }
        if end > cursor {
            ranges.append((start: cursor, end: end))
        }
        return ranges
    }
}

enum TimeFormat {
    /// "1:05" or "12:03.4" style durations.
    static func clock(_ seconds: Double, tenths: Bool = false) -> String {
        let safe = max(0, seconds)
        let minutes = Int(safe) / 60
        let remaining = safe - Double(minutes * 60)
        if tenths {
            return String(format: "%d:%04.1f", minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, Int(remaining))
    }

    static func clockPrecise(_ seconds: Double) -> String {
        let safe = max(0, seconds)
        let minutes = Int(safe) / 60
        let remaining = safe - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, remaining)
    }
}
