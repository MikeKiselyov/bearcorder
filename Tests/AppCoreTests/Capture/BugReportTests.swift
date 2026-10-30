import XCTest
@testable import AppCore

final class BugReportTests: XCTestCase {
    func testStepsMergeTypingAndDoubleClicks() {
        let actions = [
            BugReport.Action(kind: .click, time: 1, target: "\"Email\" text field", app: "Safari"),
            BugReport.Action(kind: .key, time: 2, label: "typing…"),
            BugReport.Action(kind: .key, time: 3, label: "typing…"),
            BugReport.Action(kind: .key, time: 4, label: "⌘ Enter"),
            BugReport.Action(kind: .click, time: 5, target: "row", app: "Finder"),
            BugReport.Action(kind: .click, time: 5.3, target: "row", app: "Finder"),
            BugReport.Action(kind: .marker, time: 64),
        ]
        let steps = BugReport.steps(from: actions)
        XCTAssertEqual(steps, [
            "1. Click \"Email\" text field in Safari",
            "2. Type text",
            "3. Press ⌘ Enter",
            "4. Double-click row in Finder",
            "5. ⚑ Bug moment",
        ])
    }

    /// Steps have no times: the seconds into the clip only got in the way of reading them.
    func testStepsHaveNoTimes() {
        let steps = BugReport.steps(from: [BugReport.Action(kind: .click, time: -12.4)])
        XCTAssertEqual(steps, ["1. Click"])
    }

    func testMarkdownSections() {
        let environment = EnvironmentSnapshot(osVersion: "15.1", osBuild: "24B83", display: "2560×1440 @2x", appName: "Chrome", appVersion: "131.0", url: "stage.myapp.com")
        let text = BugReport.markdown(environment: environment, actions: [])
        // The ticket has its own title, and local file paths mean nothing to whoever reads it.
        XCTAssertTrue(text.hasPrefix("## Steps to reproduce\n1. \n"), text)
        XCTAssertFalse(text.contains("Summary"))
        XCTAssertFalse(text.contains("Attachments"))
        XCTAssertTrue(text.contains("## Expected result"))
        XCTAssertTrue(text.contains("## Actual result"))
        XCTAssertTrue(text.contains("- App: Chrome 131.0"))
        XCTAssertTrue(text.contains("- URL: stage.myapp.com"), text)
        // The environment is the last section.
        XCTAssertTrue(text.components(separatedBy: "\n").last?.hasPrefix("- Time: ") ?? false, text)
    }
}
