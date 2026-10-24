import AppKit
import BugbearCore
import SwiftUI

/// Opens editor, toolbox, history and settings windows. The app runs as a menu bar
/// accessory and becomes a regular (Dock) app only while one of these windows is open.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var windows: [String: NSWindow] = [:]

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
        windows[id] = window
        activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = window.identifier?.rawValue else { return }
        windows[id] = nil
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
            show(id: "screenshot:\(capture.id)", title: "Screenshot · \(capture.title)", size: CGSize(width: 1220, height: 780), minSize: CGSize(width: 900, height: 560)) {
                ScreenshotEditorView(capture: capture)
            }
        case .video:
            show(id: "video:\(capture.id)", title: "Clip · \(capture.title)", size: CGSize(width: 1220, height: 800), minSize: CGSize(width: 980, height: 640)) {
                VideoEditorView(capture: capture)
            }
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

    func openSettings() {
        show(id: "settings", title: "Bugbear Settings", size: CGSize(width: 560, height: 640), minSize: CGSize(width: 480, height: 480)) {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let toolboxSelect = Notification.Name("Bugbear.toolboxSelect")
}
