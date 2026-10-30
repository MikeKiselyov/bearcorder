import XCTest
@testable import AppCore

final class JiraReportTests: XCTestCase {
    func testJiraWikiMarkup() {
        var environment = EnvironmentSnapshot(osVersion: "15.1", appName: "Chrome", appVersion: "131.0", url: "stage.example.com/[cart]")
        environment.extras = [EnvironmentSnapshot.Field(name: "Stand", value: "stage-3")]
        let actions = [BugReport.Action(kind: .click, time: 4, target: "\"Pay\" button", app: "Chrome")]
        let text = BugReport.report(environment: environment, actions: actions, format: .jira)
        XCTAssertTrue(text.hasPrefix("h2. Steps to reproduce"), text)
        XCTAssertTrue(text.contains("# Click \"Pay\" button in Chrome"))
        XCTAssertTrue(text.contains("* *Stand:* stage-3"))
        XCTAssertTrue(text.contains("* *URL:* stage.example.com/\\[cart\\]"))
        XCTAssertFalse(text.contains("Attachments") || text.contains("Summary") || text.contains("{{00:"), text)
    }

    func testExtrasComeFirstAndShowInBadge() {
        var environment = EnvironmentSnapshot(osVersion: "15.1")
        environment.extras = [EnvironmentSnapshot.Field(name: "Build", value: "1.42"), EnvironmentSnapshot.Field(name: "Account", value: "qa+1@example.com")]
        XCTAssertEqual(environment.rows().first?.label, "Build")
        XCTAssertTrue(environment.badgeLines().contains("Build: 1.42 · Account: qa+1@example.com"))
    }

    func testHiddenFieldsLeaveThePanelTheBadgeAndTheReport() {
        var environment = EnvironmentSnapshot(osVersion: "15.1", deviceModel: "Mac15,3", display: "3024×1964 @2x", appName: "Chrome", appVersion: "131.0", url: "stage.example.com", locale: "en-US")
        environment.hiddenFields = ["Locale", "URL", "Time"]
        var labels: [String] = []
        for row in environment.rows() {
            labels.append(row.label)
        }
        XCTAssertEqual(labels, ["macOS", "Device", "Display", "App"])
        let badge = environment.badgeLines()
        XCTAssertEqual(badge, ["macOS 15.1 · Chrome 131.0", "Mac15,3", "3024×1964 @2x"])
        let report = BugReport.report(environment: environment, actions: [], format: .markdown)
        XCTAssertFalse(report.contains("stage.example.com"))
        XCTAssertFalse(report.contains("Locale"))
        XCTAssertTrue(report.contains("- Device: Mac15,3"))
    }

    /// The badge left out Device, Locale and Appearance although they were on.
    func testBadgeShowsEveryFieldThatIsOn() {
        var environment = EnvironmentSnapshot(osVersion: "15.1", deviceModel: "Mac15,3", display: "3024×1964 @2x", appName: "Chrome", appVersion: "131.0", url: "stage.example.com", locale: "en-US")
        environment.appearance = "Dark"
        environment.hiddenFields = ["Time"]
        XCTAssertEqual(environment.badgeLines(), ["macOS 15.1 · Chrome 131.0", "Mac15,3", "3024×1964 @2x", "stage.example.com", "en-US · Dark"])
        environment.hiddenFields = ["Time", "Locale"]
        XCTAssertEqual(environment.badgeLines().last, "Dark")
    }

    func testHiddenMacOSAndAppLeaveNoEmptyBadgeLine() {
        var environment = EnvironmentSnapshot(osVersion: "15.1", appName: "Chrome")
        environment.hiddenFields = ["macOS", "App", "Time"]
        XCTAssertEqual(environment.badgeLines(), [])
        environment.hiddenFields = ["App", "Time"]
        environment.osBuild = "24B83"
        XCTAssertEqual(environment.badgeLines(), ["macOS 15.1 (24B83)"])
    }

    func testRenamedFieldsShowTheirNewName() {
        var environment = EnvironmentSnapshot(osVersion: "15.1", deviceModel: "Mac15,3", appName: "Chrome")
        environment.renamedFields = ["Device": "Model", "App": "  ", "Time": "Captured at"]
        var labels: [String] = []
        for row in environment.rows() {
            labels.append(row.label)
        }
        XCTAssertEqual(labels, ["macOS", "Model", "App", "Captured at"])
        let jira = BugReport.report(environment: environment, actions: [], format: .jira)
        XCTAssertTrue(jira.contains("* *Model:* Mac15,3"))
        XCTAssertFalse(jira.contains("*Device:*"))
    }

    func testFieldChoicesAreSavedWithTheCapture() throws {
        var environment = EnvironmentSnapshot(osVersion: "15.1")
        environment.hiddenFields = ["Locale"]
        environment.renamedFields = ["Device": "Model"]
        let decoded = try JSONDecoder().decode(EnvironmentSnapshot.self, from: JSONEncoder().encode(environment))
        XCTAssertEqual(decoded.hiddenFields, ["Locale"])
        XCTAssertEqual(decoded.renamedFields, ["Device": "Model"])
    }

    func testOldCapturesWithoutExtrasStillDecode() throws {
        let json = #"{"osVersion":"15","osBuild":"","deviceModel":"","display":"","appName":"","appVersion":"","appBundleId":"","url":"","locale":"","timeZone":"","appearance":"","capturedAt":0}"#
        let snapshot = try JSONDecoder().decode(EnvironmentSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.extras)
        XCTAssertNil(snapshot.hiddenFields)
        XCTAssertTrue(snapshot.shows(.locale))
        XCTAssertEqual(snapshot.name(of: .device), "Device")
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

    func testCrashClipsHaveTheirOwnTime() {
        var oldCrash = item(10, 5)
        oldCrash.isCrashClip = true
        var freshCrash = item(2, 5)
        freshCrash.isCrashClip = true
        var openCrash = item(20, 5)
        openCrash.isCrashClip = true
        let oldScreenshot = item(10, 5)
        let doomed = StoragePolicy.itemsToDelete([oldCrash, freshCrash, openCrash, oldScreenshot], now: now, maxAgeDays: 0, maxBytes: 0, protected: [openCrash.id], crashClipMaxAgeDays: 7)
        XCTAssertEqual(doomed, [oldCrash.id])
        // 0 keeps crash clips.
        XCTAssertTrue(StoragePolicy.itemsToDelete([oldCrash], now: now, maxAgeDays: 0, maxBytes: 0, protected: [], crashClipMaxAgeDays: 0).isEmpty)
    }
}
