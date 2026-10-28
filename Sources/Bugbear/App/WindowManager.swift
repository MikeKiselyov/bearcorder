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
        window.backgroundColor = NSColor(hex: 0x16131B)
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
        let wasActive = NSApp.isActive
        activate()
        window.makeKeyAndOrderFront(nil)
        if !wasActive {
            bringForwardWhenActive(window)
        }
    }

    /// Becoming active comes a moment later and brings the app's last key window forward again: a
    /// window opened from an editor (Settings from "Edit") ended up behind that editor. Only for that
    /// moment: if macOS does not activate the app now, a later activation (a click on an editor)
    /// must not pull this window over it.
    private func bringForwardWhenActive(_ window: NSWindow) {
        var observer: NSObjectProtocol?
        let stop = {
            if let registered = observer {
                NotificationCenter.default.removeObserver(registered)
                observer = nil
            }
        }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak window] _ in
            stop()
            MainActor.assumeIsolated {
                if let shown = window, shown.isVisible {
                    shown.makeKeyAndOrderFront(nil)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            stop()
        }
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
        if !NSApp.setActivationPolicy(.regular) {
            Log.info("dock icon: macOS did not switch to a regular app")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = window.identifier?.rawValue else { return }
        windows[id] = nil
        if id == "feedback" {
            feedbackModel = nil
        }
        if windows.isEmpty {
            // After the window is really gone: while it is still closing macOS refuses the switch
            // and the Dock icon stays.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self.windows.isEmpty {
                        self.leaveDock()
                    }
                }
            }
        }
    }

    /// A click on the Dock icon: the open windows come forward, or with none the menu opens.
    func reopenFromDock() {
        switch DockReopen.action(openWindowCount: windows.count) {
        case .showWindows:
            activate()
            for window in windows.values {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            }
        case .openMenu:
            Log.info("dock icon with no window: opening the menu")
            // The menu needs Bugbear in front a moment: handing the focus away would close it.
            leaveDock(handingFocusBack: false)
            if !AppState.shared.isMenuPanelOpen {
                AppState.shared.toggleMenuPanel()
            }
        }
    }

    var openWindowCount: Int {
        return windows.count
    }

    /// Back to the menu bar only. macOS refuses the switch while the app is active, so Bugbear
    /// hands the focus back to the app the person was in and switches once it is no longer active.
    private func leaveDock(handingFocusBack: Bool = true) {
        if !NSApp.isActive || !handingFocusBack {
            switchToMenuBarOnly()
            return
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    WindowManager.shared.finishLeavingDock()
                }
            }
        }
        if let previous = AppState.shared.lastExternalApp, !previous.isTerminated {
            NSApp.yieldActivation(to: previous)
            previous.activate(from: NSRunningApplication.current, options: [])
        } else {
            NSApp.deactivate()
        }
    }

    private var resignObserver: NSObjectProtocol?

    private func finishLeavingDock() {
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
            resignObserver = nil
        }
        // A window opened in the meantime keeps the icon.
        if windows.isEmpty {
            switchToMenuBarOnly()
        }
    }

    private func switchToMenuBarOnly() {
        let switched = NSApp.setActivationPolicy(.accessory)
        Log.info("dock icon: back to the menu bar only, switched=\(switched)")
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
            show(id: "screenshot:\(capture.id)", title: L("app.window.screenshot", capture.title), size: CGSize(width: 1280, height: 780), minSize: CGSize(width: 1080, height: 560)) {
                ScreenshotEditorView(capture: capture)
            }
        case .video:
            show(id: "video:\(capture.id)", title: L("app.window.clip", capture.title), size: CGSize(width: 1220, height: 800), minSize: CGSize(width: 980, height: 640)) {
                VideoEditorView(capture: capture)
            }
        }
    }

    /// Disk space: clean up, folders by size, largest files.
    func openSpace(section: SpaceView.Section) {
        AppState.shared.closeMenuPanel()
        show(id: "space", title: L("app.window.space"), size: CGSize(width: 980, height: 720), minSize: CGSize(width: 760, height: 520)) {
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
        show(id: "toolbox", title: L("app.window.toolbox"), size: CGSize(width: 1220, height: 760), minSize: CGSize(width: 900, height: 560)) {
            ToolboxView(initialTool: initial ?? .json, initialInput: initialInput, detectedFromClipboard: detectedFromClipboard)
        }
    }

    func openHistory() {
        show(id: "history", title: L("app.window.history"), size: CGSize(width: 980, height: 680), minSize: CGSize(width: 640, height: 420)) {
            HistoryView()
        }
    }

    func openOnboarding() {
        show(id: "onboarding", title: L("app.window.onboarding", AppInfo.name), size: CGSize(width: 680, height: 600), minSize: CGSize(width: 620, height: 560)) {
            OnboardingView()
        }
    }

    func openStepGuide(captures: [Capture]) {
        let model = StepGuideModel(captures: captures)
        show(id: "step-guide", title: L("app.window.stepGuide"), size: CGSize(width: 900, height: 760), minSize: CGSize(width: 720, height: 480)) {
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
        show(id: "compare", title: L("app.window.compare"), size: CGSize(width: 1300, height: 800), minSize: CGSize(width: 900, height: 560)) {
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
        show(id: "feedback", title: L("app.window.feedback"), size: CGSize(width: 560, height: 640), minSize: CGSize(width: 500, height: 560)) {
            FeedbackView(model: model)
        }
    }

    func openSettings(page: SettingsPage? = nil) {
        if let shown = page {
            SettingsNavigation.shared.page = shown
        }
        show(id: "settings", title: L("app.window.settings", AppInfo.name), size: CGSize(width: 780, height: 620), minSize: CGSize(width: 700, height: 480)) {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let toolboxSelect = Notification.Name("Bugbear.toolboxSelect")
}
