import AppKit

/// Full-screen picker for "record an area": drag to draw, drag inside to move,
/// drag the corner handles to resize. Enter or "Record" confirms, Esc cancels.
@MainActor
final class RegionSelector {
    struct Selection {
        var screen: NSScreen
        /// Normalized rect on the screen, origin top-left.
        var normalized: CGRect
        /// Global AppKit rect (origin bottom-left) for drawing the frame while recording.
        var global: CGRect
    }

    private var panel: KeyablePanel?

    /// For automation: the size chips of the open picker, in top-left screen coordinates.
    var chipCenters: [(title: String, point: CGPoint)] {
        guard let view = panel?.contentView as? RegionSelectionView, let screenFrame = panel?.frame, let main = NSScreen.screens.first else { return [] }
        var result: [(title: String, point: CGPoint)] = []
        for chip in view.chipRects {
            // View coordinates are flipped (top-left) within the screen.
            let x = screenFrame.minX + chip.rect.midX
            let top = (main.frame.maxY - screenFrame.maxY) + chip.rect.midY
            result.append((title: chip.title, point: CGPoint(x: x, y: top)))
        }
        return result
    }
    private var continuation: CheckedContinuation<Selection?, Never>?

    func pick(on screen: NSScreen, initial: CGRect?, confirmTitle: String = L("recording.areaPicker.record"), showsSizes: Bool = true) async -> Selection? {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let newPanel = KeyablePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            newPanel.identifier = NSUserInterfaceItemIdentifier("region-picker")
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.level = .screenSaver
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.isReleasedWhenClosed = false
            let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.confirmTitle = confirmTitle
            view.showsSizes = showsSizes
            if let start = initial {
                view.selection = start
            } else {
                let size = screen.frame.size
                view.selection = CGRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.6, height: size.height * 0.6)
            }
            view.onFinish = { [weak self] rect in
                MainActor.assumeIsolated {
                    self?.finish(rect: rect, screen: screen)
                }
            }
            newPanel.contentView = view
            panel = newPanel
            NSApp.activate(ignoringOtherApps: true)
            newPanel.makeKeyAndOrderFront(nil)
            newPanel.makeFirstResponder(view)
        }
    }

    private func finish(rect: CGRect?, screen: NSScreen) {
        panel?.orderOut(nil)
        panel = nil
        guard let selected = rect, selected.width > 20, selected.height > 20 else {
            continuation?.resume(returning: nil)
            continuation = nil
            return
        }
        let size = screen.frame.size
        let normalized = CGRect(x: selected.minX / size.width, y: selected.minY / size.height, width: selected.width / size.width, height: selected.height / size.height)
        // View coordinates are flipped (top-left); convert to global bottom-left.
        let global = CGRect(x: screen.frame.minX + selected.minX, y: screen.frame.maxY - selected.maxY, width: selected.width, height: selected.height)
        continuation?.resume(returning: Selection(screen: screen, normalized: normalized, global: global))
        continuation = nil
    }

}

/// A button drawn by hand that VoiceOver (and the tests) can still find and press. Its frame is
/// read from the view each time, so it follows the selection when that moves.
final class DrawnButton: NSAccessibilityElement {
    private weak var view: NSView?
    private let rect: () -> CGRect
    private let action: () -> Void

    /// `rect` gives the place in the view's own coordinates.
    init(label: String, view: NSView, rect: @escaping () -> CGRect, action: @escaping () -> Void) {
        self.view = view
        self.rect = rect
        self.action = action
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setAccessibilityParent(view)
    }

    override func accessibilityFrame() -> NSRect {
        guard let view else { return .zero }
        // Converts from the view's coordinates, flipped or not, to the screen.
        return NSAccessibility.screenRect(fromView: view, rect: rect())
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}

final class RegionSelectionView: NSView {
    var selection: CGRect = .zero
    var onFinish: ((CGRect?) -> Void)?
    var confirmTitle = L("recording.areaPicker.record")
    /// The ready-made size bar; off where sizes make no sense (scrolling screenshots).
    var showsSizes = true

    private enum DragMode {
        case create(CGPoint)
        case move(CGPoint, CGRect)
        case resize(corner: Int, original: CGRect)
    }

    private var dragMode: DragMode?
    private let handleSize: CGFloat = 12

    /// Ready-made sizes in the bar at the top. Pixel sizes match what ends up in the video.
    private struct SizePreset {
        enum Kind {
            case pixels(CGSize)
            case points(CGSize)
            case aspect(CGSize)
            case fullScreen
        }

        var title: String
        var kind: Kind
    }

    private let presets: [SizePreset] = [
        SizePreset(title: "720p", kind: .pixels(CGSize(width: 1280, height: 720))),
        SizePreset(title: "1080p", kind: .pixels(CGSize(width: 1920, height: 1080))),
        SizePreset(title: "1440×900", kind: .pixels(CGSize(width: 1440, height: 900))),
        SizePreset(title: "16:9", kind: .aspect(CGSize(width: 16, height: 9))),
        SizePreset(title: "4:3", kind: .aspect(CGSize(width: 4, height: 3))),
        SizePreset(title: "1:1", kind: .aspect(CGSize(width: 1, height: 1))),
        SizePreset(title: L("recording.areaPicker.size.phone"), kind: .points(CGSize(width: 390, height: 844))),
        SizePreset(title: L("recording.areaPicker.size.fullScreen"), kind: .fullScreen),
    ]

    private let presetFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    /// Chip rects in a row centered near the top of the screen, below the menu bar.
    private var presetRects: [CGRect] {
        var widths: [CGFloat] = []
        var total: CGFloat = 0
        for preset in presets {
            let width = (preset.title as NSString).size(withAttributes: [.font: presetFont]).width + 20
            widths.append(width)
            total += width + 6
        }
        let label: CGFloat = 44
        var x = bounds.midX - (total + label) / 2 + label
        var rects: [CGRect] = []
        for width in widths {
            rects.append(CGRect(x: x, y: 48, width: width, height: 28))
            x += width + 6
        }
        return rects
    }

    var chipRects: [(title: String, rect: CGRect)] {
        var result: [(title: String, rect: CGRect)] = []
        for (index, rect) in presetRects.enumerated() {
            result.append((title: presets[index].title, rect: rect))
        }
        return result
    }

    private func apply(_ preset: SizePreset) {
        let scale = window?.backingScaleFactor ?? 2
        var size = selection.size
        switch preset.kind {
        case .fullScreen:
            selection = bounds
            needsDisplay = true
            announceLayoutChange()
            return
        case .pixels(let pixels):
            size = CGSize(width: pixels.width / scale, height: pixels.height / scale)
        case .points(let points):
            size = points
        case .aspect(let ratio):
            size = CGSize(width: selection.width, height: selection.width * ratio.height / ratio.width)
        }
        // Too big for this screen: shrink, keeping the shape.
        let fit = min(1, bounds.width / size.width, bounds.height / size.height)
        size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
        var center = CGPoint(x: selection.midX, y: selection.midY)
        if selection.width < 1 || selection.height < 1 {
            center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        origin.x = max(0, min(bounds.width - size.width, origin.x))
        origin.y = max(0, min(bounds.height - size.height, origin.y))
        selection = CGRect(origin: origin, size: size)
        needsDisplay = true
        announceLayoutChange()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var corners: [CGPoint] {
        return [
            CGPoint(x: selection.minX, y: selection.minY),
            CGPoint(x: selection.maxX, y: selection.minY),
            CGPoint(x: selection.maxX, y: selection.maxY),
            CGPoint(x: selection.minX, y: selection.maxY),
        ]
    }

    private var buttonRects: (record: CGRect, cancel: CGRect) {
        let y = min(bounds.height - 44, selection.maxY + 12)
        let record = CGRect(x: selection.midX + 4, y: y, width: 110, height: 32)
        let cancel = CGRect(x: selection.midX - 114, y: y, width: 110, height: 32)
        return (record: record, cancel: cancel)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything except the selection.
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: selection))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        let border = NSBezierPath(rect: selection)
        border.lineWidth = 2
        NSColor(hex: 0xFF6B4A).setStroke()
        border.stroke()

        for corner in corners {
            let handle = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2, width: handleSize, height: handleSize)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: handle).fill()
            NSColor(hex: 0xFF6B4A).setStroke()
            NSBezierPath(ovalIn: handle).stroke()
        }

        let scale = window?.backingScaleFactor ?? 2
        let label = "\(Int(selection.width * scale)) × \(Int(selection.height * scale))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let labelSize = label.size(withAttributes: attributes)
        let labelRect = CGRect(x: selection.minX, y: max(0, selection.minY - labelSize.height - 10), width: labelSize.width + 12, height: labelSize.height + 6)
        NSColor(hex: 0x1C1D20, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        label.draw(at: CGPoint(x: labelRect.minX + 6, y: labelRect.minY + 3), withAttributes: attributes)

        if showsSizes {
            drawPresetBar()
        }
        drawButton(buttonRects.cancel, title: L("recording.areaPicker.cancel.withKey"), fill: NSColor(hex: 0x2B2D31), text: .white)
        drawButton(buttonRects.record, title: confirmTitle, fill: NSColor(hex: 0xFF6B4A), text: NSColor(hex: 0x1A0B06))
    }

    private func drawPresetBar() {
        let rects = presetRects
        guard let first = rects.first, let last = rects.last else { return }
        let bar = CGRect(x: first.minX - 52, y: first.minY - 6, width: last.maxX - first.minX + 60, height: first.height + 12)
        NSColor(hex: 0x1C1D20, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 9, yRadius: 9).fill()
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: presetFont, .foregroundColor: NSColor(white: 1, alpha: 0.6)]
        (L("recording.areaPicker.size") as NSString).draw(at: CGPoint(x: bar.minX + 12, y: first.midY - 8), withAttributes: labelAttributes)
        let scale = window?.backingScaleFactor ?? 2
        for (index, preset) in presets.enumerated() {
            var isCurrent = false
            switch preset.kind {
            case .pixels(let pixels):
                isCurrent = abs(selection.width * scale - pixels.width) < 2 && abs(selection.height * scale - pixels.height) < 2
            case .points(let points):
                isCurrent = abs(selection.width - points.width) < 1 && abs(selection.height - points.height) < 1
            case .fullScreen:
                isCurrent = selection == bounds
            case .aspect:
                isCurrent = false
            }
            let fill = isCurrent ? NSColor(hex: 0xFF6B4A) : NSColor(hex: 0x2B2D31)
            let text = isCurrent ? NSColor(hex: 0x1A0B06) : NSColor.white
            let attributes: [NSAttributedString.Key: Any] = [.font: presetFont, .foregroundColor: text]
            let rect = rects[index]
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            let size = (preset.title as NSString).size(withAttributes: attributes)
            (preset.title as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }

    private func drawButton(_ rect: CGRect, title: String, fill: NSColor, text: NSColor) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: text]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }

    /// The buttons for accessibility, kept while the picker looks the same: VoiceOver follows an
    /// element by its identity, so a new one on every question would lose its place.
    private var drawnButtons: [DrawnButton] = []
    private var drawnButtonsLayout = ""

    /// The buttons and size chips for VoiceOver and the tests, named without the key hint.
    override func accessibilityChildren() -> [Any]? {
        let layout = "\(showsSizes)|\(confirmTitle)"
        if layout == drawnButtonsLayout {
            return drawnButtons
        }
        var buttons: [DrawnButton] = []
        if showsSizes {
            for (index, preset) in presets.enumerated() {
                let button = DrawnButton(label: L("recording.areaPicker.size.button", preset.title), view: self, rect: { [weak self] in
                    self?.presetRects[index] ?? .zero
                }, action: { [weak self] in
                    self?.apply(preset)
                })
                buttons.append(button)
            }
        }
        buttons.append(DrawnButton(label: L("recording.areaPicker.cancel"), view: self, rect: { [weak self] in
            self?.buttonRects.cancel ?? .zero
        }, action: { [weak self] in
            self?.onFinish?(nil)
        }))
        let confirmLabel = confirmTitle.components(separatedBy: "  ").first ?? confirmTitle
        buttons.append(DrawnButton(label: confirmLabel, view: self, rect: { [weak self] in
            self?.buttonRects.record ?? .zero
        }, action: { [weak self] in
            guard let view = self else { return }
            view.onFinish?(view.selection)
        }))
        drawnButtons = buttons
        drawnButtonsLayout = layout
        return buttons
    }

    /// VoiceOver's pointer finds the drawn buttons under it.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        for button in accessibilityChildren() ?? [] {
            if let drawn = button as? DrawnButton, drawn.accessibilityFrame().contains(point) {
                return drawn
            }
        }
        return super.accessibilityHitTest(point)
    }

    /// The buttons moved with the selection.
    private func announceLayoutChange() {
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, rect) in presetRects.enumerated() where showsSizes && rect.contains(point) {
            apply(presets[index])
            return
        }
        if buttonRects.record.contains(point) {
            onFinish?(selection)
            return
        }
        if buttonRects.cancel.contains(point) {
            onFinish?(nil)
            return
        }
        for (index, corner) in corners.enumerated() where hypot(point.x - corner.x, point.y - corner.y) < handleSize {
            dragMode = .resize(corner: index, original: selection)
            return
        }
        if selection.contains(point) {
            dragMode = .move(point, selection)
            return
        }
        dragMode = .create(point)
        selection = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let mode = dragMode else { return }
        switch mode {
        case .create(let origin):
            selection = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        case .move(let start, let original):
            var moved = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            moved.origin.x = max(0, min(bounds.width - moved.width, moved.origin.x))
            moved.origin.y = max(0, min(bounds.height - moved.height, moved.origin.y))
            selection = moved
        case .resize(let corner, let original):
            // The corner opposite the dragged one stays fixed.
            let opposite = (corner + 2) % 4
            let fixedCorners = [
                CGPoint(x: original.minX, y: original.minY),
                CGPoint(x: original.maxX, y: original.minY),
                CGPoint(x: original.maxX, y: original.maxY),
                CGPoint(x: original.minX, y: original.maxY),
            ]
            let fixed = fixedCorners[opposite]
            selection = CGRect(x: min(fixed.x, point.x), y: min(fixed.y, point.y), width: abs(point.x - fixed.x), height: abs(point.y - fixed.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if dragMode != nil {
            announceLayoutChange()
        }
        dragMode = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish?(nil)
        } else if event.keyCode == 36 || event.keyCode == 76 {
            onFinish?(selection)
        } else {
            super.keyDown(with: event)
        }
    }
}
