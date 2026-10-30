/// When the screen buffer repeats, prunes and catches up. Times are host seconds (`CACurrentMediaTime`).
public enum BufferTiming {
    /// How often the idle heartbeat looks at a still screen.
    public static let heartbeatInterval: Double = 1.0
    /// A still screen gets its last frame repeated once it has had no frame for this long. A bit under
    /// the interval, so a timer firing a little early still repeats.
    public static let heartbeatIdleThreshold: Double = 0.95
    /// Old segments are looked at no more often than this, unless a segment just finished.
    public static let pruneInterval: Double = 1.0
    /// A save closer than this to the last frame needs no extra frame.
    public static let catchUpThreshold: Double = 0.05

    public static func shouldRepeat(now: Double, lastFrame: Double) -> Bool {
        return now - lastFrame >= heartbeatIdleThreshold
    }

    public static func shouldPrune(now: Double, lastPrune: Double, segmentFinished: Bool) -> Bool {
        if segmentFinished {
            return true
        }
        return now - lastPrune >= pruneInterval
    }

    /// The time to repeat the last frame at so a clip saved `now` reaches `now`, or nil when the last
    /// frame is close enough.
    public static func catchUpTime(now: Double, lastFrame: Double) -> Double? {
        if now - lastFrame > catchUpThreshold {
            return now
        }
        return nil
    }
}
