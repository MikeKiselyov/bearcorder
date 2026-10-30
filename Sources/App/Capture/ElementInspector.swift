import AppKit
import ApplicationServices
import Carbon

/// Names the UI element under a click via Accessibility, e.g. `"Submit" button` in Safari.
/// Needs Accessibility access; password fields are reported without their contents.
enum ElementInspector {
    struct Element {
        var target: String
        var app: String
        /// The web page the element is on, read from the browser's web area. Empty outside browsers.
        var url: String = ""
    }

    /// The text field being typed into.
    struct Field {
        var target: String
        var app: String
        var url: String
        /// What the field holds; nil for password fields and when it cannot be read.
        var value: String?
    }

    static let queue = DispatchQueue(label: "app.element-inspector", qos: .utility)
    private static let maxNameLength = 60

    /// `point` is in AppKit global coordinates (origin bottom-left of the main display).
    static func describe(at point: CGPoint, readPage: Bool, completion: @escaping @Sendable (Element?) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(nil)
            return
        }
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let topLeftPoint = CGPoint(x: point.x, y: mainHeight - point.y)
        queue.async {
            completion(lookUp(topLeftPoint, readPage: readPage))
        }
    }

    private static func lookUp(_ point: CGPoint, readPage: Bool) -> Element? {
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
        var url = ""
        if readPage {
            url = pageURL(of: element)
        }
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
            return Element(target: "password field", app: app, url: url)
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
                    return Element(target: label(name: parentName, kind: kind(of: parentRole, element: parentNode)), app: app, url: url)
                }
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Element(target: label(name: name, kind: kind(of: role, element: element)), app: app, url: url)
    }

    /// The focused element of each typing run, kept on `queue` so a run's text is read from the
    /// field it was typed into even after Tab or a click moved the focus.
    nonisolated(unsafe) private static var runFields: [Int: AXUIElement] = [:]

    /// Names the field a typing run goes into, at its first key, and keeps it for `readValue`.
    static func beginField(run: Int, readPage: Bool, completion: @escaping @Sendable (Field?) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(nil)
            return
        }
        queue.async {
            guard let element = focusedElement() else {
                completion(nil)
                return
            }
            runFields[run] = element
            completion(describeField(element, readPage: readPage))
        }
    }

    /// What the run's field holds now. Nil for password fields, multi-line text (a terminal or a
    /// document would give away far more than what was typed), and while macOS has secure input on.
    static func readValue(run: Int, completion: @escaping @Sendable (String?) -> Void) {
        queue.async {
            guard let element = runFields[run] else {
                completion(nil)
                return
            }
            completion(singleLineValue(element))
        }
    }

    /// Forgets the run's field.
    static func endField(run: Int) {
        queue.async {
            runFields[run] = nil
        }
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.3)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let found = focused, CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        let element = found as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.3)
        var processId: pid_t = 0
        AXUIElementGetPid(element, &processId)
        if processId == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        return element
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        return role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    private static func describeField(_ element: AXUIElement, readPage: Bool) -> Field {
        var processId: pid_t = 0
        AXUIElementGetPid(element, &processId)
        let app = NSRunningApplication(processIdentifier: processId)?.localizedName ?? ""
        var url = ""
        if readPage {
            url = pageURL(of: element)
        }
        if isSecure(element) {
            return Field(target: "password field", app: app, url: url, value: nil)
        }
        let role = string(element, kAXRoleAttribute)
        let name = name(of: element, role: role).trimmingCharacters(in: .whitespacesAndNewlines)
        return Field(target: label(name: name, kind: kind(of: role, element: element)), app: app, url: url, value: nil)
    }

    private static func singleLineValue(_ element: AXUIElement) -> String? {
        if IsSecureEventInputEnabled() || isSecure(element) {
            return nil
        }
        let role = string(element, kAXRoleAttribute)
        let singleLine = role == "AXTextField" || role == "AXComboBox" || role == "AXSearchField"
        if !singleLine {
            return nil
        }
        let value = string(element, kAXValueAttribute)
        if value.isEmpty || value.contains("\n") {
            return nil
        }
        return value
    }

    /// The address of the web page around `element`: browsers give their web area an AXURL.
    static func pageURL(of element: AXUIElement) -> String {
        var current: AXUIElement? = element
        var steps = 0
        while let node = current, steps < 100 {
            if string(node, kAXRoleAttribute) == "AXWebArea" {
                var value: AnyObject?
                if AXUIElementCopyAttributeValue(node, "AXURL" as CFString, &value) == .success, let found = value {
                    if let url = found as? URL {
                        return pageAddress(url)
                    }
                    if let text = found as? String, let url = URL(string: text) {
                        return pageAddress(url)
                    }
                }
                return ""
            }
            var parent: AnyObject?
            guard AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parent) == .success,
                  let parentNode = parent, CFGetTypeID(parentNode) == AXUIElementGetTypeID() else { return "" }
            current = (parentNode as! AXUIElement)
            steps += 1
        }
        return ""
    }

    /// Web pages only, without the part after # (it changes while scrolling some apps).
    private static func pageAddress(_ url: URL) -> String {
        guard let scheme = url.scheme, scheme == "http" || scheme == "https" || scheme == "file" else { return "" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
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
