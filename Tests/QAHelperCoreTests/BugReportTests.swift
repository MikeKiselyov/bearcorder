import XCTest
@testable import QAHelperCore

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
            "1. [00:01] Click \"Email\" text field in Safari",
            "2. [00:02] Type text",
            "3. [00:04] Press ⌘ Enter",
            "4. [00:05] Double-click row in Finder",
            "5. [01:04] ⚑ Bug moment",
        ])
    }

    func testTimesBeforeScreenshot() {
        let steps = BugReport.steps(from: [BugReport.Action(kind: .click, time: -12.4)])
        XCTAssertEqual(steps, ["1. [−00:12] Click"])
    }

    func testMarkdownSections() {
        let environment = EnvironmentSnapshot(osVersion: "15.1", osBuild: "24B83", display: "2560×1440 @2x", appName: "Chrome", appVersion: "131.0", url: "stage.myapp.com")
        let text = BugReport.markdown(environment: environment, actions: [], files: ["/tmp/clip.mp4"])
        XCTAssertTrue(text.contains("## Steps to reproduce\n1. \n"))
        XCTAssertTrue(text.contains("## Expected result"))
        XCTAssertTrue(text.contains("## Actual result"))
        XCTAssertTrue(text.contains("- App: Chrome 131.0"))
        XCTAssertTrue(text.hasSuffix("## Attachments\n- /tmp/clip.mp4"))
    }
}
