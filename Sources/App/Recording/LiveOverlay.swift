import AppKit
import AppCore
import Observation
import QuartzCore

/// Transparent full-screen window for drawing on the screen while recording.
/// It is the one window of ours that the buffer is allowed to capture.
@MainActor
@Observable
final class LiveOverlay {
    static let liveTools: [AnnotationTool] = [.arrow, .text, .rectangle, .ellipse, .pen, .highlighter, .step]
    /// Text typed on the screen, in points.
    static let textSize: CGFloat = 26

    var isDrawing = false {
        didSet { applyDrawingState() }
    }
    var tool: AnnotationTool = .arrow
    var color: AnnotationColor = .coral
    var stroke: StrokeSize = .thick
    /// Marks fade out after a few seconds so the screen stays usable.
    var autoFade = true
    private(set) var annotations: [(annotation: Annotation, createdAt: Double)] = []

    @ObservationIgnored private var window: NSPanel?
    @ObservationIgnored private var drawingView: OverlayDrawingView?
    @ObservationIgnored private var fadeTimer: Timer?
    @ObservationIgnored var onVisibilityChange: ((Int?) -> Void)?

    static let fadeDelay = 3.0
    static let fadeDuration = 0.8

    var windowNumber: Int? {
        guard let window = window, window.isVisible else { return nil }
        return window.windowNumber
    }

    func show(on frame: CGRect) {
        if window == nil {
            let panel = KeyablePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = false
            let view = OverlayDrawingView(frame: CGRect(origin: .zero, size: frame.size))
            view.overlay = self
            panel.contentView = view
            window = panel
            drawingView = view
        }
        window?.setFrame(frame, display: true)
        window?.orderFrontRegardless()
        applyDrawingState()
        onVisibilityChange?(window?.windowNumber)
    }

    func hide() {
        drawingView?.endText(keeping: false)
        isDrawing = false
        annotations.removeAll()
        drawingView?.needsDisplay = true
        window?.orderOut(nil)
        onVisibilityChange?(nil)
    }

    var isVisible: Bool {
        return window?.isVisible ?? false
    }

    /// Where the drawing window is, in screen coordinates.
    var frame: CGRect {
        return window?.frame ?? .zero
    }

    /// For tests: where the drawing window is (top-left screen points) and whether it takes the mouse.
    var stateForChecks: String {
        guard let panel = window else { return "window=none" }
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = panel.frame
        let viewSize = drawingView?.bounds.size ?? .zero
        let lastText = (annotations.last?.annotation.text ?? "").replacingOccurrences(of: " ", with: "_")
        return "visible=\(panel.isVisible) drawing=\(isDrawing) key=\(panel.isKeyWindow) mouse=\(!panel.ignoresMouseEvents) x=\(Int(frame.minX)) y=\(Int(mainHeight - frame.maxY)) w=\(Int(frame.width)) h=\(Int(frame.height)) view=\(Int(viewSize.width))x\(Int(viewSize.height)) marks=\(annotations.count) lastKind=\(annotations.last?.annotation.tool.rawValue ?? "none") lastText=\(lastText) typing=\(drawingView?.isTyping ?? false)"
    }

    private func applyDrawingState() {
        guard let panel = window else { return }
        if !isDrawing {
            // Text being typed stays on the screen when drawing ends.
            drawingView?.endText(keeping: true)
        }
        panel.ignoresMouseEvents = !isDrawing
        // The tint shows at once, and the window is no longer fully clear: macOS lets clicks pass
        // through fully clear windows, and nothing was drawn.
        drawingView?.needsDisplay = true
        if isDrawing {
            panel.makeKey()
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
        drawingView?.window?.invalidateCursorRects(for: drawingView!)
    }

    var lineWidth: CGFloat {
        return stroke.width * 1.5
    }

    var nextStepNumber: Int {
        var highest = 0
        for item in annotations where item.annotation.tool == .step {
            highest = max(highest, item.annotation.number)
        }
        return highest + 1
    }

    func add(_ annotation: Annotation) {
        annotations.append((annotation: annotation, createdAt: CACurrentMediaTime()))
        startFadeTimerIfNeeded()
        drawingView?.needsDisplay = true
    }

    func undo() {
        if !annotations.isEmpty {
            annotations.removeLast()
            drawingView?.needsDisplay = true
        }
    }

    func clear() {
        annotations.removeAll()
        drawingView?.needsDisplay = true
    }

    /// Opacity for an annotation right now (1 while fresh, then fading to 0).
    func opacity(createdAt: Double, now: Double) -> CGFloat {
        if !autoFade { return 1 }
        let age = now - createdAt
        if age < LiveOverlay.fadeDelay { return 1 }
        let progress = (age - LiveOverlay.fadeDelay) / LiveOverlay.fadeDuration
        return CGFloat(max(0, 1 - progress))
    }

    private func startFadeTimerIfNeeded() {
        if fadeTimer != nil { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        guard autoFade else {
            fadeTimer?.invalidate()
            fadeTimer = nil
            return
        }
        let now = CACurrentMediaTime()
        let limit = LiveOverlay.fadeDelay + LiveOverlay.fadeDuration
        annotations.removeAll { item in now - item.createdAt > limit }
        drawingView?.needsDisplay = true
        if annotations.isEmpty {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }

    /// Drawing finished: restart the fade clock so the mark stays visible after release.
    func refreshLast() {
        if annotations.isEmpty { return }
        annotations[annotations.count - 1].createdAt = CACurrentMediaTime()
    }
}

final class OverlayDrawingView: NSView, NSTextFieldDelegate {
    weak var overlay: LiveOverlay?
    private var draft: Annotation?
    /// The text being typed with the Text tool, where it was clicked.
    private var textField: NSTextField?
    private var textStart: CGPoint = .zero

    var isTyping: Bool {
        return textField != nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if overlay?.isDrawing == true {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let overlay = overlay else { return }
        let now = CACurrentMediaTime()
        if overlay.isDrawing {
            // A faint tint tells the user clicks now draw instead of reaching apps.
            NSColor(hex: 0x9B6BFF, alpha: 0.06).setFill()
            bounds.fill()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
            border.lineWidth = 4
            NSColor(hex: 0x9B6BFF, alpha: 0.6).setStroke()
            border.stroke()
        }
        for item in overlay.annotations {
            let alpha = overlay.opacity(createdAt: item.createdAt, now: now)
            if alpha <= 0 { continue }
            context.saveGState()
            context.setAlpha(alpha)
            AnnotationRenderer.draw([item.annotation], baseImage: nil, in: context)
            context.restoreGState()
        }
        if let current = draft {
            AnnotationRenderer.draw([current], baseImage: nil, in: context)
        }
        // The label as it will be, drawn by the same code; the field on top only takes the keys.
        if let typing = typingAnnotation() {
            AnnotationRenderer.draw([typing], baseImage: nil, in: context)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let overlay = overlay, overlay.isDrawing else { return }
        // A click away from the text being typed keeps it, the way Return does.
        let wasTyping = isTyping
        endText(keeping: true)
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if overlay.tool == .text {
            if !wasTyping {
                beginText(at: point)
            }
            return
        }
        var annotation = Annotation(tool: overlay.tool, start: point, end: point, color: overlay.color, lineWidth: overlay.lineWidth)
        annotation.fontSize = 22
        if overlay.tool == .pen || overlay.tool == .highlighter {
            annotation.points = [point]
        }
        if overlay.tool == .step {
            annotation.number = overlay.nextStepNumber
            overlay.add(annotation)
            return
        }
        draft = annotation
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = draft else { return }
        let point = convert(event.locationInWindow, from: nil)
        current.end = point
        if current.tool == .pen || current.tool == .highlighter {
            current.points.append(point)
        }
        draft = current
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = draft, let overlay = overlay else { return }
        draft = nil
        let isTiny = hypot(current.end.x - current.start.x, current.end.y - current.start.y) < 4 && current.points.count < 3
        if !isTiny {
            overlay.add(current)
        }
        needsDisplay = true
    }

    // MARK: Text

    /// The text mark being typed, as it will be kept.
    private func typingAnnotation() -> Annotation? {
        guard let field = textField, let overlay = overlay else { return nil }
        var annotation = Annotation(tool: .text, start: textStart, end: textStart, color: overlay.color, lineWidth: overlay.lineWidth)
        annotation.fontSize = LiveOverlay.textSize
        annotation.text = field.stringValue
        return annotation
    }

    /// Typing goes into a real text field, so any keyboard layout, input method and paste work.
    /// The field itself is clear and sits exactly on the label's text: what shows is the label
    /// drawn by the renderer, the same as after Return, plus the field's caret.
    private func beginText(at point: CGPoint) {
        guard let overlay = overlay else { return }
        textStart = point
        let field = NSTextField(frame: .zero)
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = false
        field.textColor = .clear
        field.font = NSFont.systemFont(ofSize: LiveOverlay.textSize, weight: .bold)
        field.delegate = self
        field.setAccessibilityLabel(L("recording.drawing.textField"))
        addSubview(field)
        textField = field
        placeTextField()
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = overlay.color.contrastingText
        }
        needsDisplay = true
    }

    /// Over the label's text: the renderer pads it by 0.45 of the font size (0.27 at the top); the
    /// field's own inset is 2 pt.
    private func placeTextField() {
        guard let field = textField, let typing = typingAnnotation() else { return }
        let size = AnnotationRenderer.textSize(typing)
        let padding = LiveOverlay.textSize * 0.45
        let width = min(size.width, max(40, bounds.maxX - textStart.x))
        field.frame = CGRect(x: textStart.x + padding - 2, y: textStart.y + padding * 0.6 - 1, width: width, height: size.height - padding * 0.6)
    }

    /// Ends typing: the text becomes a mark (empty text is dropped), or goes with `keeping` false.
    func endText(keeping: Bool) {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.delegate = nil
        field.removeFromSuperview()
        if keeping && !text.isEmpty, let overlay = overlay {
            var annotation = Annotation(tool: .text, start: textStart, end: textStart, color: overlay.color, lineWidth: overlay.lineWidth)
            annotation.fontSize = LiveOverlay.textSize
            annotation.text = text
            overlay.add(annotation)
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func controlTextDidChange(_ notification: Notification) {
        placeTextField()
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            endText(keeping: true)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endText(keeping: false)
            return true
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        guard let overlay = overlay else { return }
        if event.keyCode == 53 {
            overlay.isDrawing = false
            return
        }
        let key = LatinKeys.key(forKeyCode: event.keyCode, typed: event.charactersIgnoringModifiers ?? "")
        if event.modifierFlags.contains(.command), key == "z" {
            overlay.undo()
            return
        }
        if event.keyCode == 51 {
            overlay.clear()
            return
        }
        for tool in LiveOverlay.liveTools {
            if let shortcut = tool.keyboardShortcut, String(shortcut) == key {
                overlay.tool = tool
                return
            }
        }
        super.keyDown(with: event)
    }
}

/// Borderless panels refuse key status by default; the overlay and HUD need keyboard input.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
