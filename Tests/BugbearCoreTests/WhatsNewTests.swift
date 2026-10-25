import XCTest
@testable import BugbearCore

final class WhatsNewTests: XCTestCase {
    let releases = [
        WhatsNewRelease(id: 1, version: "0.1.0", title: "First", items: [WhatsNewRelease.Item(symbol: "flag", title: "A", text: "a")]),
        WhatsNewRelease(id: 2, version: "0.2.0", title: "Second", items: [WhatsNewRelease.Item(symbol: "flag", title: "B", text: "b")]),
        WhatsNewRelease(id: 3, version: "0.3.0", title: "Third", items: [WhatsNewRelease.Item(symbol: "flag", title: "C", text: "c")]),
    ]

    func testUnseenNewestFirst() {
        let unseen = WhatsNew.unseen(releases, lastSeenID: 1)
        XCTAssertEqual(unseen.count, 2)
        XCTAssertEqual(unseen[0].id, 3)
        XCTAssertEqual(unseen[1].id, 2)
        XCTAssertTrue(WhatsNew.unseen(releases, lastSeenID: 3).isEmpty)
        XCTAssertEqual(WhatsNew.latestID(releases), 3)
    }

    func testWhenToShow() {
        XCTAssertTrue(WhatsNew.shouldShow(unseenReleases: [releases[0]], updatedFromCommit: "", changes: []))
        XCTAssertTrue(WhatsNew.shouldShow(unseenReleases: [], updatedFromCommit: "abc", changes: ["Fix menu"]))
        // A rebuild without an update and without new notes stays quiet.
        XCTAssertFalse(WhatsNew.shouldShow(unseenReleases: [], updatedFromCommit: "", changes: ["Local commit"]))
        XCTAssertFalse(WhatsNew.shouldShow(unseenReleases: [], updatedFromCommit: "abc", changes: []))
    }
}
