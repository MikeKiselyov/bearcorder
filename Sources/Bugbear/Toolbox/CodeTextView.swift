import AppKit
import SwiftUI

/// Monospaced text view without smart quotes or autocorrect (they break JSON).
/// Read-only views can show syntax-highlighted text.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var highlight: ((String) -> NSAttributedString)? = nil
    var placeholder: String = ""
    /// What VoiceOver (and tests) call it; "Input" or "Output" when not given.
    var label: String? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor(hex: 0xC9CBD0)
        textView.backgroundColor = NSColor(hex: 0x151618)
        textView.drawsBackground = true
        textView.insertionPointColor = NSColor(hex: 0xFF8C70)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.setAccessibilityLabel(label ?? (isEditable ? "Input" : "Output"))
        context.coordinator.textView = textView
        apply(text, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        if textView.string != text {
            apply(text, to: textView)
        } else if highlight != nil && !isEditable {
            // Same text but the highlighter may have changed.
            apply(text, to: textView)
        }
    }

    private func apply(_ value: String, to textView: NSTextView) {
        if let highlighter = highlight {
            textView.textStorage?.setAttributedString(highlighter(value))
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(hex: 0xC9CBD0),
            ]
            textView.textStorage?.setAttributedString(NSAttributedString(string: value, attributes: attributes))
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        weak var textView: NSTextView?

        init(parent: CodeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

/// Lightweight JSON highlighting for output panes.
enum SyntaxHighlighter {
    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(hex: 0xC9CBD0),
    ]

    static func json(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        if text.count > 400_000 { return result }
        let characters = Array(text.utf16)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == 34 { // "
                let start = index
                index += 1
                while index < characters.count {
                    if characters[index] == 92 { // backslash
                        index += 2
                        continue
                    }
                    if characters[index] == 34 { break }
                    index += 1
                }
                let end = min(index + 1, characters.count)
                // A string followed by ':' is a key.
                var lookahead = end
                while lookahead < characters.count && (characters[lookahead] == 32 || characters[lookahead] == 9) {
                    lookahead += 1
                }
                let isKey = lookahead < characters.count && characters[lookahead] == 58
                let color = isKey ? NSColor(hex: 0x8AB8FF) : NSColor(hex: 0x3DD68C)
                result.addAttribute(.foregroundColor, value: color, range: NSRange(location: start, length: end - start))
                index = end
                continue
            }
            if (character >= 48 && character <= 57) || character == 45 {
                let start = index
                while index < characters.count {
                    let current = characters[index]
                    let isNumberChar = (current >= 48 && current <= 57) || current == 46 || current == 45 || current == 43 || current == 101 || current == 69
                    if !isNumberChar { break }
                    index += 1
                }
                result.addAttribute(.foregroundColor, value: NSColor(hex: 0xFFC93C), range: NSRange(location: start, length: index - start))
                continue
            }
            if character == 116 || character == 102 || character == 110 { // t f n
                for word in ["true", "false", "null"] {
                    let length = word.utf16.count
                    if index + length <= characters.count {
                        let slice = String(utf16CodeUnits: Array(characters[index..<(index + length)]), count: length)
                        if slice == word {
                            result.addAttribute(.foregroundColor, value: NSColor(hex: 0xC792EA), range: NSRange(location: index, length: length))
                            index += length - 1
                            break
                        }
                    }
                }
            }
            index += 1
        }
        return result
    }

    /// Tags and attribute names for XML/HTML.
    static func markup(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        if text.count > 400_000 { return result }
        let nsText = text as NSString
        let patterns: [(String, NSColor)] = [
            ("</?[A-Za-z_][\\w:.-]*", NSColor(hex: 0x8AB8FF)),
            ("/?>", NSColor(hex: 0x8AB8FF)),
            ("\\s[A-Za-z_:][\\w:.-]*(?==)", NSColor(hex: 0xFFC93C)),
            ("\"[^\"]*\"", NSColor(hex: 0x3DD68C)),
            ("<!--[\\s\\S]*?-->", NSColor(hex: 0x5F636B)),
        ]
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                result.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        return result
    }
}
