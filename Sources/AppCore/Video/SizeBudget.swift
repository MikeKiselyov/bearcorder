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

    /// Bits per pixel per frame for the quality presets; plenty for sharp screen text.
    static let presetBitsPerPixel = 0.15
    static let presetFramesPerSecond = 30.0
    static let presetMinimumBitrate = 1_000_000
    static let presetMaximumBitrate = 25_000_000

    /// Output size and video bitrate of a quality preset: the height capped at `maxHeight` (nil
    /// keeps the source), even dimensions, and a bitrate that follows the picture size.
    public static func preset(sourceWidth: Double, sourceHeight: Double, maxHeight: Double?) -> (width: Int, height: Int, videoBitrate: Int) {
        var width = sourceWidth
        var height = sourceHeight
        if let limit = maxHeight, height > limit {
            width = width * limit / height
            height = limit
        }
        let evenWidth = max(2, Int(width / 2) * 2)
        let evenHeight = max(2, Int(height / 2) * 2)
        var bitrate = Int(Double(evenWidth * evenHeight) * presetFramesPerSecond * presetBitsPerPixel)
        bitrate = max(presetMinimumBitrate, min(presetMaximumBitrate, bitrate))
        return (width: evenWidth, height: evenHeight, videoBitrate: bitrate)
    }

    /// The bitrate the encoder will really use for a re-encoded clip: what the source needed per
    /// pixel (a still screen needs little, scrolling and video much more) scaled to the output size,
    /// with some margin, and never more than the preset's target.
    public static func expectedVideoBitrate(presetBitrate: Int, sourceBitsPerPixelSecond: Double?, width: Int, height: Int) -> Int {
        guard let perPixel = sourceBitsPerPixelSecond, perPixel > 0 else { return presetBitrate }
        let needed = perPixel * Double(width * height) * 1.3
        let floor = 150_000.0
        return Int(min(Double(presetBitrate), max(floor, needed)))
    }

    /// Expected file size in bytes. Encoders treat the bitrate as an average target, and a mostly
    /// still screen often comes out smaller.
    public static func estimatedBytes(videoBitrate: Int, duration: Double, hasAudio: Bool) -> Double {
        var bitsPerSecond = Double(videoBitrate)
        if hasAudio {
            bitsPerSecond += Double(audioBitrate)
        }
        return bitsPerSecond * max(0, duration) / 8
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
