import CoreGraphics

/// Which displays a recorded area touches. Only those run at native resolution while recording;
/// the others keep the buffer's resolution and frame rate.
public enum AreaDisplays {
    /// Indices of `frames` (global AppKit points) the area intersects, in order. The same rule as
    /// `AreaComposition.plan`: a display with any part in the area is in the clip.
    public static func touched(area: CGRect, frames: [CGRect]) -> [Int] {
        var indices: [Int] = []
        for (index, frame) in frames.enumerated() {
            if frame.width > 0 && frame.intersects(area) {
                indices.append(index)
            }
        }
        return indices
    }

    /// The displays to take to native resolution after the area moved: the ones it touches now that are
    /// not native yet. None when nothing is recording. The native set only grows during a recording.
    public static func toUpgrade(touched: Set<UInt32>, native: Set<UInt32>, recording: Bool) -> Set<UInt32> {
        if !recording {
            return []
        }
        return touched.subtracting(native)
    }
}
