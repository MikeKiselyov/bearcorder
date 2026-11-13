import Foundation

/// How long writing a clip may take before it counts as stuck.
public enum ExportTimeout {
    /// A short clip on a busy Mac still gets this long.
    public static let shortest: Double = 300

    /// While frames are being encoded one follows another many times a second: this long without
    /// a new frame means the encoder is stuck, whatever the clip length.
    public static let withoutAFrame: Double = 60

    /// Writing is normally faster than the clip plays; ten times its length is far beyond a slow Mac.
    public static func seconds(forClip duration: Double) -> Double {
        if !duration.isFinite { return shortest }
        return max(shortest, duration * 10)
    }
}
