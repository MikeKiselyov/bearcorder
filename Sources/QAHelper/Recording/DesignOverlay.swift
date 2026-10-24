import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A design mockup floating over the real app, half see-through, for pixel-perfect checks.
/// Drag it to line up (arrows nudge by 1 pt, Shift by 10), then turn on "Click through" to use the app under it.
@MainActor
@Observable
final class DesignOverlay {
    static let shared = DesignOverlay()

    var opacity: Double = 0.5 {
        didSet { imagePanel?.alphaValue = opacity }
    }
    /// Image pixels per screen point: 2 for "@2x" exports from Figma.
    var scale: Double = 2 {
        didSet { applySize() }
    }
    var clickThrough = false {
        didSet { imagePanel?.ignoresMouseEvents = clickThrough }
    }
    private(set) var isOpen = false

    @ObservationIgnored private var image: NSImage?
    @ObservationIgnored private var pixelSize: CGSize = .zero
    @ObservationIgnored private var imagePanel: NSPanel?
    @ObservationIgnored private var controlsPanel: NSPanel?

    func openFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .pdf]
        panel.message = "Choose a design export (PNG from Figma works best)"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url, let loaded = NSImage(contentsOf: url) {
            show(loaded)
        }
    }

    func openFromClipboard() -> Bool {
        guard let pasted = NSImage(pasteboard: NSPasteboard.general) else { return false }
        show(pasted)
        return true
    }

    func show(_ newImage: NSImage) {
        close()
        image = newImage
        pixelSize = newImage.size
        if let bitmap = newImage.representations.first as? NSBitmapImageRep {
            pixelSize = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        // The file's DPI says it best (a @2x export is 144 dpi: half as many points as pixels);
        // otherwise a design wider than the screen at 1x is almost surely @2x.
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        scale = 1
        let pointsPerPixel = newImage.size.width / max(1, pixelSize.width)
        if pointsPerPixel > 0 && pointsPerPixel < 0.9 {
            scale = (1 / pointsPerPixel).rounded()
        } else if pixelSize.width > screenWidth {
            scale = 2
        }

        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let view = OverlayImageView(frame: .zero)
        view.image = newImage
        view.onNudge = { dx, dy in
            MainActor.assumeIsolated {
                DesignOverlay.shared.nudge(dx: dx, dy: dy)
            }
        }
        panel.contentView = view
        panel.alphaValue = opacity
        imagePanel = panel
        applySize()
        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.midX - panel.frame.width / 2, y: visible.maxY - panel.frame.height))
        }
        panel.orderFrontRegardless()
        clickThrough = false
        showControls()
        isOpen = true
    }

    /// For automation: panel size, opacity and click-through.
    var debugFrame: String {
        guard let panel = imagePanel else { return "closed" }
        return "frame=\(Int(panel.frame.width))x\(Int(panel.frame.height)) alpha=\(String(format: "%.2f", panel.alphaValue)) clickThrough=\(panel.ignoresMouseEvents)"
    }

    func close() {
        imagePanel?.orderOut(nil)
        imagePanel = nil
        controlsPanel?.orderOut(nil)
        controlsPanel = nil
        image = nil
        isOpen = false
    }

    func nudge(dx: CGFloat, dy: CGFloat) {
        guard let panel = imagePanel else { return }
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX + dx, y: panel.frame.minY + dy))
    }

    private func applySize() {
        guard let panel = imagePanel, scale > 0 else { return }
        let size = CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
        let top = panel.frame.maxY
        panel.setFrame(CGRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func showControls() {
        let hosting = NSHostingView(rootView: DesignOverlayControls(overlay: self))
        let panel = KeyablePanel(contentRect: CGRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.maxX - hosting.fittingSize.width - 20, y: visible.minY + 20))
        }
        panel.orderFrontRegardless()
        controlsPanel = panel
    }
}

final class OverlayImageView: NSView {
    var image: NSImage?
    var onNudge: ((CGFloat, CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds)
        NSColor(hex: 0xFF6B4A).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        var step: CGFloat = 1
        if event.modifierFlags.contains(.shift) {
            step = 10
        }
        switch event.keyCode {
        case 123: onNudge?(-step, 0)
        case 124: onNudge?(step, 0)
        case 125: onNudge?(0, -step)
        case 126: onNudge?(0, step)
        default: super.keyDown(with: event)
        }
    }
}

struct DesignOverlayControls: View {
    @Bindable var overlay: DesignOverlay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Design overlay").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    overlay.close()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Close the overlay")
            }
            HStack(spacing: 8) {
                Text("Opacity").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Slider(value: $overlay.opacity, in: 0.1...1)
                    .frame(width: 140)
                Text("\(Int(overlay.opacity * 100))%").font(.system(size: 12, design: .monospaced)).frame(width: 40)
            }
            HStack(spacing: 8) {
                Text("Export").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                PillPicker(options: [1.0, 2.0, 3.0], selection: $overlay.scale) { value in "@\(Int(value))x" }
                    .frame(width: 150)
            }
            Toggle("Click through to the app", isOn: $overlay.clickThrough)
                .toggleStyle(.switch)
                .font(.system(size: 12))
            Text("Drag the design to line it up; arrows nudge 1 pt, Shift 10 pt.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(width: 300)
        .foregroundStyle(Theme.text)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .preferredColorScheme(.dark)
    }
}
