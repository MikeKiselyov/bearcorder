import AppKit

/// While recording, shows what ends up in the video: a solid frame around the recorded area or screen,
/// and a dim veil with "Not recorded" over everything else (outside the area, other displays).
/// These are our own windows, which the capture excludes, so none of this is in the video.
@MainActor
final class RecordingOutline {
    private var windows: [NSPanel] = []

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
    }

    var windowCount: Int {
        return windows.count
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}

final class RecordingOutlineView: NSView {
    /// What is recorded on this screen, in view coordinates. Nil: nothing on this screen is recorded.
    var recordedRect: CGRect?
    var pixelScale: CGFloat = 2

    private let accent = NSColor(hex: 0xFF6B4A)
    private let veil = NSColor.black.withAlphaComponent(0.42)

    override func draw(_ dirtyRect: NSRect) {
        guard let recorded = recordedRect else {
            veil.setFill()
            bounds.fill()
            drawLabel("Not recorded", at: CGPoint(x: bounds.midX, y: bounds.midY), centered: true, fill: NSColor(hex: 0x1C1D20, alpha: 0.9), text: .white)
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
        drawLabel("● REC  \(size)", at: labelPoint, centered: false, fill: accent, text: NSColor(hex: 0x1A0B06))
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
