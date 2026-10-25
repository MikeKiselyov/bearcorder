import CoreGraphics

/// Which captured frames are worth encoding. While Bugbear's own windows are on screen, macOS keeps
/// redrawing our menu bar item and the recording bar, and ScreenCaptureKit sends 20-30 frames a
/// second of an otherwise still screen. Frames that changed only in such quiet zones (the menu bar,
/// the area under the recording bar) are encoded at most a few times a second, so the menu bar
/// clock still moves in the video but the encoder is not kept busy for nothing.
public enum FramePacing {
    /// Frames changed only inside quiet zones are encoded at most this often.
    public static let quietInterval: Double = 0.4

    /// True when every changed rect is covered by the zones together (a change across the menu bar
    /// and the recording bar right under it counts). An empty list means ScreenCaptureKit did not say
    /// what changed, so it does not count as quiet.
    public static func changedOnlyIn(_ zones: [CGRect], dirty: [CGRect]) -> Bool {
        if dirty.isEmpty || zones.isEmpty {
            return false
        }
        for rect in dirty {
            if !isCovered(rect, by: zones) {
                return false
            }
        }
        return true
    }

    /// Whether the zones together cover `rect`: what is left after cutting each zone out is nothing.
    static func isCovered(_ rect: CGRect, by zones: [CGRect]) -> Bool {
        var left: [CGRect] = [rect]
        for zone in zones {
            // Dirty rects come with fractions of a point; a point of slack keeps them inside.
            let cutter = zone.insetBy(dx: -1, dy: -1)
            var next: [CGRect] = []
            for piece in left {
                for part in subtract(cutter, from: piece) {
                    next.append(part)
                }
            }
            left = next
            if left.isEmpty {
                return true
            }
        }
        return left.isEmpty
    }

    /// The parts of `rect` outside `cutter`: up to four rects (above, below, left, right).
    static func subtract(_ cutter: CGRect, from rect: CGRect) -> [CGRect] {
        let overlap = rect.intersection(cutter)
        if overlap.isNull || overlap.isEmpty {
            return [rect]
        }
        var parts: [CGRect] = []
        if overlap.minY > rect.minY {
            parts.append(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY))
        }
        if overlap.maxY < rect.maxY {
            parts.append(CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY))
        }
        if overlap.minX > rect.minX {
            parts.append(CGRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height))
        }
        if overlap.maxX < rect.maxX {
            parts.append(CGRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height))
        }
        return parts
    }

    /// The area around the recording bar that macOS redraws with it (the bar and its shadow), on its
    /// own screen. Global AppKit points.
    public static func recordingBarZone(barFrame: CGRect, screenFrame: CGRect) -> CGRect {
        return barFrame.insetBy(dx: -32, dy: -32).intersection(screenFrame)
    }

    /// A point in global AppKit points as a point in the captured frame's pixels, nil when it is not
    /// on this display.
    public static func pixelPoint(_ point: CGPoint, displayFrame: CGRect, outputSize: CGSize) -> CGPoint? {
        if displayFrame.width <= 0 || displayFrame.height <= 0 {
            return nil
        }
        // Edges count: the pointer at the very top of the screen is at maxY.
        if point.x < displayFrame.minX || point.x > displayFrame.maxX || point.y < displayFrame.minY || point.y > displayFrame.maxY {
            return nil
        }
        let x = (point.x - displayFrame.minX) * outputSize.width / displayFrame.width
        let y = (displayFrame.maxY - point.y) * outputSize.height / displayFrame.height
        return CGPoint(x: x, y: y)
    }

    /// Whether to encode a frame that changed in `dirty`, the last encoded frame being at `lastKept`.
    public static func shouldKeep(dirty: [CGRect], quietZones: [CGRect], now: Double, lastKept: Double) -> Bool {
        if !changedOnlyIn(quietZones, dirty: dirty) {
            return true
        }
        return now - lastKept >= quietInterval
    }

    /// Quiet zones of one display in the captured frame's pixels (origin top-left), which is how
    /// ScreenCaptureKit reports changed rects.
    /// - displayFrame: the display in global AppKit points (origin bottom-left).
    /// - menuBarHeight: in points, 0 when the menu bar hides itself.
    /// - busyWindows: our windows that redraw on their own, global AppKit points.
    /// - outputSize: the captured frame in pixels, which can be scaled from the display's points.
    public static func zones(displayFrame: CGRect, menuBarHeight: CGFloat, busyWindows: [CGRect], outputSize: CGSize) -> [CGRect] {
        if displayFrame.width <= 0 || displayFrame.height <= 0 {
            return []
        }
        var local: [CGRect] = []
        if menuBarHeight > 0 {
            local.append(CGRect(x: 0, y: 0, width: displayFrame.width, height: menuBarHeight))
        }
        let bounds = CGRect(origin: .zero, size: displayFrame.size)
        for window in busyWindows {
            let flipped = CGRect(x: window.minX - displayFrame.minX, y: displayFrame.maxY - window.maxY, width: window.width, height: window.height)
            let visible = flipped.intersection(bounds)
            if !visible.isNull && !visible.isEmpty {
                local.append(visible)
            }
        }
        let scaleX = outputSize.width / displayFrame.width
        let scaleY = outputSize.height / displayFrame.height
        var pixels: [CGRect] = []
        for zone in local {
            pixels.append(CGRect(x: zone.minX * scaleX, y: zone.minY * scaleY, width: zone.width * scaleX, height: zone.height * scaleY))
        }
        return pixels
    }
}

/// Holds back frames that changed only in quiet zones, and gives the newest held one back once it is
/// due, so the last change before the screen goes still always ends up in the video.
public struct FramePacer {
    public enum Action: Equatable {
        case encode
        case hold
    }

    public var zones: [CGRect] = []
    /// Time of the newest frame held back, nil when none is.
    public private(set) var heldTime: Double?

    public init() {}

    /// Forgets the held frame, e.g. when the capture stopped.
    public mutating func reset() {
        heldTime = nil
    }

    /// A new frame at `time` that changed in `dirty`; `lastKept` is the last encoded frame. `pointer`
    /// is the mouse in frame pixels: while it is in a quiet zone, the person is working there (the
    /// address bar, a menu), so every frame counts.
    public mutating func receive(dirty: [CGRect], at time: Double, lastKept: Double, pointer: CGPoint? = nil) -> Action {
        var pointerInZone = false
        if let point = pointer {
            for zone in zones where zone.insetBy(dx: -24, dy: -24).contains(point) {
                pointerInZone = true
            }
        }
        if pointerInZone || FramePacing.shouldKeep(dirty: dirty, quietZones: zones, now: time, lastKept: lastKept) {
            heldTime = nil
            return .encode
        }
        heldTime = time
        return .hold
    }

    /// The held frame's time when it should be encoded now: `quietInterval` after the last encoded
    /// frame, or at once with `force` (before saving a clip). Nil when nothing is due.
    public mutating func takeHeld(now: Double, lastKept: Double, force: Bool) -> Double? {
        guard let held = heldTime else { return nil }
        if held <= lastKept {
            heldTime = nil
            return nil
        }
        if force || now - lastKept >= FramePacing.quietInterval {
            heldTime = nil
            return held
        }
        return nil
    }
}
