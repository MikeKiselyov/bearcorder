// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AppKit
import ApplicationServices

/// The controls of a window as accessibility sees them: what a person can press, toggle or pick.
/// Tests list them to know every control is covered, and press them the way VoiceOver does.
/// SwiftUI builds its accessibility tree only for an Accessibility API client, so this asks
/// through that API. For its own process the API calls straight in, without a message, so it runs on
/// the main thread: SwiftUI performs button actions only there.
@MainActor
enum ControlTree {
    struct Control {
        var role: String
        var label: String
    }

    /// Every role in the window's tree with how often it occurs, to see what accessibility shows.
    static func roleCounts(inWindowAt frame: CGRect) async -> String {
        let processId = ProcessInfo.processInfo.processIdentifier
        do {
            guard let window = axWindow(processId: processId, frame: frame) else { return "no window" }
            var counts: [String: Int] = [:]
            var stack: [AXUIElement] = [window]
            var visited = 0
            while let element = stack.popLast(), visited < 20_000 {
                visited += 1
                let role = string(element, kAXRoleAttribute)
                counts[role, default: 0] += 1
                for child in children(of: element, attribute: kAXChildrenAttribute) {
                    stack.append(child)
                }
            }
            var parts: [String] = []
            for key in counts.keys.sorted() {
                parts.append("\(key)=\(counts[key] ?? 0)")
            }
            return parts.joined(separator: " ")
        }
    }

    static let pressableRoles: Set<String> = ["AXButton", "AXCheckBox", "AXPopUpButton", "AXRadioButton", "AXMenuButton", "AXSlider", "AXTextField", "AXComboBox", "AXDisclosureTriangle", "AXIncrementor", "AXLink"]
    /// What a value can be read from: the controls and multi-line text such as a tool's output.
    static let readableRoles: Set<String> = pressableRoles.union(["AXTextArea"])

    /// Controls of the app's window whose frame (top-left screen points) is `frame`.
    static func controls(inWindowAt frame: CGRect) async -> [Control] {
        let processId = ProcessInfo.processInfo.processIdentifier
        do {
            guard let window = axWindow(processId: processId, frame: frame) else { return [] }
            var found: [(control: Control, element: AXUIElement)] = []
            var seen = 0
            collect(window, into: &found, seen: &seen, roles: pressableRoles)
            var controls: [Control] = []
            for item in found {
                controls.append(item.control)
            }
            return controls
        }
    }

    /// What the first control with this label shows (a picker's choice, a switch's 0 or 1).
    /// Text areas count here too (a tool's Input and Output); "#last" takes the last one.
    static func value(label: String, inWindowAt frame: CGRect) -> String? {
        let processId = ProcessInfo.processInfo.processIdentifier
        guard let window = axWindow(processId: processId, frame: frame) else { return nil }
        var wanted = label
        var takesLast = false
        if wanted.hasSuffix("#last") {
            wanted = String(wanted.dropLast(5))
            takesLast = true
        }
        var found: [(control: Control, element: AXUIElement)] = []
        var seen = 0
        collect(window, into: &found, seen: &seen, roles: readableRoles)
        var matches: [AXUIElement] = []
        for item in found where item.control.label == wanted {
            matches.append(item.element)
        }
        if takesLast {
            matches.reverse()
        }
        for element in matches {
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success, let shown = value else { return "" }
            if let text = shown as? String {
                return text
            }
            if let number = shown as? NSNumber {
                return number.stringValue
            }
            return "\(shown)"
        }
        return nil
    }

    /// Presses the first control with this label in the window, or the last one when the label
    /// ends with "#last" (a row just added). "#increment" and "#decrement" step a slider or a
    /// stepper instead. False when there is none.
    static func press(label: String, inWindowAt frame: CGRect) async -> Bool {
        let processId = ProcessInfo.processInfo.processIdentifier
        guard let window = axWindow(processId: processId, frame: frame) else { return false }
        var wanted = label
        var action = kAXPressAction
        if wanted.hasSuffix("#increment") {
            wanted = String(wanted.dropLast(10))
            action = kAXIncrementAction
        } else if wanted.hasSuffix("#decrement") {
            wanted = String(wanted.dropLast(10))
            action = kAXDecrementAction
        }
        var takesLast = false
        if wanted.hasSuffix("#last") {
            wanted = String(wanted.dropLast(5))
            takesLast = true
        }
        var found: [(control: Control, element: AXUIElement)] = []
        var seen = 0
        collect(window, into: &found, seen: &seen, roles: pressableRoles)
        var target: AXUIElement?
        for item in found where item.control.label == wanted {
            target = item.element
            if !takesLast {
                break
            }
        }
        guard let element = target else { return false }
        return AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// Where the first control with this label is, in top-left screen points. With `scrollIntoView`
    /// a control below the fold of a scroll view is scrolled to first.
    static func frame(label: String, inWindowAt frame: CGRect, scrollIntoView: Bool) -> CGRect? {
        let processId = ProcessInfo.processInfo.processIdentifier
        guard let window = axWindow(processId: processId, frame: frame) else { return nil }
        var found: [(control: Control, element: AXUIElement)] = []
        var seen = 0
        collect(window, into: &found, seen: &seen, roles: readableRoles)
        for item in found where item.control.label == label {
            if scrollIntoView {
                AXUIElementPerformAction(item.element, "AXScrollToVisible" as CFString)
            }
            guard let position = point(item.element, kAXPositionAttribute), let size = size(item.element, kAXSizeAttribute) else { return nil }
            return CGRect(origin: position, size: size)
        }
        return nil
    }

    private static func axWindow(processId: pid_t, frame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(processId)
        AXUIElementSetMessagingTimeout(app, 2)
        var best: AXUIElement?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        // A popover is not one of the app's windows: it hangs somewhere inside the window it points from.
        var candidates = children(of: app, attribute: kAXWindowsAttribute)
        for window in children(of: app, attribute: kAXWindowsAttribute) {
            findPopovers(in: window, depth: 0, into: &candidates)
        }
        for window in candidates {
            guard let position = point(window, kAXPositionAttribute), let size = size(window, kAXSizeAttribute) else { continue }
            let distance = abs(position.x - frame.minX) + abs(position.y - frame.minY) + abs(size.width - frame.width)
            if distance < bestDistance {
                bestDistance = distance
                best = window
            }
        }
        if bestDistance > 60 {
            return nil
        }
        return best
    }

    /// A coordinate from accessibility as a whole number. An element being laid out can report NaN,
    /// and Int(NaN) stops the app, so a value that is not a number (or too big for Int) shows as "?".
    nonisolated static func whole(_ value: CGFloat) -> String {
        if !value.isFinite || abs(value) > 1_000_000_000 {
            return "?"
        }
        return String(Int(value))
    }

    private static func collect(_ element: AXUIElement, into found: inout [(control: Control, element: AXUIElement)], seen: inout Int, roles: Set<String>) {
        // A safety stop for very large trees (a long history list).
        seen += 1
        if seen > 20_000 { return }
        let role = string(element, kAXRoleAttribute)
        // A scroll bar's arrows and pages are part of the system scroller, not controls of the app.
        if role == "AXScrollBar" { return }
        // The window's own close, minimize and zoom buttons belong to macOS, not to the app.
        let windowButtons: Set<String> = ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"]
        if roles.contains(role) && !windowButtons.contains(string(element, kAXSubroleAttribute)) {
            var label = string(element, kAXDescriptionAttribute)
            if label.isEmpty {
                label = string(element, kAXTitleAttribute)
            }
            // A picker's own name is often the separate text next to it.
            if label.isEmpty {
                label = titleElementText(element)
            }
            // A text field says what goes in it by its placeholder; its tooltip is only the help.
            if label.isEmpty {
                label = string(element, kAXPlaceholderValueAttribute)
            }
            if label.isEmpty {
                label = string(element, kAXIdentifierAttribute)
            }
            if label.isEmpty {
                label = string(element, kAXHelpAttribute)
            }
            // Nothing names it: say where it is, so a report shows which control needs a label.
            if label.isEmpty, let position = point(element, kAXPositionAttribute), let extent = size(element, kAXSizeAttribute) {
                label = "(unlabeled at \(whole(position.x)),\(whole(position.y)) \(whole(extent.width))x\(whole(extent.height)))"
            }
            found.append((control: Control(role: role, label: label), element: element))
        }
        // A stepper's up and down arrows are its own parts: the stepper is the control.
        if role == "AXIncrementor" { return }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            collect(child, into: &found, seen: &seen, roles: roles)
        }
    }

    private static func findPopovers(in element: AXUIElement, depth: Int, into found: inout [AXUIElement]) {
        if depth > 8 { return }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            if string(child, kAXRoleAttribute) == "AXPopover" {
                found.append(child)
            } else {
                findPopovers(in: child, depth: depth + 1, into: &found)
            }
        }
    }

    /// The text of the element that names this one (a picker's label), or "".
    private static func titleElementText(_ element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleUIElementAttribute as CFString, &value) == .success, let found = value, CFGetTypeID(found) == AXUIElementGetTypeID() else { return "" }
        let title = found as! AXUIElement
        var text = string(title, kAXValueAttribute)
        if text.isEmpty {
            text = string(title, kAXTitleAttribute)
        }
        return text
    }

    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let list = value as? [AXUIElement] else { return [] }
        return list
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let found = value else { return nil }
        var result = CGPoint.zero
        if AXValueGetValue(found as! AXValue, .cgPoint, &result) {
            return result
        }
        return nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let found = value else { return nil }
        var result = CGSize.zero
        if AXValueGetValue(found as! AXValue, .cgSize, &result) {
            return result
        }
        return nil
    }
}
#endif
