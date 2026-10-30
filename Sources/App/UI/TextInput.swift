import AppKit

/// Typing into a text field or text view the way the keyboard ends up: the text changes and the
/// field tells its delegate, so a SwiftUI binding sees it. Tests type here instead of posting keys,
/// which could land in another app.
@MainActor
enum TextInput {
    /// The text field or text view under a point of the window, in top-left screen points.
    static func view(at point: CGPoint, in window: NSWindow) -> NSView? {
        guard let content = window.contentView else { return nil }
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let bottomLeft = CGPoint(x: point.x, y: screenHeight - point.y)
        var stack: [NSView] = [content]
        var found: NSView?
        while let current = stack.popLast() {
            if current is NSTextField || current is NSTextView, !current.isHiddenOrHasHiddenAncestor {
                let frame = window.convertToScreen(current.convert(current.visibleRect, to: nil))
                if frame.contains(bottomLeft) {
                    found = current
                }
            }
            for child in current.subviews {
                stack.append(child)
            }
        }
        return found
    }

    /// The text field or text view with this name (placeholder or accessibility label), visible or
    /// scrolled out of sight; nil when none or more than one has it.
    static func view(labeled label: String, in window: NSWindow) -> NSView? {
        guard let content = window.contentView else { return nil }
        var stack: [NSView] = [content]
        var matches: [NSView] = []
        while let current = stack.popLast() {
            if current is NSTextField || current is NSTextView, !current.isHiddenOrHasHiddenAncestor {
                var names: [String] = []
                if let field = current as? NSTextField, let placeholder = field.placeholderString {
                    names.append(placeholder)
                }
                names.append(current.accessibilityLabel() ?? "")
                if names.contains(label) {
                    matches.append(current)
                }
            }
            for child in current.subviews {
                stack.append(child)
            }
        }
        if matches.count == 1 {
            return matches[0]
        }
        return nil
    }

    /// Replaces the text and tells the delegate it changed. False for a view that takes no text.
    /// `endEditing` false leaves the cursor in the field, like a person still typing.
    static func type(_ text: String, into view: NSView, endEditing: Bool = true) -> Bool {
        if let textView = view as? NSTextView {
            if !textView.isEditable { return false }
            textView.string = text
            textView.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: textView))
            return true
        }
        if let field = view as? NSTextField {
            // A field nobody could type in is not typed into either.
            if !field.isEditable || !field.isEnabled { return false }
            // Like a person: click in, type, click away. A field changed without its editor is left
            // half-edited, and SwiftUI then keeps its text over later changes.
            guard let window = field.window, window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else { return false }
            editor.string = text
            editor.didChangeText()
            if endEditing {
                window.makeFirstResponder(nil)
            }
            return true
        }
        return false
    }
}
