import BugbearCore
import Foundation

/// The text for a key in the person's language: `L("settings.page.general")`, or with values for a
/// format: `L("history.count", count)` with "%d captures" in the table (plurals in a `.stringsdict`).
/// A key missing everywhere shows as itself, so it is easy to spot; RepoTests fail on it first.
func L(_ key: String, _ values: CVarArg...) -> String {
    let format = L10n.text(for: key)
    if values.isEmpty {
        return format
    }
    // Numbers and count forms follow the language of the text, not the region's other settings.
    return String(format: format, locale: L10n.locale, arguments: values)
}

enum L10n {
    /// The `.lproj` folder of the language in use, and the base language's for keys it lacks.
    private static let bundles: (chosen: Bundle?, base: Bundle?) = {
        guard let resources = AppResources.bundle else { return (nil, nil) }
        return languageBundles(in: resources, preferred: Locale.preferredLanguages)
    }()

    static func languageBundles(in resources: Bundle, preferred: [String]) -> (chosen: Bundle?, base: Bundle?) {
        let language = Localization.language(available: resources.localizations, preferred: preferred)
        return (lproj(language, in: resources), lproj(Localization.base, in: resources))
    }

    /// The language the app shows.
    static let language: String = {
        guard let resources = AppResources.bundle else { return Localization.base }
        return Localization.language(available: resources.localizations, preferred: Locale.preferredLanguages)
    }()

    /// Formats values the way the app's language writes them.
    static let locale = Locale(identifier: language)

    static func text(for key: String) -> String {
        return text(for: key, in: bundles)
    }

    /// The text from the chosen language, else the base language, else the key itself.
    static func text(for key: String, in bundles: (chosen: Bundle?, base: Bundle?)) -> String {
        let table = Localization.table(of: key)
        let missing = "\u{0}"
        for bundle in [bundles.chosen, bundles.base] {
            guard let found = bundle?.localizedString(forKey: key, value: missing, table: table) else { continue }
            if found != missing {
                return found
            }
        }
        return key
    }

    private static func lproj(_ language: String, in resources: Bundle) -> Bundle? {
        guard let path = resources.path(forResource: language, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}
