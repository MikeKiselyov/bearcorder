import Foundation

/// Strings of an exact length for testing field limits, and length counts of any text.
public enum LengthString {
    public enum Style: String, CaseIterable, Identifiable {
        /// James Bach's counterstring: "2*4*6*8*11*", every * sits at the position written before it.
        case counter = "Counterstring"
        case letters = "a a a"
        /// Two bytes per character in UTF-8.
        case cyrillic = "Cyrillic"
        /// Two UTF-16 units and four UTF-8 bytes per character.
        case emoji = "Emoji"

        public var id: String { rawValue }
    }

    public struct Counts: Equatable {
        public var characters: Int
        public var utf16: Int
        public var utf8Bytes: Int
        public var words: Int
        public var lines: Int
    }

    public static let maximum = 1_000_000

    /// Exactly `length` characters (grapheme clusters).
    public static func make(length: Int, style: Style) -> String {
        let count = max(0, min(maximum, length))
        switch style {
        case .counter:
            return counterstring(count)
        case .letters:
            return String(repeating: "a", count: count)
        case .cyrillic:
            return String(repeating: "ж", count: count)
        case .emoji:
            return String(repeating: "😀", count: count)
        }
    }

    /// Built from the end: each "N*" ends at position N, so the last * shows the length.
    static func counterstring(_ length: Int) -> String {
        var pieces: [String] = []
        var position = length
        while position > 0 {
            var piece = "\(position)*"
            if piece.count > position {
                piece = String(piece.suffix(position))
            }
            pieces.append(piece)
            position -= piece.count
        }
        var result = ""
        for piece in pieces.reversed() {
            result += piece
        }
        return result
    }

    public static func counts(_ text: String) -> Counts {
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, _, _, _ in
            words += 1
        }
        var lines = 0
        if !text.isEmpty {
            lines = text.components(separatedBy: "\n").count
        }
        return Counts(characters: text.count, utf16: text.utf16.count, utf8Bytes: text.utf8.count, words: words, lines: lines)
    }
}
