import AppKit
import ScreenCaptureKit
import Observation
import BugbearCore
import QuartzCore

extension AppState {
    // MARK: Toolbox, environment, misc

    func openToolbox(tool: ToolKind?) {
        closeMenuPanel()
        WindowManager.shared.openToolbox(tool: tool)
    }

    func refreshEnvironmentPreview() async {
        environmentPreview = await EnvironmentCollector.snapshot(for: lastExternalApp, readURL: false)
    }

    func showError(_ message: String) {
        Log.error("alert: \(message)")
        statusMessage = message
        if Automation.isEnabled { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = AppInfo.name
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Hides the MenuBarExtra panel before capturing so it is not in the shot.
    var isMenuPanelOpen: Bool {
        for window in NSApp.windows where window.className.contains("MenuBarExtra") && window.isVisible {
            return true
        }
        return false
    }

    /// Closes the menu bar panel the way a click on the bear does. Hiding the panel window directly
    /// left SwiftUI thinking it was still open, so the next click on the bear only "closed" it and
    /// nothing appeared.
    func closeMenuPanel() {
        if !isMenuPanelOpen { return }
        if let button = statusItemButton() {
            button.performClick(nil)
            return
        }
        for window in NSApp.windows where window.className.contains("MenuBarExtra") {
            window.orderOut(nil)
        }
    }

    /// The bear in the menu bar, as an AppKit button.
    func statusItemButton() -> NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = AppState.findStatusButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func findStatusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view = view else { return nil }
        if let button = view as? NSStatusBarButton {
            return button
        }
        for child in view.subviews {
            if let found = findStatusButton(in: child) {
                return found
            }
        }
        return nil
    }

    /// Brings back the app that was in front before Bugbear took the focus.
    func handFocusBack() {
        guard let previous = lastExternalApp, !previous.isTerminated else { return }
        NSApp.yieldActivation(to: previous)
        previous.activate(from: NSRunningApplication.current, options: [])
    }
}
