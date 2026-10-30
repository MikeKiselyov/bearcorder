import AppCore
import XCTest

/// Picking the app's language and checking that a translation takes the same values.
final class LocalizationLogicTests: XCTestCase {
    func testTheFirstLanguageTheAppHasWins() {
        XCTAssertEqual(Localization.language(available: ["en", "ru", "de"], preferred: ["fr", "ru", "en"]), "ru")
    }

    func testARegionFallsBackToItsLanguage() {
        XCTAssertEqual(Localization.language(available: ["en", "pt"], preferred: ["pt-BR"]), "pt")
        XCTAssertEqual(Localization.language(available: ["en", "pt-BR", "pt"], preferred: ["pt-BR"]), "pt-BR")
        XCTAssertEqual(Localization.language(available: ["en", "zh-Hans"], preferred: ["zh-Hans-CN"]), "zh-Hans")
    }

    func testAScriptIsNotMixedUp() {
        XCTAssertEqual(Localization.language(available: ["en", "zh-Hans"], preferred: ["zh-Hant-TW"]), "en", "Traditional Chinese readers do not get Simplified")
        XCTAssertEqual(Localization.language(available: ["en", "zh-Hans", "zh-Hant"], preferred: ["zh-Hant-HK"]), "zh-Hant")
        XCTAssertEqual(Localization.language(available: ["en", "sr-Latn"], preferred: ["sr-Latn-RS"]), "sr-Latn")
    }

    func testEnglishWhenNothingMatches() {
        XCTAssertEqual(Localization.language(available: ["en", "ru"], preferred: ["ja"]), "en")
        XCTAssertEqual(Localization.language(available: [], preferred: []), "en")
    }

    func testTheTableIsTheStartOfTheKey() {
        XCTAssertEqual(Localization.table(of: "settings.page.general"), "settings")
        XCTAssertEqual(Localization.table(of: "menubar"), "menubar")
    }

    func testPlaceholdersInOrder() {
        XCTAssertEqual(Localization.placeholders(in: "Saved %@ in %d s"), ["%@", "%d"])
        XCTAssertEqual(Localization.placeholders(in: "%lld captures, 100%% done"), ["%lld"])
        XCTAssertEqual(Localization.placeholders(in: "%2$@ then %1$@"), ["%2$@", "%1$@"])
        XCTAssertEqual(Localization.placeholders(in: "no values"), [])
        XCTAssertEqual(Localization.placeholders(in: "%.1f MB"), ["%.1f"])
    }
}
