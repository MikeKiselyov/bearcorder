import XCTest
@testable import BugbearCore

final class JiraReportTests: XCTestCase {
    func testJiraWikiMarkup() {
        var environment = EnvironmentSnapshot(osVersion: "15.1", appName: "Chrome", appVersion: "131.0", url: "stage.example.com/[cart]")
        environment.extras = [EnvironmentSnapshot.Field(name: "Stand", value: "stage-3")]
        let actions = [BugReport.Action(kind: .click, time: 4, target: "\"Pay\" button", app: "Chrome")]
        let text = BugReport.report(environment: environment, actions: actions, files: ["/tmp/clip.mp4"], format: .jira)
        XCTAssertTrue(text.hasPrefix("h2. Summary"))
        XCTAssertTrue(text.contains("# {{00:04}} Click \"Pay\" button in Chrome"))
        XCTAssertTrue(text.contains("* *Stand:* stage-3"))
        XCTAssertTrue(text.contains("* *URL:* stage.example.com/\\[cart\\]"))
        XCTAssertTrue(text.hasSuffix("h2. Attachments\n* {{/tmp/clip.mp4}}"))
    }

    func testExtrasComeFirstAndShowInBadge() {
        var environment = EnvironmentSnapshot(osVersion: "15.1")
        environment.extras = [EnvironmentSnapshot.Field(name: "Build", value: "1.42"), EnvironmentSnapshot.Field(name: "Account", value: "qa+1@example.com")]
        XCTAssertEqual(environment.rows().first?.label, "Build")
        XCTAssertTrue(environment.badgeLines().contains("Build: 1.42 · Account: qa+1@example.com"))
    }

    func testOldCapturesWithoutExtrasStillDecode() throws {
        let json = #"{"osVersion":"15","osBuild":"","deviceModel":"","display":"","appName":"","appVersion":"","appBundleId":"","url":"","locale":"","timeZone":"","appearance":"","capturedAt":0}"#
        let snapshot = try JSONDecoder().decode(EnvironmentSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.extras)
    }
}

final class StoragePolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000_000)

    func item(_ daysAgo: Double, _ megabytes: Int64) -> StoragePolicy.Item {
        return StoragePolicy.Item(id: UUID(), createdAt: now.addingTimeInterval(-daysAgo * 24 * 3600), bytes: megabytes * 1_000_000)
    }

    func testAgeLimit() {
        let old = item(40, 10)
        let recent = item(2, 10)
        let doomed = StoragePolicy.itemsToDelete([old, recent], now: now, maxAgeDays: 30, maxBytes: 0, protected: [])
        XCTAssertEqual(doomed, [old.id])
    }

    func testSizeLimitDeletesOldestAndKeepsProtected() {
        let oldest = item(10, 400)
        let middle = item(5, 400)
        let newest = item(1, 400)
        let doomed = StoragePolicy.itemsToDelete([newest, middle, oldest], now: now, maxAgeDays: 0, maxBytes: 900_000_000, protected: [oldest.id])
        XCTAssertEqual(doomed, [middle.id])
    }

    func testNoLimits() {
        XCTAssertTrue(StoragePolicy.itemsToDelete([item(400, 9000)], now: now, maxAgeDays: 0, maxBytes: 0, protected: []).isEmpty)
    }
}
