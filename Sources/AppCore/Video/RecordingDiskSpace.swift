/// A recording keeps every segment, so a long one can fill the disk. A full disk fails the writer and
/// the clip gets holes, or nothing at all: the recording stops by itself while there is still room.
public enum RecordingDiskSpace {
    /// Room that stays free on top of what saving needs.
    public static let minimumFreeBytes: Int64 = 1_000_000_000

    /// Saving writes the clip next to the recorded pieces before they go, so it needs about as much
    /// room as what was recorded so far.
    public static func shouldStop(freeBytes: Int64, recordedBytes: Int64) -> Bool {
        return freeBytes < recordedBytes + minimumFreeBytes
    }
}
