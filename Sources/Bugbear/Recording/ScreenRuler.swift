import AppKit

/// Measure on screen: drag a box to read its size in points and pixels. Esc finishes, ⌘C copies the size.
/// The ruler is our own window, so it is never in recordings.
@MainActor
final class ScreenRuler {
    static let shared = ScreenRuler()

    private var panels: [KeyablePanel] = []
    /// Esc must close the ruler even if another app took the keyboard focus.
    private var escapeMonitor: Any?

    var isActive: Bool {
        return !panels.isEmpty
    }

    func start() {
        stop()
        for screen in NSScreen.screens {
            let panel = KeyablePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            let view = RulerView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.pixelScale = screen.backingScaleFactor
            view.onFinish = {
                MainActor.assumeIsolated {
                    ScreenRuler.shared.stop()
                }
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated {
                    ScreenRuler.shared.stop()
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        for panel in panels where panel.frame.contains(mouse) {
            panel.makeKey()
            panel.makeFirstResponder(panel.contentView)
        }
    }

    func stop() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitor = nil
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }
}

final class RulerView: NSView {
    var pixelScale: CGFloat = 2
    var onFinish: (() -> Void)?

    private var start: CGPoint?
    private var current: CGPoint?
    private var copied = false

    private let accent = NSColor(hex: 0x4C9BFF)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var box: CGRect? {
        guard let from = start, let to = current else { return nil }
        return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
    }

    private var sizeText: String {
        guard let rect = box else { return "" }
        let width = Int(rect.width.rounded())
        let height = Int(rect.height.rounded())
        return "\(width) × \(height) pt"
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()
        drawHint()
        guard let rect = box, let from = start, let to = current else { return }
        accent.withAlphaComponent(0.15).setFill()
        rect.fill()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 1
        accent.setStroke()
        outline.stroke()

        let diagonal = NSBezierPath()
        diagonal.move(to: from)
        diagonal.line(to: to)
        diagonal.lineWidth = 1
        diagonal.setLineDash([4, 3], count: 2, phase: 0)
        accent.withAlphaComponent(0.8).setStroke()
        diagonal.stroke()

        let pixelsWide = Int((rect.width * pixelScale).rounded())
        let pixelsHigh = Int((rect.height * pixelScale).rounded())
        let distance = Int(hypot(to.x - from.x, to.y - from.y).rounded())
        var lines = [sizeText, "\(pixelsWide) × \(pixelsHigh) px · diagonal \(distance) pt"]
        if copied {
            lines.append("Copied")
        }
        drawLabel(lines, near: CGPoint(x: rect.maxX + 10, y: rect.maxY + 10))
    }

    private func drawHint() {
        let text = "Drag to measure  ·  ⌘C copies the size  ·  Esc to finish" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(x: bounds.midX - size.width / 2 - 14, y: 48, width: size.width + 28, height: size.height + 14)
        NSColor(hex: 0x1C1D20, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 7), withAttributes: attributes)
    }

    private func drawLabel(_ lines: [String], near point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
        var width: CGFloat = 0
        for line in lines {
            width = max(width, (line as NSString).size(withAttributes: attributes).width)
        }
        let lineHeight: CGFloat = 17
        var origin = point
        let size = CGSize(width: width + 16, height: CGFloat(lines.count) * lineHeight + 10)
        if origin.x + size.width > bounds.maxX { origin.x = bounds.maxX - size.width - 8 }
        if origin.y + size.height > bounds.maxY { origin.y = bounds.maxY - size.height - 8 }
        let rect = CGRect(origin: origin, size: size)
        NSColor(hex: 0x1C1D20, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 5 + CGFloat(index) * lineHeight), withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        copied = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        var point = convert(event.locationInWindow, from: nil)
        // Shift keeps the line straight: horizontal or vertical.
        if event.modifierFlags.contains(.shift), let from = start {
            if abs(point.x - from.x) > abs(point.y - from.y) {
                point.y = from.y
            } else {
                point.x = from.x
            }
        }
        current = point
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish?()
            return
        }
        let key = (event.charactersIgnoringModifiers ?? "").lowercased()
        if event.modifierFlags.contains(.command) && key == "c" && box != nil {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sizeText, forType: .string)
            copied = true
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish?()
    }
}
