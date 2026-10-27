import Foundation

/// Groups key presses that type into runs: one run per field until a pause, a click or a key that
/// does not type. A run keeps the time it started, which is when its step happens.
public struct TypingRuns {
    /// Typing after a pause this long starts a new run.
    public static let pause: Double = 1.5

    public struct Run: Equatable {
        public var id: Int
        public var start: Double
        public var lastKey: Double
    }

    public private(set) var current: Run?
    private var nextID = 1

    public init() {}

    /// A key that types, at `time`. Returns the run it belongs to and whether it starts a new one.
    public mutating func typed(at time: Double) -> (run: Run, isNew: Bool) {
        if var run = current, time - run.lastKey < TypingRuns.pause {
            run.lastKey = time
            current = run
            return (run: run, isNew: false)
        }
        let run = Run(id: nextID, start: time, lastKey: time)
        nextID += 1
        current = run
        return (run: run, isNew: true)
    }

    /// A click or a key that does not type ends the run. Returns the run that ended, if any.
    public mutating func interrupted() -> Run? {
        let ended = current
        current = nil
        return ended
    }
}
