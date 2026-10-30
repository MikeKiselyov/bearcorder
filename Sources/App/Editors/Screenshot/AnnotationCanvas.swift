import AppKit
import AppCore
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
        canvas.refreshTypingField()
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
        case cropResize(edges: CropEdges, original: CGRect)
        case cropMove(start: CGPoint, original: CGRect)
    }

    /// Which sides of the crop area a handle moves.
    private struct CropEdges {
        var left = false
        var right = false
        var top = false
        var bottom = false
    }

    private var gesture: Gesture?
    private var draft: Annotation?
    private var cropDraft: CGRect?
    private var textField: NSTextField?

    init(document: ScreenshotDocument) {
        self.document = document
        super.init(frame: CGRect(origin: .zero, size: document.imageSize))
        updateGeometry()
        // Drop screenshots or picture files on the canvas to place them on top.
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    // MARK: Placed pictures

    /// ⌘V with a picture on the clipboard places it in the middle. Nil when there is none.
    @MainActor
    func pasteImage() -> Bool {
        guard let image = CanvasView.image(from: NSPasteboard.general) else { return false }
        document.insertImage(image)
        needsDisplay = true
        return true
    }

    /// The first picture on a pasteboard: a file of an image type, or image data.
    static func image(from pasteboard: NSPasteboard) -> CGImage? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                if let image = ImageFiles.load(url) {
                    return image
                }
            }
        }
        if let picture = NSImage(pasteboard: pasteboard) {
            var rect = CGRect(origin: .zero, size: picture.size)
            return picture.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if CanvasView.image(from: sender.draggingPasteboard) == nil {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return MainActor.assumeIsolated {
            guard let image = CanvasView.image(from: sender.draggingPasteboard) else { return false }
            let point = convert(sender.draggingLocation, from: nil)
            document.insertImage(image, at: point)
            needsDisplay = true
            return true
        }
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

        // Thirds while the area changes, to line things up.
        if cropDraft != nil {
            let thirds = NSBezierPath()
            for step in [CGFloat(1), CGFloat(2)] {
                let x = area.minX + area.width * step / 3
                let y = area.minY + area.height * step / 3
                thirds.move(to: CGPoint(x: x, y: area.minY))
                thirds.line(to: CGPoint(x: x, y: area.maxY))
                thirds.move(to: CGPoint(x: area.minX, y: y))
                thirds.line(to: CGPoint(x: area.maxX, y: y))
            }
            thirds.lineWidth = 1 / magnification
            NSColor.white.withAlphaComponent(0.35).setStroke()
            thirds.stroke()
        }

        for handle in cropHandles(for: area) {
            let size = (handle.isCorner ? 12 : 10) / magnification
            let square = CGRect(x: handle.point.x - size / 2, y: handle.point.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(rect: square).fill()
            let ring = NSBezierPath(rect: square)
            ring.lineWidth = 1 / magnification
            NSColor(hex: 0x1C1D20).setStroke()
            ring.stroke()
        }

        drawCropSize(area)
    }

    /// "1280 × 720" in a small label above the crop area (inside it when there is no room).
    @MainActor
    private func drawCropSize(_ area: CGRect) {
        let label = "\(Int(area.width)) × \(Int(area.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12 / magnification, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = label.size(withAttributes: attributes)
        let padding = 5 / magnification
        var origin = CGPoint(x: area.minX, y: area.minY - textSize.height - padding * 3)
        if origin.y < 0 {
            origin.y = area.minY + padding
            origin.x = area.minX + padding
        }
        let box = CGRect(x: origin.x, y: origin.y, width: textSize.width + padding * 2, height: textSize.height + padding)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: padding, yRadius: padding).fill()
        label.draw(at: CGPoint(x: box.minX + padding, y: box.minY + padding / 2), withAttributes: attributes)
    }

    /// Corner and edge handles of the crop area.
    private func cropHandles(for area: CGRect) -> [(point: CGPoint, edges: CropEdges, isCorner: Bool)] {
        var handles: [(point: CGPoint, edges: CropEdges, isCorner: Bool)] = []
        handles.append((CGPoint(x: area.minX, y: area.minY), CropEdges(left: true, top: true), true))
        handles.append((CGPoint(x: area.maxX, y: area.minY), CropEdges(right: true, top: true), true))
        handles.append((CGPoint(x: area.minX, y: area.maxY), CropEdges(left: true, bottom: true), true))
        handles.append((CGPoint(x: area.maxX, y: area.maxY), CropEdges(right: true, bottom: true), true))
        handles.append((CGPoint(x: area.midX, y: area.minY), CropEdges(top: true), false))
        handles.append((CGPoint(x: area.midX, y: area.maxY), CropEdges(bottom: true), false))
        handles.append((CGPoint(x: area.minX, y: area.midY), CropEdges(left: true), false))
        handles.append((CGPoint(x: area.maxX, y: area.midY), CropEdges(right: true), false))
        return handles
    }

    /// The handle under the pointer, if any. Edges count along their whole length.
    private func cropEdges(at point: CGPoint, area: CGRect) -> CropEdges? {
        let tolerance = 10 / magnification
        for handle in cropHandles(for: area) where handle.isCorner {
            if hypot(point.x - handle.point.x, point.y - handle.point.y) <= tolerance * 1.4 {
                return handle.edges
            }
        }
        let insideX = point.x > area.minX - tolerance && point.x < area.maxX + tolerance
        let insideY = point.y > area.minY - tolerance && point.y < area.maxY + tolerance
        if insideY && abs(point.x - area.minX) <= tolerance {
            return CropEdges(left: true)
        }
        if insideY && abs(point.x - area.maxX) <= tolerance {
            return CropEdges(right: true)
        }
        if insideX && abs(point.y - area.minY) <= tolerance {
            return CropEdges(top: true)
        }
        if insideX && abs(point.y - area.maxY) <= tolerance {
            return CropEdges(bottom: true)
        }
        return nil
    }

    private var fullImageRect: CGRect {
        return CGRect(origin: .zero, size: document.imageSize)
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
        case .arrow, .callout, .line, .rectangle, .ellipse, .blur, .magnifier, .image:
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
                if event.clickCount == 2 && annotation.tool.hasLabel {
                    beginTextEditing(annotation)
                    return
                }
                document.checkpoint()
                gesture = .move(start: point, original: annotation)
                return
            }
            document.selectedId = nil
        case .crop:
            // Drag an edge or corner to resize, inside to move, outside to draw a new area.
            let area = document.crop ?? fullImageRect
            if let edges = cropEdges(at: point, area: area) {
                gesture = .cropResize(edges: edges, original: area)
                cropDraft = area
            } else if area.contains(point) && area != fullImageRect {
                gesture = .cropMove(start: point, original: area)
                cropDraft = area
                NSCursor.closedHand.set()
            } else {
                gesture = .crop(start: point)
                cropDraft = CGRect(origin: point, size: .zero)
            }
        case .text:
            var annotation = Annotation(tool: .text, start: point, end: point, color: document.color, lineWidth: document.lineWidth)
            annotation.clearBackground = document.clearTextBackground
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
            if document.tool == .rectangle || document.tool == .ellipse {
                annotation.fill = document.shapeFill
            }
            if document.tool == .callout {
                annotation.clearBackground = document.clearTextBackground
                annotation.labelArea = CGRect(origin: .zero, size: document.imageSize)
            }
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
            if original.tool == .image {
                resized = keepingProportions(resized, original: original, movedStart: isStart)
            }
            document.replace(resized)
        case .crop(let start):
            let full = fullImageRect
            let clamped = CGPoint(x: max(full.minX, min(full.maxX, point.x)), y: max(full.minY, min(full.maxY, point.y)))
            cropDraft = CGRect(x: min(start.x, clamped.x), y: min(start.y, clamped.y), width: abs(clamped.x - start.x), height: abs(clamped.y - start.y))
        case .cropResize(let edges, let original):
            cropDraft = resized(original, edges: edges, to: point)
        case .cropMove(let start, let original):
            let full = fullImageRect
            var moved = original
            moved.origin.x = max(full.minX, min(full.maxX - original.width, original.minX + point.x - start.x))
            moved.origin.y = max(full.minY, min(full.maxY - original.height, original.minY + point.y - start.y))
            cropDraft = moved.integral
        }
        needsDisplay = true
    }

    /// The crop area with the dragged sides moved to the pointer, inside the image and at least
    /// 16 px wide and tall.
    private func resized(_ original: CGRect, edges: CropEdges, to point: CGPoint) -> CGRect {
        let full = fullImageRect
        let smallest: CGFloat = 16
        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY
        if edges.left {
            minX = max(full.minX, min(point.x, maxX - smallest))
        }
        if edges.right {
            maxX = min(full.maxX, max(point.x, minX + smallest))
        }
        if edges.top {
            minY = max(full.minY, min(point.y, maxY - smallest))
        }
        if edges.bottom {
            maxY = min(full.maxY, max(point.y, minY + smallest))
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    /// A placed picture keeps its proportions while a corner is dragged; the other corner stays.
    private func keepingProportions(_ resized: Annotation, original: Annotation, movedStart: Bool) -> Annotation {
        let ratio = original.rect.width / max(1, original.rect.height)
        var result = resized
        let fixed = movedStart ? original.end : original.start
        let moved = movedStart ? resized.start : resized.end
        var width = abs(moved.x - fixed.x)
        var height = width / max(0.01, ratio)
        if abs(moved.y - fixed.y) > height {
            height = abs(moved.y - fixed.y)
            width = height * ratio
        }
        var corner = CGPoint(x: fixed.x + width, y: fixed.y + height)
        if moved.x < fixed.x {
            corner.x = fixed.x - width
        }
        if moved.y < fixed.y {
            corner.y = fixed.y - height
        }
        if movedStart {
            result.start = corner
        } else {
            result.end = corner
        }
        return result
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
            handleMouseUp(event)
        }
    }

    @MainActor
    private func handleMouseUp(_ event: NSEvent) {
        guard let current = gesture else { return }
        gesture = nil
        switch current {
        case .draw:
            if let annotation = draft {
                let length = hypot(annotation.end.x - annotation.start.x, annotation.end.y - annotation.start.y)
                let isTiny = length < 4 && annotation.points.count < 3
                if !isTiny {
                    finishDrawing(annotation)
                }
            }
            draft = nil
        case .move, .handle:
            document.saveProject()
        case .crop, .cropResize, .cropMove:
            if let rect = cropDraft, rect.width > 8, rect.height > 8 {
                if rect == fullImageRect {
                    document.setCrop(nil)
                } else if rect != document.crop {
                    document.setCrop(rect)
                }
            }
            cropDraft = nil
            updateCropCursor(at: convert(event.locationInWindow, from: nil))
        }
        needsDisplay = true
    }

    // MARK: Crop cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        MainActor.assumeIsolated {
            updateCropCursor(at: convert(event.locationInWindow, from: nil))
        }
    }

    /// Resize arrows over the crop edges, a hand inside the area, a crosshair elsewhere.
    @MainActor
    private func updateCropCursor(at point: CGPoint) {
        guard document.tool == .crop else { return }
        let area = document.crop ?? fullImageRect
        if let edges = cropEdges(at: point, area: area) {
            let horizontal = edges.left || edges.right
            let vertical = edges.top || edges.bottom
            if horizontal && vertical {
                NSCursor.crosshair.set()
            } else if horizontal {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.resizeUpDown.set()
            }
        } else if area.contains(point) && area != fullImageRect {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
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
        // By key, not by character: with a Russian layout V types "м" and ⌘V still pastes.
        let key = LatinKeys.key(forKeyCode: event.keyCode, typed: event.charactersIgnoringModifiers ?? "")
        if flags.contains(.command) {
            if key == "z" && flags.contains(.shift) {
                document.redo()
                return true
            }
            if key == "z" {
                document.undo()
                return true
            }
            if key == "v" {
                return pasteImage()
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
            if let selected = document.selected, selected.tool.hasLabel {
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
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        field.lineBreakMode = .byClipping
        style(field, as: annotation)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        // The field editor exists now; it takes the caret color.
        style(field, as: annotation)
    }

    /// The typing field is see-through and only shows the caret: the canvas draws the text as it
    /// will look, label or outline. Drawing the text in the field too showed it twice.
    @MainActor
    private func style(_ field: NSTextField, as annotation: Annotation) {
        field.font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .bold)
        field.textColor = .clear
        field.drawsBackground = false
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = annotation.hasClearBackground ? annotation.color.nsColor : annotation.color.contrastingText
            editor.textColor = .clear
        }
        let padding = annotation.fontSize * 0.45
        let width = max(AnnotationRenderer.textSize(annotation).width, annotation.fontSize * 8)
        var origin = annotation.start
        if annotation.tool == .callout {
            origin = AnnotationRenderer.calloutLabelBox(annotation).origin
        }
        field.frame = CGRect(x: origin.x + padding * 0.6, y: origin.y + padding * 0.3, width: width, height: annotation.fontSize * 1.5)
    }

    /// Background, color or size changed while typing: the field shows it right away.
    @MainActor
    func refreshTypingField() {
        guard let field = textField, let id = document.editingTextId else { return }
        guard let annotation = document.annotations.first(where: { item in item.id == id }) else { return }
        style(field, as: annotation)
    }

    /// A drawn mark goes on the picture; an arrow with text opens its note for typing right away.
    @MainActor
    private func finishDrawing(_ annotation: Annotation) {
        document.add(annotation)
        if annotation.tool == .callout {
            beginTextEditing(annotation)
        }
    }

    /// For checks: what a drag with the current tool from `start` to `end` leaves.
    @MainActor
    func drawForChecks(from start: CGPoint, to end: CGPoint) {
        var annotation = Annotation(tool: document.tool, start: start, end: end, color: document.color, lineWidth: document.lineWidth)
        annotation.fontSize = document.fontSize
        annotation.clearBackground = document.clearTextBackground
        annotation.labelArea = CGRect(origin: .zero, size: document.imageSize)
        finishDrawing(annotation)
    }

    /// For checks: types `text` into the open note and finishes it, as Return does.
    @MainActor
    func finishTypingForChecks(_ text: String) {
        guard let field = textField else { return }
        field.stringValue = text
        commitTextEditing()
    }

    /// For checks: what a click with the Text tool does at `point`.
    @MainActor
    func startTypingForChecks(at point: CGPoint) {
        var annotation = Annotation(tool: .text, start: point, end: point, color: document.color, lineWidth: document.lineWidth)
        annotation.clearBackground = document.clearTextBackground
        annotation.fontSize = document.fontSize
        document.add(annotation)
        beginTextEditing(annotation)
    }

    /// For checks: whether the typing field draws anything besides the caret.
    var typingFieldDrawsText: Bool? {
        guard let field = textField else { return nil }
        return field.drawsBackground || field.textColor != .clear
    }

    func controlTextDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let field = textField, let id = document.editingTextId else { return }
            document.setText(field.stringValue, for: id)
            if let annotation = document.annotations.first(where: { item in item.id == id }) {
                // A note left of or above its arrow grows away from it, so the field moves too.
                style(field, as: annotation)
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
            let isCallout = document.annotations.first(where: { item in item.id == annotationId })?.tool == .callout
            if text.isEmpty && isCallout {
                // No note typed: the arrow stays, as a plain arrow.
                document.makePlainArrow(annotationId)
            } else if text.isEmpty {
                document.delete(annotationId)
            } else {
                document.setText(text, for: annotationId)
            }
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}
