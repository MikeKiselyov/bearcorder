import XCTest
@testable import BugbearCore

/// Steps to reproduce with what was typed and which page it happened on.
final class StepsTests: XCTestCase {
    private func texts(_ actions: [BugReport.Action]) -> [String] {
        var result: [String] = []
        for line in BugReport.stepLines(from: actions) {
            result.append(line.text)
        }
        return result
    }

    func testTypedTextAndField() {
        let actions = [
            BugReport.Action(kind: .click, time: 1, target: "\"Email\" text field", app: "Chrome"),
            BugReport.Action(kind: .key, time: 3, label: BugReport.typingLabel, target: "\"Email\" text field", text: "john@test.com"),
        ]
        XCTAssertEqual(texts(actions), ["Click \"Email\" text field in Chrome", "Type \"john@test.com\" in \"Email\" text field"])
    }

    func testWithoutTypedTextTheFieldIsStillNamed() {
        let typing = BugReport.Action(kind: .key, time: 3, label: BugReport.typingLabel, target: "\"Search\" text field")
        XCTAssertEqual(texts([typing]), ["Type text in \"Search\" text field"])
        let unknown = BugReport.Action(kind: .key, time: 3, label: BugReport.typingLabel)
        XCTAssertEqual(texts([unknown]), ["Type text"])
    }

    func testTypingInOneFieldIsOneStepWithTheNewestText() {
        let actions = [
            BugReport.Action(kind: .key, time: 2, label: BugReport.typingLabel, target: "\"Email\" text field", text: "jo"),
            BugReport.Action(kind: .key, time: 4, label: BugReport.typingLabel, target: "\"Email\" text field", text: "john@test.com"),
            BugReport.Action(kind: .key, time: 6, label: BugReport.typingLabel, target: "\"Name\" text field", text: "John"),
        ]
        XCTAssertEqual(texts(actions), ["Type \"john@test.com\" in \"Email\" text field", "Type \"John\" in \"Name\" text field"])
    }

    func testANewPageAddsAnOpenStep() {
        let actions = [
            BugReport.Action(kind: .click, time: 1, target: "\"Cart\" link", app: "Chrome", url: "https://shop.test/"),
            BugReport.Action(kind: .click, time: 2, target: "\"Checkout\" button", app: "Chrome", url: "https://shop.test/cart"),
            BugReport.Action(kind: .click, time: 3, target: "\"Pay\" button", app: "Chrome", url: "https://shop.test/cart"),
            BugReport.Action(kind: .key, time: 4, label: "⌘ C"),
        ]
        XCTAssertEqual(texts(actions), [
            "Open shop.test",
            "Click \"Cart\" link in Chrome",
            "Open shop.test/cart",
            "Click \"Checkout\" button in Chrome",
            "Click \"Pay\" button in Chrome",
            "Press ⌘ C",
        ])
        let lines = BugReport.stepLines(from: actions)
        XCTAssertEqual(lines[2].time, 2)
    }

    func testLongOrMultilineTextIsShortened() {
        let long = String(repeating: "a", count: 200)
        let action = BugReport.Action(kind: .key, time: 1, label: BugReport.typingLabel, text: "line one\nline two")
        XCTAssertEqual(texts([action]), ["Type \"line one line two\""])
        let cut = BugReport.shortText(long)
        XCTAssertEqual(cut.count, BugReport.maxTextLength)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertEqual(BugReport.pageName("http://localhost:3000/a/"), "localhost:3000/a")
    }

    /// "Type text, Press Space, Type text, Press Space" for one field was four steps.
    func testSpaceAndDeleteWhileTypingStayInOneStep() {
        let field = "\"Address and search bar\" text field"
        let actions = [
            BugReport.Action(kind: .key, time: 1, label: BugReport.typingLabel, target: field, text: "pork"),
            BugReport.Action(kind: .key, time: 2, label: "Space"),
            BugReport.Action(kind: .key, time: 3, label: BugReport.typingLabel, target: field, text: "pork bun"),
            BugReport.Action(kind: .key, time: 4, label: "Delete"),
            BugReport.Action(kind: .key, time: 5, label: BugReport.typingLabel, target: field, text: "porkbun.com"),
            BugReport.Action(kind: .key, time: 6, label: "Enter"),
        ]
        XCTAssertEqual(texts(actions), ["Type \"porkbun.com\" in \"Address and search bar\" text field", "Press Enter"])
    }

    /// Delete on its own, after ⌘A, is still a step.
    func testDeleteOutsideTypingIsAStep() {
        let actions = [
            BugReport.Action(kind: .key, time: 1, label: "⌘ A"),
            BugReport.Action(kind: .key, time: 2, label: "Delete"),
        ]
        XCTAssertEqual(texts(actions), ["Press ⌘ A", "Press Delete"])
    }

    func testReportsCarryTheNewSteps() {
        let actions = [
            BugReport.Action(kind: .key, time: 3, label: BugReport.typingLabel, target: "\"Email\" text field", text: "a*b", url: "https://x.test/login"),
        ]
        let markdown = BugReport.report(environment: EnvironmentSnapshot(), actions: actions, format: .markdown)
        XCTAssertTrue(markdown.contains("1. Open x.test/login"), markdown)
        XCTAssertTrue(markdown.contains("2. Type \"a*b\" in \"Email\" text field"), markdown)
        let jira = BugReport.report(environment: EnvironmentSnapshot(), actions: actions, format: .jira)
        // Jira would turn * into bold.
        XCTAssertTrue(jira.contains("a\\*b"), jira)
    }

    // A query can hold a token or an email, and changes on the same page.
    func testPageStepsLeaveOutTheQuery() {
        XCTAssertEqual(BugReport.pageName("https://shop.test/reset?token=abc123#top"), "shop.test/reset")
        let actions = [
            BugReport.Action(kind: .click, time: 1, target: "\"A\" link", url: "https://shop.test/search?q=a"),
            BugReport.Action(kind: .click, time: 2, target: "\"B\" link", url: "https://shop.test/search?q=b"),
        ]
        XCTAssertEqual(texts(actions), ["Open shop.test/search", "Click \"A\" link", "Click \"B\" link"])
    }

    // Typed text is escaped for Jira, but the environment URL stays a working link.
    func testJiraKeepsEnvironmentLinks() {
        var environment = EnvironmentSnapshot()
        environment.url = "https://shop.test/a_b+c~d"
        let jira = BugReport.report(environment: environment, actions: [], format: .jira)
        XCTAssertTrue(jira.contains("https://shop.test/a_b+c~d"), jira)
    }
}
