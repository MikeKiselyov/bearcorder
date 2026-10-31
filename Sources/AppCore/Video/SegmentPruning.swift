/// Where a buffer segment is in its life.
public enum SegmentState: Sendable {
    /// Still being written.
    case open
    /// Closed and playable.
    case finished
    /// The writer could not finish the file (a full disk, for one). It is never used for a clip.
    case failed
}

public enum SegmentPruning {
    /// Whether a segment's file goes. A finished one goes when it ended before the window starts, an open
    /// one stays, a failed one goes at once: nothing can use it and it would pile up.
    public static func shouldRemove(state: SegmentState, end: Double, keepFrom: Double) -> Bool {
        if state == .failed {
            return true
        }
        if state == .finished {
            return end < keepFrom
        }
        return false
    }
}
