import AppCore
import Foundation
import XCTest

/// Every text people see comes from Sources/App/Resources/Localization/<language>.lproj, so a new
/// language is a new folder. These checks keep that true: every key the code uses is in the English
/// tables and every key there is used, every language has the same keys taking the same values, and
/// no window, button, tooltip or alert text is written straight into the code.
final class LocalizationTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private var localizationFolder: URL {
        return root.appendingPathComponent("Sources/App/Resources/Localization")
    }

    /// The app's code that people see: everything but the developer tools (DevTools/, not in a release).
    private func appSources() -> [(path: String, text: String)] {
        let folder = root.appendingPathComponent("Sources/App")
        var files: [(path: String, text: String)] = []
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension != "swift" { continue }
            if url.path.contains("/DevTools/") { continue }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            files.append((path: url.path.replacingOccurrences(of: root.path + "/", with: ""), text: text))
        }
        return files.sorted { first, second in first.path < second.path }
    }

    /// Keys and texts of every table of a language: [table: [key: text]]. A text with a count lives in
    /// `<table>.stringsdict`; its forms are joined into one text here ("%#@n@ | %d file | %d files"),
    /// so placeholders and keys are checked the same way for both kinds.
    private func tables(language: String) -> [String: [String: String]] {
        let folder = localizationFolder.appendingPathComponent("\(language).lproj")
        var result: [String: [String: String]] = [:]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".strings") {
            let url = folder.appendingPathComponent(name)
            let table = String(name.dropLast(".strings".count))
            let entries = NSDictionary(contentsOf: url) as? [String: String]
            XCTAssertNotNil(entries, "\(language).lproj/\(name) is not a valid strings file")
            for (key, text) in entries ?? [:] {
                result[table, default: [:]][key] = text
            }
        }
        for name in names.sorted() where name.hasSuffix(".stringsdict") {
            let url = folder.appendingPathComponent(name)
            let table = String(name.dropLast(".stringsdict".count))
            let entries = NSDictionary(contentsOf: url) as? [String: [String: Any]]
            XCTAssertNotNil(entries, "\(language).lproj/\(name) is not a valid stringsdict file")
            for (key, entry) in entries ?? [:] {
                XCTAssertNil(result[table]?[key], "\(key) is in both \(table).strings and \(table).stringsdict")
                result[table, default: [:]][key] = joinedForms(entry, key: key, language: language)
            }
        }
        return result
    }

    /// The format and, for each count in it, the "other" form: what every language must have with
    /// the same placeholders. Other forms (one, few, many) may drop the number, as "one" often does.
    private func joinedForms(_ entry: [String: Any], key: String, language: String) -> String {
        let format = entry["NSStringLocalizedFormatKey"] as? String ?? ""
        XCTAssertFalse(format.isEmpty, "\(language) \(key) has no NSStringLocalizedFormatKey")
        var parts = [format]
        for name in entry.keys.sorted() where name != "NSStringLocalizedFormatKey" {
            guard let rule = entry[name] as? [String: String] else { continue }
            XCTAssertEqual(rule["NSStringFormatSpecTypeKey"], "NSStringPluralRuleType", "\(language) \(key).\(name) is not a plural rule")
            XCTAssertNotNil(rule["other"], "\(language) \(key).\(name) has no \"other\" form")
            parts.append(rule["other"] ?? "")
        }
        return parts.joined(separator: " | ")
    }

    private func languages() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: localizationFolder.path)) ?? []
        var found: [String] = []
        for name in names where name.hasSuffix(".lproj") {
            found.append(String(name.dropLast(".lproj".count)))
        }
        return found.sorted()
    }

    /// `L("key"` in the code. Keys are always written out, never built, so they can be checked.
    private func usedKeys() -> [String: String] {
        var keys: [String: String] = [:]
        let pattern = try! NSRegularExpression(pattern: #"\bL\("([^"\\]+)""#)
        for file in appSources() {
            for line in file.text.components(separatedBy: "\n") {
                // Examples in comments are not uses.
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                let range = NSRange(line.startIndex..., in: line)
                for match in pattern.matches(in: line, range: range) {
                    if let keyRange = Range(match.range(at: 1), in: line) {
                        keys[String(line[keyRange])] = file.path
                    }
                }
            }
        }
        return keys
    }

    func testEnglishIsThere() {
        XCTAssertTrue(languages().contains(Localization.base), "no \(Localization.base).lproj")
        XCTAssertFalse(tables(language: Localization.base).isEmpty)
    }

    func testEveryKeyInTheCodeHasAnEnglishText() {
        let english = tables(language: Localization.base)
        for (key, path) in usedKeys().sorted(by: { first, second in first.key < second.key }) {
            let table = Localization.table(of: key)
            XCTAssertNotNil(english[table]?[key], "\(path) uses \(key), which is not in en.lproj/\(table).strings")
        }
    }

    func testEveryEnglishTextIsUsed() {
        let used = usedKeys()
        for (table, entries) in tables(language: Localization.base) {
            for key in entries.keys.sorted() {
                XCTAssertNotNil(used[key], "en.lproj/\(table).strings has \(key), which no code uses: delete it")
                XCTAssertEqual(Localization.table(of: key), table, "\(key) is in \(table).strings; a key starts with its table")
            }
        }
    }

    func testEveryLanguageHasTheSameKeysAndValues() {
        let english = tables(language: Localization.base)
        for language in languages() where language != Localization.base {
            let translated = tables(language: language)
            XCTAssertEqual(Set(translated.keys), Set(english.keys), "\(language).lproj has other tables than en.lproj")
            for (table, entries) in english {
                let other = translated[table] ?? [:]
                for (key, text) in entries {
                    guard let translation = other[key] else {
                        XCTFail("\(language).lproj/\(table).strings has no \(key)")
                        continue
                    }
                    XCTAssertEqual(Localization.placeholders(in: translation), Localization.placeholders(in: text), "\(language) \(key) takes other values than English: \(translation)")
                }
                for key in other.keys where entries[key] == nil {
                    XCTFail("\(language).lproj/\(table).strings has \(key), which English does not")
                }
            }
        }
    }

    /// Text written straight into a view or an alert would stay English in every language. The whole
    /// file is searched, so a call split over lines is found too; comment lines are left out. A text
    /// that stays English on purpose says why on its line: `// l10n-ignore: goes into the GitHub issue`.
    func testNoTextIsWrittenIntoTheCode() {
        let calls = [
            "Text", "Button", "Toggle", "Label", "Section", "Picker", "Menu", "DisclosureGroup", "SectionLabel",
            "TextField", "Link", "LabeledContent", "\\.tip", "\\.help", "\\.accessibilityLabel", "\\.accessibilityHint",
            "\\.navigationTitle", "Toast\\.shared\\.show", "showError", "addButton\\(withTitle:",
        ]
        let assignments = ["messageText", "informativeText", "placeholderString", "statusMessage", "title"]
        // Arguments of the app's own views and buttons that are shown as they are.
        let arguments = ["title", "label", "help", "placeholder", "message"]
        var patterns: [String] = []
        for call in calls {
            // A literal that starts with a letter: "Save", not "" or "%@" or "⌘".
            patterns.append(#"(?<![A-Za-z_])"# + call + #"\(\s*"[A-Za-z]"#)
        }
        for name in assignments {
            patterns.append(#"\."# + name + #"\s*=\s*"[A-Za-z]"#)
        }
        for name in arguments {
            // A word as people write it ("Copy", "Show more"); names like "RGB", "SwiftUI" or
            // "camelCase" are not words to translate.
            patterns.append(#"[(,]\s*"# + name + #":\s*"[A-Z][a-z]+[ "]"#)
        }
        let expression = try! NSRegularExpression(pattern: patterns.joined(separator: "|"))
        var written: [String] = []
        for file in appSources() {
            var lines: [String] = []
            for line in file.text.components(separatedBy: "\n") {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    lines.append("")
                } else {
                    lines.append(line)
                }
            }
            let text = lines.joined(separator: "\n")
            let range = NSRange(text.startIndex..., in: text)
            for match in expression.matches(in: text, range: range) {
                guard let found = Range(match.range, in: text) else { continue }
                let number = text[..<found.lowerBound].filter { character in character == "\n" }.count + 1
                // "// l10n-ignore: <why>" on the line keeps a text English on purpose.
                if lines[number - 1].contains("// l10n-ignore:") { continue }
                let shown = text[found].replacingOccurrences(of: "\n", with: " ")
                written.append("\(file.path):\(number): \(shown)")
            }
        }
        XCTAssertTrue(written.isEmpty, "Text written into the code instead of L(\"key\"):\n" + written.joined(separator: "\n"))
    }
}
