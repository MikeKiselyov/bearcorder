// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI
import AppCore

/// Automation commands for scripts/test/e2e-features.sh: drive each feature the way a user would,
/// without the pickers and dialogs that need a mouse. Only active with the automation hook on.
@MainActor
enum FeatureAutomation {
    /// Handles `command` if it is a feature command. Returns the result text, or nil for unknown commands.
    static func run(_ parts: [String]) async -> String? {
        let app = AppState.shared
        let name = parts.first ?? ""
        let argument = parts.count > 1 ? parts[1] : ""
        if let result = await runCapture(name, argument, parts, app) {
            return result
        }
        if let result = await runSpace(name, argument, parts, app) {
            return result
        }
        if let result = await runControls(name, argument, parts, app) {
            return result
        }
        if let result = await runApp(name, argument, parts, app) {
            return result
        }
        if let result = await runEditor(name, argument, parts, app) {
            return result
        }
        if let result = await runInput(name, argument, parts, app) {
            return result
        }
        if let result = await runReports(name, argument, parts, app) {
            return result
        }
        return nil
    }

    /// Normalized "x,y,w,h" on the screen under the pointer.
    static func selection(_ text: String) -> RegionSelector.Selection? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { item in item.frame.contains(mouse) }) ?? NSScreen.main else { return nil }
        return selection(text, on: screen)
    }

    /// x,y,w,h normalized on `screen`, origin top-left.
    static func selection(_ text: String, on screen: NSScreen) -> RegionSelector.Selection? {
        var numbers: [CGFloat] = []
        for piece in text.split(separator: ",") {
            guard let value = Double(piece) else { return nil }
            numbers.append(CGFloat(value))
        }
        guard numbers.count == 4 else { return nil }
        let normalized = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        let frame = screen.frame
        let global = CGRect(x: frame.minX + normalized.minX * frame.width, y: frame.maxY - normalized.maxY * frame.height, width: normalized.width * frame.width, height: normalized.height * frame.height)
        return RegionSelector.Selection(global: global)
    }

    /// Visible frame of the first AXWebArea in the app's focused window, in top-left screen points. The web
    /// area itself spans the whole page, so it is cut to the scroll area around it.
    /// The browser web-area asked for its accessibility tree, so the tests can switch it off again.
    static var browserWithAccessibility: pid_t?

    static func webAreaFrame(of running: NSRunningApplication) -> CGRect? {
        let application = AXUIElementCreateApplication(running.processIdentifier)
        // Chromium browsers build the page's accessibility tree only on request (or while another
        // assistive app runs): ask for it. Other apps ignore the attribute.
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        browserWithAccessibility = running.processIdentifier
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success, let window = focused, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var queue: [(element: AXUIElement, parent: AXUIElement?)] = [(element: window as! AXUIElement, parent: nil)]
        var visited = 0
        while !queue.isEmpty && visited < 400 {
            let item = queue.removeFirst()
            visited += 1
            var role: AnyObject?
            AXUIElementCopyAttributeValue(item.element, kAXRoleAttribute as CFString, &role)
            if let roleName = role as? String, roleName == "AXWebArea" {
                guard let page = frame(of: item.element) else { return nil }
                guard let parent = item.parent, let visible = frame(of: parent) else { return page }
                return page.intersection(visible)
            }
            var children: AnyObject?
            if AXUIElementCopyAttributeValue(item.element, kAXChildrenAttribute as CFString, &children) == .success, let list = children as? [AXUIElement] {
                for child in list {
                    queue.append((element: child, parent: item.element))
                }
            }
        }
        return nil
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionFound = positionValue, let sizeFound = sizeValue else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionFound as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeFound as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    static func carbonModifiers(_ text: String) -> UInt32 {
        var flags: UInt32 = 0
        if text.contains("cmd") { flags |= 256 }       // cmdKey
        if text.contains("shift") { flags |= 512 }     // shiftKey
        if text.contains("option") { flags |= 2048 }   // optionKey
        if text.contains("control") { flags |= 4096 }  // controlKey
        return flags
    }

    /// The buffer state before `buffer-needs-permission:on`, put back by `:off`.
    static var stateBeforePermissionFake: AppState.BufferState?

    /// The person's report settings while a test changes them.
    struct SavedReportSettings: Codable {
        var fields: [EnvironmentSnapshot.Field]
        var hidden: [String]
        var renamed: [String: String]
    }

    /// Settings shows one page at a time: before a control of it is used, the page that has it
    /// is shown. The current page is kept when it has the control.
    static func showSettingsPage(with label: String, window name: String) async {
        guard name == "settings", let window = controlWindows(name).first else { return }
        var wanted = label
        for suffix in ["#increment", "#decrement", "#last"] where wanted.hasSuffix(suffix) {
            wanted = String(wanted.dropLast(suffix.count))
        }
        if ControlTree.frame(label: wanted, inWindowAt: topLeftFrame(window), scrollIntoView: true) != nil { return }
        let shown = SettingsNavigation.shared.page
        for page in SettingsPage.allCases where page != shown {
            SettingsNavigation.shared.page = page
            try? await Task.sleep(nanoseconds: 300_000_000)
            if ControlTree.frame(label: wanted, inWindowAt: topLeftFrame(window), scrollIntoView: true) != nil { return }
        }
        SettingsNavigation.shared.page = shown
    }

    /// The windows a control command looks in: "menubar" for the menu bar panel, otherwise
    /// windows whose id starts with the name (editor-…, settings, onboarding).
    static func controlWindows(_ name: String) -> [NSWindow] {
        var windows: [NSWindow] = []
        for window in NSApp.windows where window.isVisible {
            if name == "menubar" {
                if window.className.contains("MenuBarExtra") {
                    windows.append(window)
                }
            } else if name == "popover" {
                if window.className.contains("Popover") {
                    windows.append(window)
                }
            } else if let id = window.identifier?.rawValue, id.hasPrefix(name) {
                windows.append(window)
            }
        }
        return windows
    }

    static func frontAppIsOurs() -> Bool {
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// The app itself or a browser (the e2e tests drive a test page in one).
    static func frontAppTakesTestKeys() -> Bool {
        if frontAppIsOurs() {
            return true
        }
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return EnvironmentCollector.browserScripts[bundleId] != nil
    }

    /// A window's frame the way the Accessibility API gives it: top-left of the main screen.
    static func topLeftFrame(_ window: NSWindow) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = window.frame
        return CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Whether the key with these modifiers ("option,shift") is one of the app's shortcuts now.
    static func isOwnShortcut(keyCode: CGKeyCode, flags: String) -> Bool {
        var modifiers: UInt32 = 0
        if flags.contains("cmd") { modifiers |= UInt32(cmdKey) }
        if flags.contains("shift") { modifiers |= UInt32(shiftKey) }
        if flags.contains("option") { modifiers |= UInt32(optionKey) }
        if flags.contains("control") { modifiers |= UInt32(controlKey) }
        for action in HotKeyAction.allCases {
            guard let shortcut = HotKeySettings.shared.shortcut(for: action) else { continue }
            if shortcut.keyCode == UInt32(keyCode) && shortcut.modifiers == modifiers {
                return true
            }
        }
        return false
    }

    static func cgFlags(_ text: String) -> CGEventFlags {
        var flags: CGEventFlags = []
        if text.contains("cmd") { flags.insert(.maskCommand) }
        if text.contains("shift") { flags.insert(.maskShift) }
        if text.contains("option") { flags.insert(.maskAlternate) }
        if text.contains("control") { flags.insert(.maskControl) }
        return flags
    }

    /// + and - on a test screenshot and video, the way the editors do it.
    static func editorSizeTest() -> String {
        guard let shot = CaptureStore.shared.captures.first(where: { item in item.kind == .screenshot }), let document = ScreenshotDocument(capture: shot) else { return "no screenshot" }
        var results: [String] = []
        let arrow = Annotation(tool: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 200, y: 200), color: .yellow, lineWidth: document.lineWidth)
        document.annotations.append(arrow)
        document.selectedId = arrow.id
        let widthBefore = document.selected?.lineWidth ?? 0
        document.changeSize(by: 1)
        let widthAfter = document.selected?.lineWidth ?? 0
        results.append("arrowWidth=\(Int(widthBefore))->\(Int(widthAfter)) color=\(document.selected?.color.rawValue ?? "?")")
        var text = Annotation(tool: .text, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50), color: .coral, lineWidth: document.lineWidth)
        text.fontSize = document.fontSize
        text.text = "E2E"
        document.annotations.append(text)
        document.selectedId = text.id
        let fontBefore = document.selected?.fontSize ?? 0
        document.changeSize(by: 1)
        document.changeSize(by: 1)
        let fontAfter = document.selected?.fontSize ?? 0
        results.append("textFont=\(Int(fontBefore))->\(Int(fontAfter))")
        // Leave the test screenshot as it was.
        document.undo()
        document.undo()
        document.annotations.removeAll { item in item.id == arrow.id || item.id == text.id }
        document.saveProject()
        return results.joined(separator: " ")
    }
}

extension FeatureAutomation {
    /// The drawing canvas inside an editor window.
    /// "minX,minY,maxX,maxY" of a video mark in 0…1 frame coordinates, two decimals.
    static func cropText(_ crop: CGRect?) -> String {
        guard let area = crop else { return "none" }
        return String(format: "%.2f,%.2f,%.2f,%.2f", area.minX, area.minY, area.maxX, area.maxY)
    }

    static func boxText(_ overlay: VideoOverlay?) -> String {
        guard let mark = overlay else { return "none" }
        let box = mark.rect
        return String(format: "%.2f,%.2f,%.2f,%.2f", box.minX, box.minY, box.maxX, box.maxY)
    }

    static func findCanvas(in view: NSView?) -> CanvasView? {
        guard let current = view else { return nil }
        if let canvas = current as? CanvasView {
            return canvas
        }
        for child in current.subviews {
            if let found = findCanvas(in: child) {
                return found
            }
        }
        return nil
    }
}
#endif
