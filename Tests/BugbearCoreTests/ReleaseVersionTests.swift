import XCTest
@testable import BugbearCore

final class ReleaseVersionTests: XCTestCase {
    /// The real catalog: newest first, ids 1, 2, 3..., each version higher than the one before.
    func testCatalogIsValid() {
        XCTAssertEqual(WhatsNew.problems(WhatsNewCatalog.releases), [])
        XCTAssertEqual(WhatsNew.latestVersion(WhatsNewCatalog.releases), WhatsNewCatalog.releases[0].version)
    }

    func testVersionsCompareByNumbers() {
        XCTAssertTrue(ReleaseVersion.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(ReleaseVersion.isNewer("1.0.0", than: "0.99.99"))
        XCTAssertTrue(ReleaseVersion.isNewer("0.5.1", than: "0.5.0"))
        XCTAssertFalse(ReleaseVersion.isNewer("0.5.0", than: "0.5.0"))
        XCTAssertFalse(ReleaseVersion.isNewer("0.4.0", than: "0.5.0"))
        XCTAssertFalse(ReleaseVersion.isNewer("garbage", than: "0.5.0"))
    }

    func testVersionFormat() {
        XCTAssertNotNil(ReleaseVersion("0.5.0"))
        XCTAssertNil(ReleaseVersion("0.5"))
        XCTAssertNil(ReleaseVersion("0.5.0.1"))
        XCTAssertNil(ReleaseVersion("v0.5.0"))
        XCTAssertNil(ReleaseVersion("0.-1.0"))
        XCTAssertNil(ReleaseVersion("0..0"))
    }

    func testProblemsCatchMistakes() {
        let item = WhatsNewRelease.Item(symbol: "flag", title: "A", text: "a")
        let sameVersion = [
            WhatsNewRelease(id: 2, version: "0.1.0", title: "Second", items: [item]),
            WhatsNewRelease(id: 1, version: "0.1.0", title: "First", items: [item]),
        ]
        XCTAssertEqual(WhatsNew.problems(sameVersion).count, 1)
        let wrongOrder = [
            WhatsNewRelease(id: 1, version: "0.1.0", title: "First", items: [item]),
            WhatsNewRelease(id: 2, version: "0.2.0", title: "Second", items: [item]),
        ]
        XCTAssertFalse(WhatsNew.problems(wrongOrder).isEmpty)
        let empty = [WhatsNewRelease(id: 1, version: "1.0", title: "", items: [])]
        XCTAssertEqual(WhatsNew.problems(empty).count, 2)
    }

    func testLatestVersionInCatalogSource() {
        let source = """
        public enum WhatsNewCatalog {
            public static let releases: [WhatsNewRelease] = [
                WhatsNewRelease(id: 7, version: "0.7.2", title: "New", items: []),
                WhatsNewRelease(id: 6, version: "0.6.0", title: "Old", items: []),
        """
        XCTAssertEqual(ReleaseVersion.latest(inCatalogSource: source), "0.7.2")
        XCTAssertNil(ReleaseVersion.latest(inCatalogSource: "<html>Not Found</html>"))
    }

    func testMarkdownNotes() {
        let release = WhatsNewRelease(id: 1, version: "0.1.0", title: "Title", items: [
            WhatsNewRelease.Item(symbol: "flag", title: "Mark", text: "Press it.", shortcut: "⌥⇧M"),
            WhatsNewRelease.Item(symbol: "flag", title: "Plain", text: "No shortcut."),
        ])
        XCTAssertEqual(WhatsNew.markdown(release), "## Title\n\n- **Mark** - Press it. (⌥⇧M)\n- **Plain** - No shortcut.")
    }

    func testCatalogURL() {
        XCTAssertEqual(UpdateInfo.catalogURL(repository: "a/b", branch: "main")?.absoluteString, "https://raw.githubusercontent.com/a/b/main/Sources/BugbearCore/Support/WhatsNewCatalog.swift")
        XCTAssertNil(UpdateInfo.catalogURL(repository: "", branch: "main"))
    }
}
