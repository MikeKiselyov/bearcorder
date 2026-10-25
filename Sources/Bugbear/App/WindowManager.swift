import AppKit
import BugbearCore
import SwiftUI

/// Opens editor, toolbox, history and settings windows. The app runs as a menu bar
/// accessory and becomes a regular (Dock) app only while one of these windows is open.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var windows: [String: NSWindow] = [:]
    /// The model of the open feedback window, for checks.
    private(set) var feedbackModel: FeedbackModel?

    func show<Content: View>(id: String, title: String, size: CGSize, minSize: CGSize, @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let root = content()
            .environment(AppState.shared)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        let hosting = NSHostingController(rootView: root)
        // The window keeps the size given here. Otherwise it follows SwiftUI's ideal size, and a view
        // that fills the window grows as tall as the screen: on a tall display the buttons at the
        // bottom end up under the Dock or off screen.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(hex: 0x1B1C1F)
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(size)
        window.contentMinSize = minSize
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.center()
        window.setFrameAutosaveName("Bugbear.\(id.components(separatedBy: ":").first ?? id)")
        fitOnScreen(window)
        windows[id] = window
        activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Keeps a window inside the visible part of its screen, also when the saved frame is from a
    /// bigger display or was saved too tall.
    private func fitOnScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        if frame.width > visible.width {
            frame.size.width = visible.width
        }
        if frame.height > visible.height {
            frame.size.height = visible.height
        }
        if frame.minX < visible.minX {
            frame.origin.x = visible.minX
        }
        if frame.maxX > visible.maxX {
            frame.origin.x = visible.maxX - frame.width
        }
        if frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        if frame.maxY > visible.maxY {
            frame.origin.y = visible.maxY - frame.height
        }
        window.setFrame(frame, display: false)
    }

    private func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = window.identifier?.rawValue else { return }
        windows[id] = nil
        if id == "feedback" {
            feedbackModel = nil
        }
        if windows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func isOpen(id: String) -> Bool {
        return windows[id] != nil
    }

    func close(id: String) {
        windows[id]?.close()
    }

    // MARK: Specific windows

    func openEditor(for capture: Capture) {
        switch capture.kind {
        case .screenshot:
            show(id: "screenshot:\(capture.id)", title: "Screenshot · \(capture.title)", size: CGSize(width: 1280, height: 780), minSize: CGSize(width: 1080, height: 560)) {
                ScreenshotEditorView(capture: capture)
            }
        case .video:
            show(id: "video:\(capture.id)", title: "Clip · \(capture.title)", size: CGSize(width: 1220, height: 800), minSize: CGSize(width: 980, height: 640)) {
                VideoEditorView(capture: capture)
            }
        }
    }

    /// Disk space: clean up, folders by size, largest files.
    func openSpace(section: SpaceView.Section) {
        AppState.shared.closeMenuPanel()
        show(id: "space", title: "Disk Space", size: CGSize(width: 980, height: 720), minSize: CGSize(width: 760, height: 520)) {
            SpaceView(section: section)
        }
    }

    func openToolbox(tool: ToolKind?) {
        var initial = tool
        var initialInput = ""
        if initial == nil, let clipboard = NSPasteboard.general.string(forType: .string) {
            if let detected = ContentDetector.detect(clipboard) {
                initial = detected
                initialInput = clipboard
            }
        } else if let clipboard = NSPasteboard.general.string(forType: .string), let chosen = tool, ContentDetector.detect(clipboard) == chosen {
            initialInput = clipboard
        }
        if let existing = windows["toolbox"] {
            if let chosen = initial {
                NotificationCenter.default.post(name: .toolboxSelect, object: nil, userInfo: ["tool": chosen.rawValue, "input": initialInput])
            }
            activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let detectedFromClipboard = tool == nil && initial != nil
        show(id: "toolbox", title: "Dev Toolbox", size: CGSize(width: 1220, height: 760), minSize: CGSize(width: 900, height: 560)) {
            ToolboxView(initialTool: initial ?? .json, initialInput: initialInput, detectedFromClipboard: detectedFromClipboard)
        }
    }

    func openHistory() {
        show(id: "history", title: "All captures", size: CGSize(width: 980, height: 680), minSize: CGSize(width: 640, height: 420)) {
            HistoryView()
        }
    }

    func openOnboarding() {
        show(id: "onboarding", title: "Welcome to Bugbear", size: CGSize(width: 680, height: 600), minSize: CGSize(width: 620, height: 560)) {
            OnboardingView()
        }
    }

    func openStepGuide(captures: [Capture]) {
        let model = StepGuideModel(captures: captures)
        show(id: "step-guide", title: "Step guide", size: CGSize(width: 900, height: 760), minSize: CGSize(width: 720, height: 480)) {
            StepGuideView(model: model)
        }
    }

    /// The older capture is "before".
    func openCompare(_ first: Capture, _ second: Capture) {
        var before = first
        var after = second
        if second.createdAt < first.createdAt {
            before = second
            after = first
        }
        close(id: "compare")
        show(id: "compare", title: "Before and after", size: CGSize(width: 1300, height: 800), minSize: CGSize(width: 900, height: 560)) {
            CompareView(before: before, after: after)
        }
    }

    /// Report a problem with Bugbear or suggest a feature on GitHub.
    func openFeedback(kind: FeedbackReport.Kind) {
        openFeedback(model: FeedbackModel(kind: kind))
    }

    /// An open feedback window is replaced, so the window always shows what was asked for.
    func openFeedback(model: FeedbackModel) {
        AppState.shared.closeMenuPanel()
        close(id: "feedback")
        feedbackModel = model
        show(id: "feedback", title: "Feedback", size: CGSize(width: 560, height: 640), minSize: CGSize(width: 500, height: 560)) {
            FeedbackView(model: model)
        }
    }

    func openSettings() {
        show(id: "settings", title: "Bugbear Settings", size: CGSize(width: 560, height: 640), minSize: CGSize(width: 480, height: 480)) {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let toolboxSelect = Notification.Name("Bugbear.toolboxSelect")
}
