import Foundation

/// How the app picks its language and checks its translations. The text itself lives in
/// `Sources/Bugbear/Resources/<language>.lproj/<table>.strings`, one table per part of the app; a
/// key starts with its table: `settings.page.general` is in `settings.strings`. Adding a language
/// is adding a folder with the same tables and keys.
public enum Localization {
    /// The language every key has; the others may miss keys and fall back to it.
    public static let base = "en"

    /// The table a key lives in: the part before the first dot.
    public static func table(of key: String) -> String {
        guard let dot = key.firstIndex(of: ".") else { return key }
        return String(key[..<dot])
    }

    /// The first of the person's languages (System Settings → Language & Region) the app has, by its
    /// language code and script; the base language when none is there. "pt-BR" picks "pt-BR", then
    /// "pt"; "zh-Hant-TW" picks "zh-Hant", never "zh-Hans".
    public static func language(available: [String], preferred: [String]) -> String {
        for wanted in preferred {
            if available.contains(wanted) {
                return wanted
            }
            let code = languageCode(wanted)
            for language in available where languageCode(language) == code {
                return language
            }
        }
        return base
    }

    /// The language and, when there is one, the script: "pt-BR" → "pt", "zh-Hant-TW" → "zh-hant".
    static func languageCode(_ identifier: String) -> String {
        let parts = identifier.split(whereSeparator: { character in character == "-" || character == "_" })
        guard let language = parts.first else { return identifier.lowercased() }
        var code = String(language)
        // A script is four letters (Hans, Hant, Latn, Cyrl); a region is two letters or three digits.
        if parts.count > 1 && parts[1].count == 4 && parts[1].allSatisfy({ character in character.isLetter }) {
            code += "-" + String(parts[1])
        }
        return code.lowercased()
    }

    /// The placeholders of a format string in order (`%@`, `%d`, `%lld`, `%1$@`...), so a translation
    /// can be checked to take the same values. `%%` is a plain percent sign.
    public static func placeholders(in format: String) -> [String] {
        var found: [String] = []
        let characters = Array(format)
        var index = 0
        while index < characters.count {
            if characters[index] != "%" {
                index += 1
                continue
            }
            if index + 1 < characters.count && characters[index + 1] == "%" {
                index += 2
                continue
            }
            var end = index + 1
            var placeholder = "%"
            while end < characters.count {
                let character = characters[end]
                placeholder.append(character)
                end += 1
                if character.isLetter && character != "l" && character != "h" && character != "q" {
                    break
                }
                if character == "@" {
                    break
                }
            }
            found.append(placeholder)
            index = end
        }
        return found
    }
}
