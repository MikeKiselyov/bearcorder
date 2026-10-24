import AppKit
import SwiftUI

/// SwiftUI wrapper: a zoomable scroll view hosting the AppKit drawing canvas.
struct AnnotationCanvas: NSViewRepresentable {
    let document: ScreenshotDocument

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 8
        scrollView.backgroundColor = NSColor(hex: 0x131416)
        scrollView.drawsBackground = true
        let canvas = CanvasView(document: document)
        scrollView.documentView = canvas
        context.coordinator.canvas = canvas
        context.coordinator.scrollView = scrollView
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.magnificationChanged), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
        DispatchQueue.main.async {
            context.coordinator.fit()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Reading these registers observation so SwiftUI calls us when they change.
        _ = document.annotations
        _ = document.selectedId
        _ = document.crop
        _ = document.tool
        _ = document.showBadge
        _ = document.badgeCorner
        _ = document.base
        _ = document.editingTextId
        guard let canvas = context.coordinator.canvas else { return }
        canvas.updateGeometry()
        canvas.needsDisplay = true
        if context.coordinator.lastFitRequest != document.fitRequest {
            context.coordinator.lastFitRequest = document.fitRequest
            DispatchQueue.main.async {
                context.coordinator.fit()
            }
        } else if abs(scrollView.magnification - document.zoom) > 0.0001 {
            scrollView.magnification = document.zoom
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(document: document)
    }

    @MainActor
    final class Coordinator: NSObject {
        let document: ScreenshotDocument
        weak var canvas: CanvasView?
        weak var scrollView: NSScrollView?
        var lastFitRequest = 0

        init(document: ScreenshotDocument) {
            self.document = document
        }

        func fit() {
            guard let scrollView = scrollView, let canvas = canvas else { return }
            let available = scrollView.contentSize
            let size = canvas.frame.size
            if size.width <= 0 || size.height <= 0 || available.width <= 0 { return }
            let scale = min((available.width - 40) / size.width, (available.height - 40) / size.height)
            let backing = scrollView.window?.backingScaleFactor ?? 2
            // Never enlarge past actual pixels when fitting.
            let magnification = min(scale, 1 / backing)
            scrollView.magnification = magnification
            document.zoom = magnification
        }

        @objc func magnificationChanged() {
            guard let scrollView = scrollView else { return }
            document.zoom = scrollView.magnification
        }
    }
}

/// Centers the document when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let frame = document.frame
        if rect.width > frame.width {
            rect.origin.x = frame.minX - (rect.width - frame.width) / 2
        }
        if rect.height > frame.height {
            rect.origin.y = frame.minY - (rect.height - frame.height) / 2
        }
        return rect
    }
}

/// Draws the screenshot with its marks and turns mouse gestures into annotations.
/// Coordinates are image pixels, origin top-left (the view is flipped).
final class CanvasView: NSView, NSTextFieldDelegate {
    let document: ScreenshotDocument

    private enum Gesture {
        case draw
        case move(start: CGPoint, original: Annotation)
        case handle(isStart: Bool, original: Annotation)
        case crop(start: CGPoint)
    }

    private var gesture: Gesture?
    private var draft: Annotation?
    private var cropDraft: CGRect?
    private var textField: NSTextField?

    init(document: ScreenshotDocument) {
        self.document = document
        super.init(frame: CGRect(origin: .zero, size: document.imageSize))
        updateGeometry()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var magnification: CGFloat {
        return enclosingScrollView?.magnification ?? 1
    }

    /// While cropping we show the whole image; otherwise only the cropped region.
    private var displayedArea: CGRect {
        let full = CGRect(origin: .zero, size: document.imageSize)
        if document.tool == .crop { return full }
        return document.crop ?? full
    }

    func updateGeometry() {
        MainActor.assumeIsolated {
            let area = displayedArea
            if frame.size != area.size {
                setFrameSize(area.size)
            }
            if bounds.origin != area.origin {
                setBoundsOrigin(area.origin)
            }
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        MainActor.assumeIsolated {
            drawContents()
        }
    }

    @MainActor
    private func drawContents() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let full = CGRect(origin: .zero, size: document.imageSize)
        let image = NSImage(cgImage: document.base, size: full.size)
        image.draw(in: full, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])

        var visible: [Annotation] = []
        for annotation in document.annotations {
            visible.append(annotation)
        }
        if let current = draft {
            visible.append(current)
        }
        AnnotationRenderer.draw(visible, baseImage: document.base, in: context)

        if document.showBadge {
            AnnotationRenderer.drawBadge(lines: document.badgeLines, corner: document.badgeCorner, bounds: document.crop ?? full, scale: document.unit, in: context)
        }

        if document.tool == .crop {
            drawCropOverlay(full: full)
        }

        if let selected = document.selected, document.tool == .select {
            drawSelection(selected)
        }
    }

    @MainActor
    private func drawCropOverlay(full: CGRect) {
        let area = cropDraft ?? document.crop ?? full
        let dim = NSBezierPath(rect: full)
        dim.append(NSBezierPath(rect: area))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.55).setFill()
        dim.fill()
        let border = NSBezierPath(rect: area)
        border.lineWidth = 2 / magnification
        border.setLineDash([8 / magnification, 5 / magnification], count: 2, phase: 0)
        NSColor.white.setStroke()
        border.stroke()
    }

    @MainActor
    private func drawSelection(_ annotation: Annotation) {
        let outline = NSBezierPath(rect: annotation.bounds.insetBy(dx: -4 / magnification, dy: -4 / magnification))
        outline.lineWidth = 1.5 / magnification
        outline.setLineDash([5 / magnification, 4 / magnification], count: 2, phase: 0)
        NSColor(hex: 0x8AB8FF).setStroke()
        outline.stroke()
        if hasHandles(annotation) {
            for point in [annotation.start, annotation.end] {
                let size = 10 / magnification
                let handle = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: handle).fill()
                NSColor(hex: 0x4C9BFF).setStroke()
                let ring = NSBezierPath(ovalIn: handle)
                ring.lineWidth = 1.5 / magnification
                ring.stroke()
            }
        }
    }

    private func hasHandles(_ annotation: Annotation) -> Bool {
        switch annotation.tool {
        case .arrow, .line, .rectangle, .ellipse, .blur, .magnifier:
            return true
        default:
            return false
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            handleMouseDown(event)
        }
    }

    @MainActor
    private func handleMouseDown(_ event: NSEvent) {
        window?.makeFirstResponder(self)
        commitTextEditing()
        let point = convert(event.locationInWindow, from: nil)
        let tolerance = 8 / magnification

        switch document.tool {
        case .select:
            if let selected = document.selected, hasHandles(selected) {
                if hypot(point.x - selected.start.x, point.y - selected.start.y) < tolerance {
                    document.checkpoint()
                    gesture = .handle(isStart: true, original: selected)
                    return
                }
                if hypot(point.x - selected.end.x, point.y - selected.end.y) < tolerance {
                    document.checkpoint()
                    gesture = .handle(isStart: false, original: selected)
                    return
                }
            }
            // Topmost mark under the pointer.
            for annotation in document.annotations.reversed() where annotation.hitTest(point, tolerance: tolerance) {
                document.selectedId = annotation.id
                if event.clickCount == 2 && annotation.tool == .text {
                    beginTextEditing(annotation)
                    return
                }
                document.checkpoint()
                gesture = .move(start: point, original: annotation)
                return
            }
            document.selectedId = nil
        case .crop:
            gesture = .crop(start: point)
            cropDraft = CGRect(origin: point, size: .zero)
        case .text:
            var annotation = Annotation(tool: .text, start: point, end: point, color: document.color, lineWidth: document.lineWidth)
            annotation.fontSize = document.fontSize
            document.add(annotation)
            beginTextEditing(annotation)
        case .step:
            var annotation = Annotation(tool: .step, start: point, end: point, color: document.color, lineWidth: document.lineWidth)
            annotation.number = document.nextStepNumber
            annotation.fontSize = document.fontSize * 1.1
            document.add(annotation)
        default:
            var annotation = Annotation(tool: document.tool, start: point, end: point, color: document.color, lineWidth: document.lineWidth)
            annotation.fontSize = document.fontSize
            if document.tool == .pen || document.tool == .highlighter {
                annotation.points = [point]
            }
            draft = annotation
            gesture = .draw
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        MainActor.assumeIsolated {
            handleMouseDragged(event)
        }
    }

    @MainActor
    private func handleMouseDragged(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let current = gesture else { return }
        switch current {
        case .draw:
            guard var annotation = draft else { return }
            var end = point
            // Shift: constrain lines and arrows to 45°, rectangles to squares.
            if event.modifierFlags.contains(.shift) {
                end = constrained(start: annotation.start, end: point, tool: annotation.tool)
            }
            annotation.end = end
            if annotation.tool == .pen || annotation.tool == .highlighter {
                annotation.points.append(point)
            }
            draft = annotation
        case .move(let start, let original):
            var moved = original
            moved.move(by: CGSize(width: point.x - start.x, height: point.y - start.y))
            document.replace(moved)
        case .handle(let isStart, let original):
            var resized = original
            if isStart {
                resized.start = point
            } else {
                resized.end = point
            }
            document.replace(resized)
        case .crop(let start):
            cropDraft = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        }
        needsDisplay = true
    }

    private func constrained(start: CGPoint, end: CGPoint, tool: AnnotationTool) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if tool == .rectangle || tool == .ellipse || tool == .blur || tool == .magnifier {
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        let angle = atan2(dy, dx)
        let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: start.x + cos(snapped) * length, y: start.y + sin(snapped) * length)
    }

    override func mouseUp(with event: NSEvent) {
        MainActor.assumeIsolated {
            handleMouseUp()
        }
    }

    @MainActor
    private func handleMouseUp() {
        guard let current = gesture else { return }
        gesture = nil
        switch current {
        case .draw:
            if let annotation = draft {
                let length = hypot(annotation.end.x - annotation.start.x, annotation.end.y - annotation.start.y)
                let isTiny = length < 4 && annotation.points.count < 3
                if !isTiny {
                    document.add(annotation)
                }
            }
            draft = nil
        case .move, .handle:
            document.saveProject()
        case .crop:
            if let rect = cropDraft, rect.width > 8, rect.height > 8 {
                document.setCrop(rect)
            }
            cropDraft = nil
        }
        needsDisplay = true
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let handled = MainActor.assumeIsolated {
            handleKey(event)
        }
        if !handled {
            super.keyDown(with: event)
        }
    }

    @MainActor
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = (event.charactersIgnoringModifiers ?? "").lowercased()
        if flags.contains(.command) {
            if key == "z" && flags.contains(.shift) {
                document.redo()
                return true
            }
            if key == "z" {
                document.undo()
                return true
            }
            return false
        }
        switch event.keyCode {
        case 51, 117:
            document.deleteSelected()
            return true
        case 53:
            if document.tool == .crop {
                document.tool = .select
            }
            document.selectedId = nil
            return true
        case 36, 76:
            if document.tool == .crop {
                document.tool = .select
                return true
            }
            if let selected = document.selected, selected.tool == .text {
                beginTextEditing(selected)
                return true
            }
            return false
        case 123, 124, 125, 126:
            nudge(keyCode: event.keyCode, large: flags.contains(.shift))
            return true
        default:
            break
        }
        if key == "+" || key == "=" {
            document.changeSize(by: 1)
            return true
        }
        if key == "-" || key == "_" {
            document.changeSize(by: -1)
            return true
        }
        for tool in AnnotationTool.allCases {
            if let shortcut = tool.keyboardShortcut, String(shortcut) == key {
                document.tool = tool
                return true
            }
        }
        return false
    }

    @MainActor
    private func nudge(keyCode: UInt16, large: Bool) {
        guard var selected = document.selected else { return }
        let step: CGFloat = large ? 10 : 1
        var delta = CGSize.zero
        if keyCode == 123 { delta.width = -step }
        if keyCode == 124 { delta.width = step }
        if keyCode == 125 { delta.height = step }
        if keyCode == 126 { delta.height = -step }
        document.checkpoint()
        selected.move(by: delta)
        document.replace(selected)
        document.saveProject()
        needsDisplay = true
    }

    // MARK: Text editing

    @MainActor
    private func beginTextEditing(_ annotation: Annotation) {
        commitTextEditing()
        document.editingTextId = annotation.id
        document.selectedId = annotation.id
        let field = NSTextField(string: annotation.text)
        field.font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .bold)
        field.textColor = annotation.color.contrastingText
        field.backgroundColor = annotation.color.nsColor
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "Type…"
        field.delegate = self
        field.lineBreakMode = .byClipping
        let padding = annotation.fontSize * 0.45
        let width = max(AnnotationRenderer.textSize(annotation).width, annotation.fontSize * 8)
        field.frame = CGRect(x: annotation.start.x + padding * 0.6, y: annotation.start.y + padding * 0.3, width: width, height: annotation.fontSize * 1.5)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    func controlTextDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let field = textField, let id = document.editingTextId else { return }
            document.setText(field.stringValue, for: id)
            if let annotation = document.annotations.first(where: { item in item.id == id }) {
                let width = max(AnnotationRenderer.textSize(annotation).width, annotation.fontSize * 8)
                field.frame.size.width = width
            }
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        MainActor.assumeIsolated {
            commitTextEditing()
        }
    }

    @MainActor
    private func commitTextEditing() {
        guard let field = textField else { return }
        let id = document.editingTextId
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        textField = nil
        field.delegate = nil
        field.removeFromSuperview()
        document.editingTextId = nil
        if let annotationId = id {
            if text.isEmpty {
                document.delete(annotationId)
            } else {
                document.setText(text, for: annotationId)
            }
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}
