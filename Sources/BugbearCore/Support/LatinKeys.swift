import Foundation

/// The Latin character a key prints on a US layout, by its key code. Shortcuts follow the key, not
/// the layout: with a Russian layout V types "м", and ⌘V still has to paste.
public enum LatinKeys {
    /// Key codes of the ANSI keyboard (kVK_ANSI_*), upper-case letters.
    public static let names: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 43: ",", 47: ".", 44: "/", 41: ";", 39: "'", 33: "[", 30: "]", 42: "\\", 50: "`",
    ]

    /// The key's character in lower case, or `typed` (lower-cased) for keys outside the table.
    public static func key(forKeyCode keyCode: UInt16, typed: String) -> String {
        if let name = names[keyCode] {
            return name.lowercased()
        }
        return typed.lowercased()
    }
}
