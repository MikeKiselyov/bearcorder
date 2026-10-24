import Foundation

/// Picks an encoder bitrate so an exported clip fits a file size limit (e.g. a 10 MB ticket attachment).
public enum SizeBudget {
    public static let audioBitrate = 160_000
    /// Share of the limit given to audio and video; the rest is container overhead and encoder overshoot.
    static let usableShare = 0.9
    static let minimumVideoBitrate = 250_000
    /// Below this, 1080p looks worse than a sharp 720p.
    static let fullHDMinimumBitrate = 2_500_000

    /// Average video bitrate in bits per second for a clip of `duration` seconds to fit `limitMB` (decimal megabytes).
    public static func videoBitrate(limitMB: Int, duration: Double, hasAudio: Bool) -> Int {
        if duration <= 0 {
            return minimumVideoBitrate
        }
        let totalBits = Double(limitMB) * 1_000_000 * 8 * usableShare
        var bitrate = totalBits / duration
        if hasAudio {
            bitrate -= Double(audioBitrate)
        }
        return max(minimumVideoBitrate, Int(bitrate))
    }

    /// Highest output height that still looks good at `bitrate`, or nil to keep the source size.
    public static func maxHeight(forVideoBitrate bitrate: Int) -> Double? {
        if bitrate < fullHDMinimumBitrate {
            return 720
        }
        return nil
    }

    /// True when even the lowest bitrate cannot fit the clip, so the user should trim it.
    public static func cannotFit(limitMB: Int, duration: Double, hasAudio: Bool) -> Bool {
        let totalBits = Double(limitMB) * 1_000_000 * 8 * usableShare
        var needed = Double(minimumVideoBitrate) * duration
        if hasAudio {
            needed += Double(audioBitrate) * duration
        }
        return needed > totalBits
    }
}
