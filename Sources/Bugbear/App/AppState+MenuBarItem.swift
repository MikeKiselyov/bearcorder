import AppKit
import ScreenCaptureKit
import Observation
import BugbearCore
import QuartzCore

extension AppState {
    // MARK: Menu bar item


    /// Whether the bear cannot be seen in the menu bar, nil when there is no item to look at.
    func menuBarItemIsHidden() -> Bool? {
        guard let button = statusItemButton(), let window = button.window else { return nil }
        let screen = window.screen ?? NSScreen.main
        return MenuBarPlacement.isHidden(itemFrame: window.frame, rightArea: screen?.auxiliaryTopRightArea, occlusionVisible: window.occlusionState.contains(.visible))
    }

    /// When the bear ended up behind the notch (a display was unplugged, more apps added icons),
    /// moves it next to the system icons. If even there is no room, says how to open Bugbear.
    func keepMenuBarItemVisible(reason: String) async {
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard menuBarItemIsHidden() == true else { return }
        Log.info("menu bar item hidden (\(reason)), moving it next to the system icons")
        await reinsertMenuBarItem(at: MenuBarPlacement.visiblePosition)
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard menuBarItemIsHidden() == true else {
            Log.info("menu bar item visible again")
            return
        }
        Log.info("menu bar item still hidden: the menu bar is full")
        if toldAboutHiddenItem || Automation.isEnabled { return }
        toldAboutHiddenItem = true
        let shortcut = HotKeySettings.shared.shortcut(for: .openMenu)?.display ?? ""
        var message = L("app.menuBar.hiddenBehindNotch")
        if !shortcut.isEmpty {
            message += " " + L("app.menuBar.hiddenBehindNotch.shortcut", shortcut, AppInfo.name)
        }
        Toast.shared.show(message, symbol: "menubar.rectangle", seconds: 8)
    }

    /// Takes the bear out of the menu bar and puts it back at `position` points from the right.
    /// macOS forgets an item's place when it is taken out, so the place is written in between.
    /// Nil puts it where macOS puts a new item: leftmost, the first to be hidden.
    func reinsertMenuBarItem(at position: Double?) async {
        showsMenuBarItem = false
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let place = position {
            UserDefaults.standard.set(place, forKey: MenuBarPlacement.positionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: MenuBarPlacement.positionKey)
        }
        showsMenuBarItem = true
    }

    /// The menu from a shortcut, also when the bear is hidden.
    func toggleMenuPanel() {
        if isMenuPanelOpen {
            closeMenuPanel()
            return
        }
        statusItemButton()?.performClick(nil)
    }

    /// Before quitting: stops every screen capture, so macOS takes its "Currently Sharing" indicator
    /// down at once instead of keeping it for a process that is gone.
    func stopCaptureForQuit() async {
        // All displays at once: the quit waits only so long.
        var stops: [Task<Void, Never>] = []
        for buffer in buffers {
            stops.append(Task { await buffer.stopCaptureForQuit() })
        }
        for stop in stops {
            await stop.value
        }
        buffers = []
        micSink = nil
        microphone.stop()
        inputRecorder.stop()
        crashWatcher.stop()
    }

    func toggleBuffer() async {
        if bufferState == .running {
            await pauseBuffer()
        } else {
            await startBuffer()
        }
    }

    /// Applies new settings by restarting a running buffer (drops what was recorded).
    func restartBufferIfRunning() async {
        if bufferState == .running && recording == nil {
            await startBuffer()
        }
    }

    func requestScreenRecordingAccess() {
        SystemActions.askPermission("Screen Recording") { ScreenBuffer.requestScreenRecordingAccess() }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            SystemActions.open(url)
        }
    }

    func requestAccessibilityAccess() {
        SystemActions.askPermission("Accessibility") { InputEventRecorder.requestAccessibilityAccess() }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            SystemActions.open(url)
        }
    }
}
