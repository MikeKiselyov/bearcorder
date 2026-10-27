import BugbearCore
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
    private(set) var timeline: PauseTimeline

    var startTime: Double {
        return timeline.startTime
    }

    init(startTime: Double = CACurrentMediaTime()) {
        timeline = PauseTimeline(startTime: startTime)
    }

    var isPaused: Bool {
        return state == .paused
    }

    func pause(at time: Double = CACurrentMediaTime()) {
        if state == .paused { return }
        timeline.pause(at: time)
        state = .paused
    }

    func resume(at time: Double = CACurrentMediaTime()) {
        if state == .recording { return }
        timeline.resume(at: time)
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
        return timeline.elapsed(now: now)
    }

    /// Host-time ranges to keep, in order.
    func keptRanges(until end: Double) -> [(start: Double, end: Double)] {
        return timeline.keptRanges(until: end)
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
