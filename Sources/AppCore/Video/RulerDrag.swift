import Foundation

/// A drag on the video editor's ruler: started on the playhead it moves the playhead, started
/// elsewhere it selects a range (a click without moving just seeks). The choice is made once, at
/// the start, from where the playhead was before the drag moved it.
public struct RulerDrag {
    public enum Mode: Equatable {
        case scrub
        case select
    }

    public enum Action: Equatable {
        case seek(Double)
        case select(start: Double, end: Double)
    }

    /// How far from the playhead a drag still grabs it, in points.
    public static let playheadGrabDistance: Double = 10
    /// Moves shorter than this are a click.
    public static let clickDistance: Double = 3

    public private(set) var mode: Mode?

    public init() {}

    /// Positions in points along the ruler; `scale` is points per second.
    public mutating func changed(startX: Double, x: Double, playheadX: Double, scale: Double) -> Action {
        if mode == nil {
            if abs(startX - playheadX) <= RulerDrag.playheadGrabDistance {
                mode = .scrub
            } else {
                mode = .select
            }
        }
        let time = x / scale
        if mode == .scrub || abs(x - startX) < RulerDrag.clickDistance {
            return .seek(time)
        }
        return .select(start: startX / scale, end: time)
    }

    /// True when the drag should leave no selection behind (a scrub or a click).
    public mutating func ended(startX: Double, x: Double) -> Bool {
        let clearsSelection = mode == .scrub || abs(x - startX) < RulerDrag.clickDistance
        mode = nil
        return clearsSelection
    }
}
