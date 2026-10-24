import AppKit
import ApplicationServices

/// Names the UI element under a click via Accessibility, e.g. `"Submit" button` in Safari.
/// Needs Accessibility access; password fields are reported without their contents.
enum ElementInspector {
    struct Element {
        var target: String
        var app: String
    }

    private static let queue = DispatchQueue(label: "bugbear.element-inspector", qos: .utility)
    private static let maxNameLength = 60

    /// `point` is in AppKit global coordinates (origin bottom-left of the main display).
    static func describe(at point: CGPoint, completion: @escaping @Sendable (Element?) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(nil)
            return
        }
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let topLeftPoint = CGPoint(x: point.x, y: mainHeight - point.y)
        queue.async {
            completion(lookUp(topLeftPoint))
        }
    }

    private static func lookUp(_ point: CGPoint) -> Element? {
        let systemWide = AXUIElementCreateSystemWide()
        // A hung app must not stall recording: give up quickly.
        AXUIElementSetMessagingTimeout(systemWide, 0.3)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &found) == .success, let element = found else {
            return nil
        }
        var processId: pid_t = 0
        AXUIElementGetPid(element, &processId)
        let app = NSRunningApplication(processIdentifier: processId)?.localizedName ?? ""

        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
            return Element(target: "password field", app: app)
        }
        var name = name(of: element, role: role)
        if name.isEmpty && (role == "AXStaticText" || role == "AXImage" || role == "AXGroup") {
            var parent: AnyObject?
            let hasParent = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success
            if hasParent, let parentElement = parent, CFGetTypeID(parentElement) == AXUIElementGetTypeID() {
                let parentNode = parentElement as! AXUIElement
                let parentRole = string(parentNode, kAXRoleAttribute)
                let parentName = Self.name(of: parentNode, role: parentRole)
                if !parentName.isEmpty {
                    return Element(target: label(name: parentName, kind: kind(of: parentRole, element: parentNode)), app: app)
                }
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Element(target: label(name: name, kind: kind(of: role, element: element)), app: app)
    }

    private static func label(name: String, kind: String) -> String {
        var shortName = name.replacingOccurrences(of: "\n", with: " ")
        if shortName.count > maxNameLength {
            shortName = String(shortName.prefix(maxNameLength)) + "…"
        }
        if shortName.isEmpty {
            return kind
        }
        if kind.isEmpty {
            return "\"\(shortName)\""
        }
        return "\"\(shortName)\" \(kind)"
    }

    /// Visible name only. Values of text fields are never read: they may hold personal data.
    private static func name(of element: AXUIElement, role: String) -> String {
        let title = string(element, kAXTitleAttribute)
        if !title.isEmpty { return title }
        let description = string(element, kAXDescriptionAttribute)
        if !description.isEmpty { return description }
        if role == "AXStaticText" || role == "AXLink" || role == "AXMenuItem" || role == "AXMenuBarItem" {
            return string(element, kAXValueAttribute)
        }
        if role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox" {
            return string(element, kAXPlaceholderValueAttribute)
        }
        return ""
    }

    private static func kind(of role: String, element: AXUIElement) -> String {
        switch role {
        case "AXButton": return "button"
        case "AXLink": return "link"
        case "AXTextField": return "text field"
        case "AXTextArea": return "text area"
        case "AXComboBox": return "combo box"
        case "AXCheckBox": return "checkbox"
        case "AXRadioButton": return "radio button"
        case "AXPopUpButton": return "pop-up menu"
        case "AXMenuButton": return "menu button"
        case "AXMenuItem": return "menu item"
        case "AXMenuBarItem": return "menu"
        case "AXSlider": return "slider"
        case "AXTabGroup": return "tab"
        case "AXCell", "AXRow": return "row"
        case "AXImage": return "image"
        case "AXStaticText": return "text"
        case "AXGroup", "AXScrollArea", "AXWebArea", "AXWindow", "AXSplitGroup", "AXLayoutArea", "AXUnknown", "": return ""
        default: return string(element, kAXRoleDescriptionAttribute)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
}
