import AppKit
import ApplicationServices

/// Resizes the front window of the app you were using, through Accessibility.
@MainActor
enum WindowResizer {
    struct Preset: Identifiable {
        var id: String { title }
        var title: String
        var size: CGSize
    }

    /// Window sizes in points. For a browser the page area is a bit smaller than the window.
    static let desktopPresets = [
        Preset(title: "1280 × 720", size: CGSize(width: 1280, height: 720)),
        Preset(title: "1366 × 768", size: CGSize(width: 1366, height: 768)),
        Preset(title: "1440 × 900", size: CGSize(width: 1440, height: 900)),
        Preset(title: "1920 × 1080", size: CGSize(width: 1920, height: 1080)),
    ]

    static let mobilePresets = [
        Preset(title: "Phone · 375 × 812", size: CGSize(width: 375, height: 812)),
        Preset(title: "Phone · 390 × 844", size: CGSize(width: 390, height: 844)),
        Preset(title: "Tablet · 768 × 1024", size: CGSize(width: 768, height: 1024)),
        Preset(title: "Tablet · 1024 × 768", size: CGSize(width: 1024, height: 768)),
    ]

    enum Failure: Error {
        case noAccess
        case noApp
        case noWindow
        case refused
    }

    /// Resizes and moves the window so it stays on its screen. Returns the size the app accepted
    /// (apps can enforce a minimum size).
    static func resize(app: NSRunningApplication?, to size: CGSize) -> Result<CGSize, Failure> {
        guard AXIsProcessTrusted() else { return .failure(.noAccess) }
        guard let running = app else { return .failure(.noApp) }
        let element = AXUIElementCreateApplication(running.processIdentifier)
        var focused: AnyObject?
        var result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focused)
        if result != .success || focused == nil {
            result = AXUIElementCopyAttributeValue(element, kAXMainWindowAttribute as CFString, &focused)
        }
        guard result == .success, let found = focused, CFGetTypeID(found) == AXUIElementGetTypeID() else {
            return .failure(.noWindow)
        }
        let window = found as! AXUIElement

        // Keep the window on the screen it is on: move it up and left if the new size would overflow.
        let currentOrigin = point(of: window) ?? .zero
        let screen = screenContaining(topLeft: currentOrigin)
        var origin = currentOrigin
        if let visible = screen?.visibleFrame, let main = NSScreen.screens.first {
            // AX uses top-left origin; convert the visible frame.
            let visibleTop = main.frame.maxY - visible.maxY
            let visibleLeft = visible.minX
            origin.x = max(visibleLeft, min(origin.x, visibleLeft + visible.width - size.width))
            origin.y = max(visibleTop, min(origin.y, visibleTop + visible.height - size.height))
        }
        var newOrigin = origin
        var newSize = size
        if let positionValue = AXValueCreate(.cgPoint, &newOrigin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        guard let sizeValue = AXValueCreate(.cgSize, &newSize) else { return .failure(.refused) }
        if AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) != .success {
            return .failure(.refused)
        }
        return .success(currentSize(of: window) ?? size)
    }

    /// Moves the front window's top-left corner (top-left screen coordinates, points).
    static func move(app: NSRunningApplication?, to point: CGPoint) -> Bool {
        guard AXIsProcessTrusted(), let running = app else { return false }
        let element = AXUIElementCreateApplication(running.processIdentifier)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focused) == .success, let found = focused, CFGetTypeID(found) == AXUIElementGetTypeID() else { return false }
        var target = point
        guard let value = AXValueCreate(.cgPoint, &target) else { return false }
        return AXUIElementSetAttributeValue(found as! AXUIElement, kAXPositionAttribute as CFString, value) == .success
    }

    private static func point(of window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success, let found = value, CFGetTypeID(found) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(found as! AXValue, .cgPoint, &point)
        return point
    }

    private static func currentSize(of window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success, let found = value, CFGetTypeID(found) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        AXValueGetValue(found as! AXValue, .cgSize, &size)
        return size
    }

    private static func screenContaining(topLeft: CGPoint) -> NSScreen? {
        guard let main = NSScreen.screens.first else { return nil }
        let appKitPoint = CGPoint(x: topLeft.x + 1, y: main.frame.maxY - topLeft.y - 1)
        for screen in NSScreen.screens where screen.frame.contains(appKitPoint) {
            return screen
        }
        return NSScreen.main
    }
}
