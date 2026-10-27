import AVFoundation
import AppKit

/// Round, draggable webcam preview floating over the screen. It is allowed into the capture,
/// so it shows up in the recording like in Loom-style videos.
@MainActor
final class CameraBubble: NSObject {
    private var panel: KeyablePanel?
    private let session = AVCaptureSession()
    private var configured = false
    var onVisibilityChange: ((Int?) -> Void)?
    var size: CGFloat = 200 {
        didSet { applySize() }
    }

    var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    var windowNumber: Int? {
        guard let panel = panel, panel.isVisible else { return nil }
        return panel.windowNumber
    }

    static var authorization: AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Returns false when there is no camera or access was denied.
    func show(on screen: NSScreen?) async -> Bool {
        if CameraBubble.authorization == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard CameraBubble.authorization == .authorized else { return false }
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return false }
            session.beginConfiguration()
            session.sessionPreset = .high
            if session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            configured = true
        }
        if panel == nil {
            makePanel()
        }
        let target = screen ?? NSScreen.main
        if let frame = target?.visibleFrame {
            let origin = CGPoint(x: frame.minX + 32, y: frame.minY + 32)
            panel?.setFrame(CGRect(origin: origin, size: CGSize(width: size, height: size)), display: true)
        }
        let captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
        }
        panel?.orderFrontRegardless()
        onVisibilityChange?(panel?.windowNumber)
        return true
    }

    func hide() {
        panel?.orderOut(nil)
        let captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
        onVisibilityChange?(nil)
    }

    private func makePanel() {
        let newPanel = KeyablePanel(contentRect: CGRect(x: 0, y: 0, width: size, height: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        newPanel.identifier = NSUserInterfaceItemIdentifier("camera")
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .floating
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newPanel.isReleasedWhenClosed = false

        let view = CameraBubbleView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.bubble = self
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.wantsLayer = true
        view.layer?.addSublayer(preview)
        view.layer?.masksToBounds = true
        view.layer?.cornerRadius = size / 2
        view.layer?.borderWidth = 4
        view.layer?.borderColor = NSColor(hex: 0x9B6BFF).cgColor
        newPanel.contentView = view
        panel = newPanel
    }

    private func applySize() {
        guard let panel = panel else { return }
        var frame = panel.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        frame.size = CGSize(width: size, height: size)
        frame.origin = CGPoint(x: center.x - size / 2, y: center.y - size / 2)
        panel.setFrame(frame, display: true)
        panel.contentView?.layer?.cornerRadius = size / 2
    }
}

final class CameraBubbleView: NSView {
    weak var bubble: CameraBubble?

    override var mouseDownCanMoveWindow: Bool { true }

    /// Scroll to resize.
    override func scrollWheel(with event: NSEvent) {
        guard let bubble = bubble else { return }
        let next = bubble.size + event.scrollingDeltaY * 2
        MainActor.assumeIsolated {
            bubble.size = max(120, min(420, next))
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, value) in [("Small", 140.0), ("Medium", 200.0), ("Large", 300.0)] {
            let item = NSMenuItem(title: title, action: #selector(choseSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide camera", action: #selector(hideBubble), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        return menu
    }

    @objc private func choseSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        MainActor.assumeIsolated {
            bubble?.size = CGFloat(value)
            AppSettings.shared.cameraBubbleSize = value
        }
    }

    @objc private func hideBubble() {
        Task { @MainActor in
            await AppState.shared.setCamera(false)
        }
    }
}
