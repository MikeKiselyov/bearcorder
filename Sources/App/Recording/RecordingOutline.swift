import AppKit
import AppCore

/// While recording, shows what ends up in the video: a solid frame around the recorded area or screen,
/// and a dim veil with "Not recorded" over everything else (outside the area, other displays).
/// These are our own windows, which the capture excludes, so none of this is in the video.
/// A picked area has handles on its corners and edges: drag one to make the area bigger or smaller
/// while recording, or drag the grip above the frame to move the whole area, onto another display or
/// across two. The video gets the area as it is when the recording stops. Clicks inside the area
/// still go to the apps under it.
@MainActor
final class RecordingOutline {
    private var windows: [NSPanel] = []
    private var handles: [NSPanel] = []
    private var grip: NSPanel?
    /// The picked area (global, bottom-left), nil when whole screens are recorded.
    private var area: CGRect = .zero
    private var hasArea = false
    /// Every screen's veil, which shows the part of the area on that screen.
    private var screenViews: [(frame: CGRect, view: RecordingOutlineView)] = []
    /// The area was resized: the new global rect (origin bottom-left).
    var onAreaChange: ((CGRect) -> Void)?
    /// The area never gets smaller than this, in points.
    static let minimumSide: CGFloat = 40

    /// `region` is the picked area (nil for whole screens); `recordedDisplays` are the captured displays.
    func show(region: RegionSelector.Selection?, recordedDisplays: Set<CGDirectDisplayID>) {
        hide()
        if let selected = region {
            area = selected.global
            hasArea = true
        }
        for screen in NSScreen.screens {
            let view = RecordingOutlineView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.pixelScale = screen.backingScaleFactor
            let displayID = AppState.displayID(of: screen)
            if hasArea {
                screenViews.append((frame: screen.frame, view: view))
            } else if recordedDisplays.contains(displayID) {
                view.recordedRect = CGRect(origin: .zero, size: screen.frame.size)
            }
            let window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }
        if hasArea {
            showArea()
            showHandles()
        }
    }

    /// Each screen shows the part of the area on it; a screen the area is not on is dimmed as not recorded.
    private func showArea() {
        var clipScale: CGFloat = 0
        for item in screenViews where item.frame.intersects(area) {
            clipScale = max(clipScale, item.view.pixelScale)
        }
        // One size label, on the screen with the area's top-left corner, or the one most of it is on.
        var labelIndex = AreaComposition.mainDisplay(of: area, frames: screenFrames)
        for (index, item) in screenViews.enumerated() where item.frame.contains(CGPoint(x: area.minX, y: area.maxY - 1)) {
            labelIndex = index
        }
        for (index, item) in screenViews.enumerated() {
            if item.frame.intersects(area) {
                // Global (bottom-left) rect to this window's coordinates.
                item.view.recordedRect = area.offsetBy(dx: -item.frame.minX, dy: -item.frame.minY)
                item.view.labelScale = clipScale
                item.view.showsLabel = index == labelIndex
            } else {
                item.view.recordedRect = nil
            }
            item.view.needsDisplay = true
        }
    }

    private var screenFrames: [CGRect] {
        var frames: [CGRect] = []
        for item in screenViews {
            frames.append(item.frame)
        }
        return frames
    }

    private func showHandles() {
        for edges in AreaEdges.handles {
            handles.append(handlePanel(edges: edges, size: CGSize(width: AreaHandleView.side, height: AreaHandleView.side)))
        }
        grip = handlePanel(edges: .all, size: AreaHandleView.gripSize)
        placeHandles()
    }

    /// A small window of its own for a handle or the grip: the outline lets clicks through, these take them.
    private func handlePanel(edges: AreaEdges, size: CGSize) -> NSPanel {
        let view = AreaHandleView(frame: CGRect(origin: .zero, size: size))
        view.edges = edges
        view.onDrag = { [weak self] edges, original, dx, dy in
            self?.resize(from: original, edges: edges, dx: dx, dy: dy)
        }
        view.currentArea = { [weak self] in
            return self?.area ?? .zero
        }
        let panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Under the drawing overlay, so a stroke that starts on a handle still draws.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = view
        panel.orderFrontRegardless()
        return panel
    }

    private func placeHandles() {
        for (index, panel) in handles.enumerated() {
            let center = AreaEdges.handles[index].point(on: area)
            panel.setFrameOrigin(CGPoint(x: center.x - AreaHandleView.side / 2, y: center.y - AreaHandleView.side / 2))
        }
        if let panel = grip {
            let origin = RecordingOutline.gripOrigin(area: area, screens: screenFrames)
            panel.setFrameOrigin(origin)
            // The size label keeps clear of the grip.
            for item in screenViews {
                item.view.gripRect = CGRect(origin: origin, size: AreaHandleView.gripSize).offsetBy(dx: -item.frame.minX, dy: -item.frame.minY)
                item.view.needsDisplay = true
            }
        }
    }

    /// The grip sits centered above the frame, clear of the top handle; with no screen to hold it
    /// above (the area reaches the top) just inside it. Our windows are not in the video.
    static func gripOrigin(area: CGRect, screens: [CGRect]) -> CGPoint {
        let size = AreaHandleView.gripSize
        let gap = AreaHandleView.side / 2 + 4
        let x = (area.midX - size.width / 2).rounded()
        var y = area.maxY + gap
        var onAScreen = false
        for screen in screens where screen.contains(CGRect(x: x, y: y, width: size.width, height: size.height)) {
            onAScreen = true
        }
        if !onAScreen {
            y = area.maxY - gap - size.height
        }
        return CGPoint(x: x, y: y.rounded())
    }

    /// Resizes or moves the area from where the drag started, anywhere on the screens: onto another
    /// one or across two. It always keeps a part on a screen.
    func resize(from original: CGRect, edges: AreaEdges, dx: CGFloat, dy: CGFloat) {
        // Along the edge of a screen where the next one is shorter, instead of stopping.
        guard let onScreens = AreaResize.dragged(original, edges: edges, dx: dx, dy: dy, screens: screenFrames, minimum: RecordingOutline.minimumSide) else { return }
        let resized = onScreens.integral
        if resized == area { return }
        area = resized
        showArea()
        placeHandles()
        onAreaChange?(resized)
    }

    /// For automation: the handle centers in top-left screen coordinates, corners first.
    var handleCenters: [CGPoint] {
        guard let main = NSScreen.screens.first else { return [] }
        var centers: [CGPoint] = []
        for panel in handles {
            centers.append(CGPoint(x: panel.frame.midX, y: main.frame.maxY - panel.frame.midY))
        }
        return centers
    }

    /// For automation: the grip's center in top-left screen coordinates, nil without one.
    var gripCenter: CGPoint? {
        guard let panel = grip, let main = NSScreen.screens.first else { return nil }
        return CGPoint(x: panel.frame.midX, y: main.frame.maxY - panel.frame.midY)
    }

    var windowCount: Int {
        return windows.count
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        for panel in handles {
            panel.orderOut(nil)
        }
        handles.removeAll()
        grip?.orderOut(nil)
        grip = nil
        hasArea = false
        screenViews.removeAll()
    }
}

final class RecordingOutlineView: NSView {
    /// What is recorded on this screen, in view coordinates. Nil: nothing on this screen is recorded.
    var recordedRect: CGRect?
    var pixelScale: CGFloat = 2
    /// Pixels per point of the clip: an area across displays takes the sharpest one's.
    var labelScale: CGFloat?
    /// The size label; an area across displays has it on one of them.
    var showsLabel = true
    /// Where the grip is in this view, which the size label keeps clear of.
    var gripRect: CGRect?
    /// Draws the resize handles into the picture (README and What's New pictures; on screen they
    /// are windows of their own).
    var drawsHandles = false
    /// With the handles, the grip too (a picture of an area across displays draws it on one).
    var drawsGrip = true

    private let accent = NSColor(hex: 0xFF6B4A)
    private let veil = NSColor.black.withAlphaComponent(0.42)

    override func draw(_ dirtyRect: NSRect) {
        guard let recorded = recordedRect else {
            veil.setFill()
            bounds.fill()
            drawLabel(L("recording.outline.notRecorded"), at: CGPoint(x: bounds.midX, y: bounds.midY), centered: true, fill: NSColor(hex: 0x1C1D20, alpha: 0.9), text: .white)
            return
        }
        let isWholeScreen = recorded.size == bounds.size
        if !isWholeScreen {
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(rect: recorded))
            outside.windingRule = .evenOdd
            veil.setFill()
            outside.fill()
        }
        // The frame sits just outside a picked area, so it never covers recorded pixels.
        var frameRect = recorded.insetBy(dx: -2, dy: -2)
        if isWholeScreen {
            frameRect = bounds.insetBy(dx: 2, dy: 2)
        }
        let frame = NSBezierPath(rect: frameRect)
        frame.lineWidth = 4
        accent.setStroke()
        frame.stroke()

        let scale = labelScale ?? pixelScale
        let size = "\(Int(recorded.width * scale)) × \(Int(recorded.height * scale))"
        var labelPoint = CGPoint(x: recorded.minX, y: recorded.maxY + 8)
        if isWholeScreen || labelPoint.y + 24 > bounds.maxY {
            labelPoint = CGPoint(x: recorded.minX + 10, y: recorded.minY + 10)
        }
        var grip = gripRect
        if drawsHandles && drawsGrip && !isWholeScreen {
            grip = CGRect(origin: RecordingOutline.gripOrigin(area: recorded, screens: [bounds]), size: AreaHandleView.gripSize)
        }
        if showsLabel {
            drawLabel(L("recording.outline.label", size), at: labelPoint, centered: false, fill: accent, text: NSColor(hex: 0x1A0B06), avoiding: isWholeScreen ? nil : grip)
        }
        if drawsHandles && !isWholeScreen {
            for edges in AreaEdges.handles {
                let center = edges.point(on: recorded)
                let side = AreaHandleView.side
                AreaHandleView.drawHandle(in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
            }
            if drawsGrip {
                let origin = RecordingOutline.gripOrigin(area: recorded, screens: [bounds])
                AreaHandleView.drawGrip(in: CGRect(origin: origin, size: AreaHandleView.gripSize))
            }
        }
    }

    private func drawLabel(_ title: String, at point: CGPoint, centered: Bool, fill: NSColor, text: NSColor, avoiding grip: CGRect? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: text,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        var origin = point
        if centered {
            origin = CGPoint(x: point.x - size.width / 2 - 8, y: point.y - size.height / 2 - 4)
        }
        var rect = CGRect(x: origin.x, y: origin.y, width: size.width + 16, height: size.height + 8)
        if let grip {
            rect = AreaResize.label(rect, clearOf: grip, gap: 4)
        }
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        (title as NSString).draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 4), withAttributes: attributes)
    }
}

/// A square on the recording frame that resizes the area when dragged, or the grip above it
/// (edges `.all`) that moves the whole area.
final class AreaHandleView: NSView {
    static let side: CGFloat = 14
    static let gripSize = CGSize(width: 56, height: 16)
    var edges = AreaEdges()
    /// edges, the area when the drag started, and how far the pointer moved (global points).
    var onDrag: ((AreaEdges, CGRect, CGFloat, CGFloat) -> Void)?
    var currentArea: (() -> CGRect)?
    private var dragStart: CGPoint?
    private var originalArea: CGRect = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        if edges == .all {
            AreaHandleView.drawGrip(in: bounds)
        } else {
            AreaHandleView.drawHandle(in: bounds)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        RegionSelectionView.cursor(for: edges.cursor).set()
    }

    override func mouseEntered(with event: NSEvent) {
        RegionSelectionView.cursor(for: edges.cursor).set()
    }

    override func mouseExited(with event: NSEvent) {
        if dragStart == nil {
            NSCursor.arrow.set()
        }
    }

    /// A pill in the frame's color with three grip lines.
    static func drawGrip(in rect: CGRect) {
        let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor(hex: 0xFF6B4A).setFill()
        pill.fill()
        NSColor.white.setStroke()
        for index in -1...1 {
            let y = rect.midY + CGFloat(index) * 3.5
            let line = NSBezierPath()
            line.move(to: CGPoint(x: rect.midX - 9, y: y))
            line.line(to: CGPoint(x: rect.midX + 9, y: y))
            line.lineWidth = 1.5
            line.lineCapStyle = .round
            line.stroke()
        }
    }

    static func drawHandle(in rect: CGRect) {
        let square = rect.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: square, xRadius: 2, yRadius: 2)
        NSColor.white.setFill()
        path.fill()
        NSColor(hex: 0xFF6B4A).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        originalArea = currentArea?() ?? .zero
        if edges == .all {
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        onDrag?(edges, originalArea, now.x - start.x, now.y - start.y)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        RegionSelectionView.cursor(for: edges.cursor).set()
    }
}
