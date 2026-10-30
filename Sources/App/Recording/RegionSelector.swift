import AppKit
import AppCore

/// Full-screen picker for "record an area": drag to draw, drag inside or by the grip above to move,
/// drag the handles on the corners and edges to resize. The pointer shows which of these a drag
/// does. Enter or "Record" confirms, Esc cancels.
@MainActor
final class RegionSelector {
    struct Selection {
        /// The screen most of the area is on.
        var screen: NSScreen
        /// Normalized rect on that screen, origin top-left (beyond 0...1 where the area crosses screens).
        var normalized: CGRect
        /// Global AppKit rect (origin bottom-left) for drawing the frame while recording.
        var global: CGRect

        init(screen: NSScreen, normalized: CGRect, global: CGRect) {
            self.screen = screen
            self.normalized = normalized
            self.global = global
        }

        /// An area anywhere on the desktop, with the screen most of it is on. Nil off every screen.
        init?(global: CGRect) {
            let screens = NSScreen.screens
            var frames: [CGRect] = []
            for screen in screens {
                frames.append(screen.frame)
            }
            guard let index = AreaComposition.mainDisplay(of: global, frames: frames) else { return nil }
            let frame = frames[index]
            let normalized = CGRect(x: (global.minX - frame.minX) / frame.width, y: (frame.maxY - global.maxY) / frame.height, width: global.width / frame.width, height: global.height / frame.height)
            self.init(screen: screens[index], normalized: normalized, global: global)
        }
    }

    /// One panel per screen the area may use; the first is where the picker opened (size bar, keys).
    private var panels: [KeyablePanel] = []
    private var model: RegionPickerModel?

    private var homeView: RegionSelectionView? {
        return panels.first?.contentView as? RegionSelectionView
    }

    /// For automation: the size chips of the open picker, in top-left screen coordinates.
    var chipCenters: [(title: String, point: CGPoint)] {
        guard let view = homeView else { return [] }
        var result: [(title: String, point: CGPoint)] = []
        for chip in view.chipRects {
            result.append((title: chip.title, point: CGPoint(x: view.origin.x + chip.rect.midX, y: view.origin.y + chip.rect.midY)))
        }
        return result
    }

    /// For automation: the selection of the open picker, top-left screen points.
    var selectionOnScreen: CGRect? {
        return model?.selection
    }

    /// For automation: the middle of the grip that moves the area, top-left screen points.
    var gripCenterOnScreen: CGPoint? {
        guard let model, model.hasGrip else { return nil }
        let grip = model.gripRect
        return CGPoint(x: grip.midX, y: grip.midY)
    }

    /// For automation: the screens the open picker covers, top-left screen points, and their scale.
    var screensOnScreen: [(rect: CGRect, scale: CGFloat)] {
        var result: [(rect: CGRect, scale: CGFloat)] = []
        for view in model?.views ?? [] {
            result.append((rect: CGRect(origin: view.origin, size: view.bounds.size), scale: view.pixelScale))
        }
        return result
    }
    private var continuation: CheckedContinuation<Selection?, Never>?

    /// `acrossScreens` lets the area go onto every screen and across them (recording); without it the
    /// area stays on `screen` (a scrolling screenshot reads one display).
    func pick(on screen: NSScreen, initial: CGRect?, confirmTitle: String = L("recording.areaPicker.record"), showsSizes: Bool = true, acrossScreens: Bool = false) async -> Selection? {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            var screens = [screen]
            if acrossScreens {
                for other in NSScreen.screens where other != screen {
                    screens.append(other)
                }
            }
            var frames: [CGRect] = []
            for item in screens {
                frames.append(RegionPickerModel.desktopRect(ofGlobal: item.frame))
            }
            let home = frames[0]
            var start = CGRect(x: home.minX + home.width * 0.2, y: home.minY + home.height * 0.2, width: home.width * 0.6, height: home.height * 0.6)
            if let initial {
                start = initial.offsetBy(dx: home.minX, dy: home.minY)
            }
            let newModel = RegionPickerModel(selection: start, screens: frames)
            newModel.onFinish = { [weak self] rect in
                MainActor.assumeIsolated {
                    self?.finish(rect: rect)
                }
            }
            model = newModel
            for (index, item) in screens.enumerated() {
                let newPanel = KeyablePanel(contentRect: item.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                newPanel.identifier = NSUserInterfaceItemIdentifier("region-picker")
                newPanel.isOpaque = false
                newPanel.backgroundColor = .clear
                // Inside the area nothing is drawn, and macOS passes a click on a fully clear pixel
                // to the window under it: a drag inside never reached the picker. Set, it takes them all.
                newPanel.ignoresMouseEvents = false
                newPanel.level = .screenSaver
                newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                newPanel.isReleasedWhenClosed = false
                let view = RegionSelectionView.screen(of: newModel, frame: frames[index], pixelScale: item.backingScaleFactor, confirmTitle: confirmTitle, showsSizes: showsSizes && index == 0)
                newPanel.contentView = view
                panels.append(newPanel)
            }
            NSApp.activate(ignoringOtherApps: true)
            for other in panels.dropFirst() {
                other.orderFrontRegardless()
            }
            if let first = panels.first, let view = homeView {
                first.makeKeyAndOrderFront(nil)
                first.makeFirstResponder(view)
            }
        }
    }

    private func finish(rect: CGRect?) {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        model = nil
        guard let selected = rect, selected.width > 20, selected.height > 20 else {
            continuation?.resume(returning: nil)
            continuation = nil
            return
        }
        continuation?.resume(returning: Selection(global: RegionPickerModel.globalRect(ofDesktop: selected)))
        continuation = nil
    }

}

/// The area being picked, shared by the picker's screens. Desktop points: x as in AppKit, y down from
/// the top of the first screen (the one with the menu bar), the same as the automation uses; each
/// screen's view only shifts it by its own corner.
@MainActor
final class RegionPickerModel {
    var selection: CGRect {
        didSet {
            for view in views {
                view.needsDisplay = true
            }
        }
    }
    /// The screens the area may use; the first one has the size bar.
    var screens: [CGRect]
    var views: [RegionSelectionView] = []
    var onFinish: ((CGRect?) -> Void)?
    /// The size bar on the first screen, where the grip does not go.
    var barRect: CGRect?
    let handleSize: CGFloat = 12

    init(selection: CGRect, screens: [CGRect]) {
        self.selection = selection
        self.screens = screens
    }

    static func desktopRect(ofGlobal frame: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
    }

    static func globalRect(ofDesktop rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Every screen together: an area is dragged inside this, and must touch a screen.
    var reach: CGRect {
        var union = CGRect.null
        for screen in screens {
            union = union.union(screen)
        }
        return union
    }

    func touchesAScreen(_ rect: CGRect) -> Bool {
        for screen in screens where screen.intersects(rect) {
            return true
        }
        return false
    }

    /// The screen with the area's size label: the one with its top-left corner, or most of it.
    var labelScreen: CGRect {
        for screen in screens where screen.contains(CGPoint(x: selection.minX, y: selection.minY)) {
            return screen
        }
        return mainScreen
    }

    /// Pixels per point of the clip of `rect`: the sharpest screen it is on.
    func clipScale(of rect: CGRect) -> CGFloat? {
        var scale: CGFloat?
        for view in views where CGRect(origin: view.origin, size: view.bounds.size).intersects(rect) {
            scale = max(scale ?? 0, view.pixelScale)
        }
        return scale
    }

    /// The screen most of the area is on, where the size presets and the buttons go.
    var mainScreen: CGRect {
        guard let index = AreaComposition.mainDisplay(of: selection, frames: screens) else { return screens.first ?? .zero }
        return screens[index]
    }

    /// Only an area that is there has a grip; not while the first one is being drawn flat.
    var hasGrip: Bool {
        selection.width > 0 && selection.height > 0
    }

    var gripRect: CGRect {
        RegionSelectionView.gripRect(area: selection, screens: screens, avoiding: barRect, handleSize: handleSize)
    }

    /// Cancel and Record under the area, kept on the screen the area's bottom middle is on (or the
    /// one most of it is on).
    var buttonRects: (record: CGRect, cancel: CGRect) {
        let anchor = CGPoint(x: selection.midX, y: selection.maxY)
        var screen = mainScreen
        for item in screens where item.contains(anchor) {
            screen = item
        }
        let y = min(screen.maxY - 44, selection.maxY + 12)
        let middle = max(screen.minX + 118, min(screen.maxX - 118, selection.midX))
        let record = CGRect(x: middle + 4, y: y, width: 110, height: 32)
        let cancel = CGRect(x: middle - 114, y: y, width: 110, height: 32)
        return (record: record, cancel: cancel)
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

/// One screen of the picker. It draws and edits the shared area (`model`) in its own flipped
/// coordinates: the desktop's, shifted by `origin`, this screen's top-left corner.
final class RegionSelectionView: NSView {
    /// On its own (self-test, pictures) a view is a picker of one screen.
    lazy var model: RegionPickerModel = {
        let own = RegionPickerModel(selection: .zero, screens: [CGRect(origin: origin, size: bounds.size)])
        own.views.append(self)
        ownsModel = true
        return own
    }()
    private var ownsModel = false
    var origin: CGPoint = .zero {
        didSet { updateBar() }
    }
    /// Pixels per point of this screen.
    var pixelScale: CGFloat = 2

    /// The area in this view's coordinates.
    var selection: CGRect {
        get { model.selection.offsetBy(dx: -origin.x, dy: -origin.y) }
        set { model.selection = newValue.offsetBy(dx: origin.x, dy: origin.y) }
    }

    var onFinish: ((CGRect?) -> Void)? {
        get { model.onFinish }
        set { model.onFinish = newValue }
    }

    /// One screen of a picker: `frame` in desktop points. Only the screen with the size bar sets
    /// where the grip keeps clear of.
    static func screen(of model: RegionPickerModel, frame: CGRect, pixelScale: CGFloat, confirmTitle: String, showsSizes: Bool) -> RegionSelectionView {
        let view = RegionSelectionView(frame: CGRect(origin: .zero, size: frame.size))
        view.model = model
        view.showsSizes = showsSizes
        view.origin = frame.origin
        view.pixelScale = pixelScale
        view.confirmTitle = confirmTitle
        model.views.append(view)
        return view
    }

    var confirmTitle = L("recording.areaPicker.record")
    /// The ready-made size bar; off where sizes make no sense (scrolling screenshots), and on every
    /// screen but the one the picker opened on.
    var showsSizes = true {
        didSet { updateBar() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if ownsModel {
            model.screens = [CGRect(origin: origin, size: newSize)]
        }
        updateBar()
    }

    /// The grip keeps clear of the size bar; a view without one leaves the bar to the view that has it.
    private func updateBar() {
        guard let bar = presetBarRect?.offsetBy(dx: origin.x, dy: origin.y) else { return }
        if showsSizes {
            model.barRect = bar
        } else if model.barRect == bar {
            model.barRect = nil
        }
    }

    /// A rect of the desktop in this view's coordinates.
    private func local(_ rect: CGRect) -> CGRect {
        return rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private enum DragMode {
        case create(CGPoint)
        /// A handle or the whole area (AreaEdges.all), where the drag started, the area then.
        case grab(AreaEdges, CGPoint, CGRect)
    }

    private var dragMode: DragMode?
    private var handleSize: CGFloat { model.handleSize }

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

    /// The dark bar behind the size chips.
    private var presetBarRect: CGRect? {
        let rects = presetRects
        guard let first = rects.first, let last = rects.last else { return nil }
        return CGRect(x: first.minX - 52, y: first.minY - 6, width: last.maxX - first.minX + 60, height: first.height + 12)
    }

    var hasGrip: Bool {
        model.hasGrip
    }

    var gripRect: CGRect {
        local(model.gripRect)
    }

    /// The grip that moves the area, as on the recording frame: centered above the area, out of the
    /// top handle's reach (a press there resizes); inside the area when no screen has room for it
    /// above or the size bar is in the way (flipped coordinates).
    static func gripRect(area: CGRect, screens: [CGRect], avoiding bar: CGRect?, handleSize: CGFloat) -> CGRect {
        let size = AreaHandleView.gripSize
        let gap = handleSize + 4
        var grip = CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.minY - gap - size.height).rounded(), width: size.width, height: size.height)
        var onAScreen = false
        for screen in screens where screen.contains(grip) {
            onAScreen = true
        }
        if !onAScreen || bar?.intersects(grip) == true {
            grip.origin.y = (area.minY + gap).rounded()
        }
        return grip
    }

    var chipRects: [(title: String, rect: CGRect)] {
        var result: [(title: String, rect: CGRect)] = []
        for (index, rect) in presetRects.enumerated() {
            result.append((title: presets[index].title, rect: rect))
        }
        return result
    }

    /// A size preset goes on the screen most of the area is on.
    private func apply(_ preset: SizePreset) {
        let screen = local(model.mainScreen)
        // A pixel size is what the clip gets: at the density of the sharpest screen the area is on.
        let scale = model.clipScale(of: model.selection) ?? pixelScale
        var size = selection.size
        switch preset.kind {
        case .fullScreen:
            selection = screen
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
        let fit = min(1, screen.width / size.width, screen.height / size.height)
        size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
        var center = CGPoint(x: selection.midX, y: selection.midY)
        if selection.width < 1 || selection.height < 1 {
            center = CGPoint(x: screen.midX, y: screen.midY)
        }
        var corner = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        corner.x = max(screen.minX, min(screen.maxX - size.width, corner.x))
        corner.y = max(screen.minY, min(screen.maxY - size.height, corner.y))
        selection = CGRect(origin: corner, size: size)
        // Moved onto other screens, the area may have another density now: size it again for that.
        if case .pixels(let pixels) = preset.kind, let placed = model.clipScale(of: model.selection), placed != scale {
            let exact = CGSize(width: (pixels.width / placed).rounded(), height: (pixels.height / placed).rounded())
            selection = CGRect(x: selection.midX - exact.width / 2, y: selection.midY - exact.height / 2, width: exact.width, height: exact.height)
        }
        announceLayoutChange()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The picker keeps an area at least this big; a smaller one is not recorded.
    private let minimumSide: CGFloat = 24

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    /// What the pointer is over: a button or size chip, a handle, the area or the screen around it.
    private func updateCursor(at point: CGPoint) {
        var onControl = buttonRects.record.contains(point) || buttonRects.cancel.contains(point)
        for rect in presetRects where showsSizes && rect.contains(point) {
            onControl = true
        }
        if onControl {
            NSCursor.arrow.set()
            return
        }
        if hasGrip && gripRect.contains(point) {
            NSCursor.openHand.set()
            return
        }
        RegionSelectionView.cursor(for: AreaCursor.at(point, area: selection, reach: handleSize)).set()
    }

    static func cursor(for kind: AreaCursor) -> NSCursor {
        switch kind {
        case .move:
            return .openHand
        case .leftRight:
            return .resizeLeftRight
        case .upDown:
            return .resizeUpDown
        case .corner, .draw:
            return .crosshair
        }
    }

    private var buttonRects: (record: CGRect, cancel: CGRect) {
        let buttons = model.buttonRects
        return (record: local(buttons.record), cancel: local(buttons.cancel))
    }

    /// The buttons are on this screen (the others draw nothing there and do not list them).
    private var hasButtons: Bool {
        let buttons = buttonRects
        return bounds.contains(CGPoint(x: buttons.cancel.maxX, y: buttons.cancel.midY))
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

        for edges in AreaEdges.handles {
            let corner = edges.point(on: selection)
            let handle = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2, width: handleSize, height: handleSize)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: handle).fill()
            NSColor(hex: 0xFF6B4A).setStroke()
            NSBezierPath(ovalIn: handle).stroke()
        }

        if hasGrip {
            AreaHandleView.drawGrip(in: gripRect)
        }

        // The clip takes the density of the sharpest screen the area is on.
        let scale = model.clipScale(of: model.selection) ?? pixelScale
        let label = "\(Int(selection.width * scale)) × \(Int(selection.height * scale))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        // One label, on the screen with the area's top-left corner.
        if CGRect(origin: origin, size: bounds.size) == model.labelScreen {
            let labelSize = label.size(withAttributes: attributes)
            var labelRect = CGRect(x: selection.minX, y: max(0, selection.minY - labelSize.height - 10), width: labelSize.width + 12, height: labelSize.height + 6)
            if hasGrip {
                labelRect = AreaResize.label(labelRect, clearOf: gripRect, gap: 4)
            }
            NSColor(hex: 0x1C1D20, alpha: 0.9).setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
            label.draw(at: CGPoint(x: labelRect.minX + 6, y: labelRect.minY + 3), withAttributes: attributes)
        }

        if showsSizes {
            drawPresetBar()
        }
        if hasButtons {
            drawButton(buttonRects.cancel, title: L("recording.areaPicker.cancel.withKey"), fill: NSColor(hex: 0x2B2D31), text: .white)
            drawButton(buttonRects.record, title: confirmTitle, fill: NSColor(hex: 0xFF6B4A), text: NSColor(hex: 0x1A0B06))
        }
    }

    private func drawPresetBar() {
        let rects = presetRects
        guard showsSizes, let first = rects.first, let bar = presetBarRect else { return }
        NSColor(hex: 0x1C1D20, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 9, yRadius: 9).fill()
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: presetFont, .foregroundColor: NSColor(white: 1, alpha: 0.6)]
        (L("recording.areaPicker.size") as NSString).draw(at: CGPoint(x: bar.minX + 12, y: first.midY - 8), withAttributes: labelAttributes)
        let scale = model.clipScale(of: model.selection) ?? pixelScale
        for (index, preset) in presets.enumerated() {
            var isCurrent = false
            switch preset.kind {
            case .pixels(let pixels):
                isCurrent = abs(selection.width * scale - pixels.width) < 2 && abs(selection.height * scale - pixels.height) < 2
            case .points(let points):
                isCurrent = abs(selection.width - points.width) < 1 && abs(selection.height - points.height) < 1
            case .fullScreen:
                isCurrent = selection == local(model.mainScreen)
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
        let showsButtons = hasButtons
        let layout = "\(showsSizes)|\(confirmTitle)|\(showsButtons)"
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
        if showsButtons {
            buttons.append(DrawnButton(label: L("recording.areaPicker.cancel"), view: self, rect: { [weak self] in
                self?.buttonRects.cancel ?? .zero
            }, action: { [weak self] in
                self?.model.onFinish?(nil)
            }))
            let confirmLabel = confirmTitle.components(separatedBy: "  ").first ?? confirmTitle
            buttons.append(DrawnButton(label: confirmLabel, view: self, rect: { [weak self] in
                self?.buttonRects.record ?? .zero
            }, action: { [weak self] in
                guard let view = self else { return }
                view.model.onFinish?(view.model.selection)
            }))
        }
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

    /// The buttons moved with the selection, maybe to another screen.
    private func announceLayoutChange() {
        for view in model.views {
            NSAccessibility.post(element: view, notification: .layoutChanged)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, rect) in presetRects.enumerated() where showsSizes && rect.contains(point) {
            apply(presets[index])
            return
        }
        if hasButtons && buttonRects.record.contains(point) {
            model.onFinish?(model.selection)
            return
        }
        if hasButtons && buttonRects.cancel.contains(point) {
            model.onFinish?(nil)
            return
        }
        if hasGrip && gripRect.contains(point) {
            dragMode = .grab(.all, point, selection)
            NSCursor.closedHand.set()
            return
        }
        if let edges = AreaEdges.grabbed(at: point, area: selection, reach: handleSize) {
            dragMode = .grab(edges, point, selection)
            if edges == .all {
                NSCursor.closedHand.set()
            }
            return
        }
        dragMode = .create(point)
        selection = CGRect(origin: point, size: .zero)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let mode = dragMode else { return }
        // Every screen of the picker together; the area may cross from one to another.
        let reach = local(model.reach)
        var dragged = selection
        switch mode {
        case .create(let start):
            let end = CGPoint(x: max(reach.minX, min(reach.maxX, point.x)), y: max(reach.minY, min(reach.maxY, point.y)))
            dragged = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        case .grab(let edges, let start, let original):
            // Along the edge of a screen where the next one is shorter, instead of stopping.
            let desktop = original.offsetBy(dx: origin.x, dy: origin.y)
            if let onScreens = AreaResize.dragged(desktop, edges: edges, dx: point.x - start.x, dy: point.y - start.y, screens: model.screens, minimum: minimumSide) {
                selection = local(onScreens)
            }
            return
        }
        // Between screens of different sizes part of the reach is no screen: the area keeps a foot on one.
        if model.touchesAScreen(dragged.offsetBy(dx: origin.x, dy: origin.y)) {
            selection = dragged
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragMode != nil {
            announceLayoutChange()
        }
        dragMode = nil
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            model.onFinish?(nil)
        } else if event.keyCode == 36 || event.keyCode == 76 {
            model.onFinish?(model.selection)
        } else {
            super.keyDown(with: event)
        }
    }
}
