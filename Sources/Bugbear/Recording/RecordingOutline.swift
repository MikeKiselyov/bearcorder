import AppKit
import BugbearCore

/// While recording, shows what ends up in the video: a solid frame around the recorded area or screen,
/// and a dim veil with "Not recorded" over everything else (outside the area, other displays).
/// These are our own windows, which the capture excludes, so none of this is in the video.
/// A picked area has handles on its corners and edges: drag one to make the area bigger or smaller
/// while recording; the video gets the area as it is when the recording stops.
@MainActor
final class RecordingOutline {
    private var windows: [NSPanel] = []
    private var handles: [NSPanel] = []
    /// The picked area (global, bottom-left) and the screen it is on.
    private var area: CGRect = .zero
    private var areaScreen: NSScreen?
    private var areaView: RecordingOutlineView?
    /// The area was resized: the new global rect (origin bottom-left).
    var onAreaChange: ((CGRect) -> Void)?
    /// The area never gets smaller than this, in points.
    static let minimumSide: CGFloat = 40

    /// `region` is the picked area (nil for whole screens); `recordedDisplays` are the captured displays.
    func show(region: RegionSelector.Selection?, recordedDisplays: Set<CGDirectDisplayID>) {
        hide()
        for screen in NSScreen.screens {
            let view = RecordingOutlineView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.pixelScale = screen.backingScaleFactor
            let displayID = AppState.displayID(of: screen)
            if let selected = region {
                if selected.screen == screen {
                    // Global (bottom-left) rect to this window's coordinates.
                    view.recordedRect = selected.global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                    area = selected.global
                    areaScreen = screen
                    areaView = view
                }
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
        if areaScreen != nil {
            showHandles()
        }
    }

    private func showHandles() {
        for edges in AreaEdges.handles {
            let view = AreaHandleView(frame: CGRect(x: 0, y: 0, width: AreaHandleView.side, height: AreaHandleView.side))
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
            handles.append(panel)
        }
        placeHandles()
    }

    private func placeHandles() {
        for (index, panel) in handles.enumerated() {
            let center = AreaEdges.handles[index].point(on: area)
            panel.setFrameOrigin(CGPoint(x: center.x - AreaHandleView.side / 2, y: center.y - AreaHandleView.side / 2))
        }
    }

    /// Resizes the area from where the drag started, inside its screen.
    func resize(from original: CGRect, edges: AreaEdges, dx: CGFloat, dy: CGFloat) {
        guard let screen = areaScreen else { return }
        let resized = AreaResize.resized(original, edges: edges, dx: dx, dy: dy, bounds: screen.frame, minimum: RecordingOutline.minimumSide).integral
        if resized == area { return }
        area = resized
        areaView?.recordedRect = resized.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        areaView?.needsDisplay = true
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
        areaScreen = nil
        areaView = nil
    }
}

final class RecordingOutlineView: NSView {
    /// What is recorded on this screen, in view coordinates. Nil: nothing on this screen is recorded.
    var recordedRect: CGRect?
    var pixelScale: CGFloat = 2
    /// Draws the resize handles into the picture (README and What's New pictures; on screen they
    /// are windows of their own).
    var drawsHandles = false

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

        let size = "\(Int(recorded.width * pixelScale)) × \(Int(recorded.height * pixelScale))"
        var labelPoint = CGPoint(x: recorded.minX, y: recorded.maxY + 8)
        if isWholeScreen || labelPoint.y + 24 > bounds.maxY {
            labelPoint = CGPoint(x: recorded.minX + 10, y: recorded.minY + 10)
        }
        drawLabel(L("recording.outline.label", size), at: labelPoint, centered: false, fill: accent, text: NSColor(hex: 0x1A0B06))
        if drawsHandles && !isWholeScreen {
            for edges in AreaEdges.handles {
                let center = edges.point(on: recorded)
                let side = AreaHandleView.side
                AreaHandleView.drawHandle(in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
            }
        }
    }

    private func drawLabel(_ title: String, at point: CGPoint, centered: Bool, fill: NSColor, text: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: text,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        var origin = point
        if centered {
            origin = CGPoint(x: point.x - size.width / 2 - 8, y: point.y - size.height / 2 - 4)
        }
        let rect = CGRect(x: origin.x, y: origin.y, width: size.width + 16, height: size.height + 8)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        (title as NSString).draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 4), withAttributes: attributes)
    }
}

/// A square on the recording frame that resizes the area when dragged.
final class AreaHandleView: NSView {
    static let side: CGFloat = 14
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
        AreaHandleView.drawHandle(in: bounds)
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
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        onDrag?(edges, originalArea, now.x - start.x, now.y - start.y)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }
}
