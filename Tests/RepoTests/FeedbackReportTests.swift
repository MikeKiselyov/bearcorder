import XCTest
@testable import BugbearCore

final class FeedbackReportTests: XCTestCase {
    private func queryValue(_ url: URL, _ name: String) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for item in components?.queryItems ?? [] where item.name == name {
            return item.value
        }
        return nil
    }

    func testRedactHidesHomeAndUserName() {
        let text = "Saved /Users/janedoe/Desktop/Bugbear/a.png for janedoe"
        let redacted = FeedbackReport.redact(text, homePath: "/Users/janedoe", userName: "janedoe")
        XCTAssertEqual(redacted, "Saved ~/Desktop/Bugbear/a.png for <user>")
    }

    func testRedactMatchesWholeNamesOnly() {
        let text = "latest run of test in /Users/test/x and /Users/tester/y, file:///Users/test/a%20b"
        let redacted = FeedbackReport.redact(text, homePath: "/Users/test", userName: "test")
        XCTAssertEqual(redacted, "latest run of <user> in ~/x and /Users/tester/y, file://~/a%20b")
    }

    func testRedactHomeWithSpaceInFileLinks() {
        let text = "file:///Users/Jane%20Doe/Desktop/a.png"
        XCTAssertEqual(FeedbackReport.redact(text, homePath: "/Users/Jane Doe", userName: "jane"), "file://~/Desktop/a.png")
    }

    func testRedactKeepsHyphenatedWordsAndIsSafeTwice() {
        let once = FeedbackReport.redact("self-test by user", homePath: "/Users/user", userName: "user")
        XCTAssertEqual(once, "self-test by <user>")
        XCTAssertEqual(FeedbackReport.redact(once, homePath: "/Users/user", userName: "user"), once)
    }

    func testRedactUsesWholeWordsInAnyScript() {
        let text = "Миша и Мишанька"
        XCTAssertEqual(FeedbackReport.redact(text, homePath: "/Users/misha", userName: "Миша"), "<user> и Мишанька")
    }

    func testRedactLeavesShortNamesAlone() {
        let text = "a cat sat on a mat"
        XCTAssertEqual(FeedbackReport.redact(text, homePath: "/Users/a", userName: "a"), text)
    }

    func testProblemURLFillsTheForm() throws {
        let report = FeedbackReport(
            kind: .problem,
            title: "Clip is black",
            details: "Saved the last minute, the clip is black & silent + short",
            environment: [EnvironmentSnapshot.Field(name: "Bugbear", value: "0.10.0")],
            logLines: ["line one", "line two"]
        )
        let url = try XCTUnwrap(report.issueURL(repository: "owner/repo"))
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/owner/repo/issues/new")
        XCTAssertEqual(queryValue(url, "template"), "bug_report.yml")
        // Labels come from the form file; GitHub ignores the parameter for most people.
        XCTAssertNil(queryValue(url, "labels"))
        XCTAssertEqual(queryValue(url, "title"), "Clip is black")
        // "&" and "+" must survive as text, not split the query or turn into spaces.
        XCTAssertEqual(queryValue(url, "description"), "Saved the last minute, the clip is black & silent + short")
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertEqual(queryValue(url, "environment"), "Bugbear: 0.10.0")
        XCTAssertEqual(queryValue(url, "logs"), "line one\nline two")
    }

    func testIdeaURLUsesTheIdeaForm() throws {
        let report = FeedbackReport(kind: .idea, title: "Dark editor", details: "Let me pick the canvas color", logLines: ["not sent"])
        let url = try XCTUnwrap(report.issueURL(repository: ""))
        XCTAssertEqual(url.path, "/\(FeedbackReport.defaultRepository)/issues/new")
        XCTAssertEqual(queryValue(url, "template"), "feature_request.yml")
        XCTAssertEqual(queryValue(url, "idea"), "Let me pick the canvas color")
        XCTAssertNil(queryValue(url, "logs"))
    }

    func testLongLogKeepsTheNewestLinesUnderTheLimit() throws {
        var lines: [String] = []
        for number in 1...2000 {
            lines.append("2026-10-25 12:00:00.000 INFO  line \(number) with some padding text")
        }
        let report = FeedbackReport(kind: .problem, title: "Slow", details: "It is slow", logLines: lines)
        let url = try XCTUnwrap(report.issueURL(repository: "owner/repo"))
        XCTAssertLessThanOrEqual(url.absoluteString.count, FeedbackReport.maxURLLength)
        let logs = try XCTUnwrap(queryValue(url, "logs"))
        XCTAssertTrue(logs.hasSuffix("line 2000 with some padding text"))
        XCTAssertFalse(logs.contains("line 1 with"))
        XCTAssertEqual(queryValue(url, "description"), "It is slow")
    }

    func testVeryLongDescriptionIsShortened() throws {
        let details = String(repeating: "word ", count: 4000)
        let report = FeedbackReport(kind: .idea, title: "Long", details: details)
        let url = try XCTUnwrap(report.issueURL(repository: "owner/repo"))
        XCTAssertLessThanOrEqual(url.absoluteString.count, FeedbackReport.maxURLLength)
        let idea = try XCTUnwrap(queryValue(url, "idea"))
        XCTAssertTrue(idea.hasSuffix("…"))
    }

    func testSpecialCharactersSurvive() throws {
        let details = "line one\nline #2 has a=b; c?d/e 'f' 100% done"
        let report = FeedbackReport(kind: .problem, title: "a & b", details: details)
        let url = try XCTUnwrap(report.issueURL(repository: "owner/repo"))
        XCTAssertEqual(queryValue(url, "description"), details)
        XCTAssertEqual(queryValue(url, "title"), "a & b")
        XCTAssertNil(url.fragment)
    }

    func testCrashGoesToItsOwnField() throws {
        let report = FeedbackReport(kind: .problem, title: "Crash", crash: "EXC_BAD_ACCESS (SIGSEGV)")
        let url = try XCTUnwrap(report.issueURL())
        XCTAssertEqual(queryValue(url, "crash"), "EXC_BAD_ACCESS (SIGSEGV)")
        XCTAssertNil(queryValue(url, "description"))
    }

    func testLongTitleIsCutAndStillFits() throws {
        let report = FeedbackReport(kind: .problem, title: String(repeating: "t", count: 9000), details: "x")
        let url = try XCTUnwrap(report.issueURL())
        let title = try XCTUnwrap(queryValue(url, "title"))
        XCTAssertLessThanOrEqual(title.count, FeedbackReport.maxTitleLength)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func testLogsGoBeforeTheDescriptionIsCut() throws {
        var lines: [String] = []
        for number in 1...300 {
            lines.append("log line \(number) with padding padding padding")
        }
        let details = String(repeating: "describe ", count: 1500)
        let report = FeedbackReport(kind: .problem, title: "Both long", details: details, logLines: lines)
        let url = try XCTUnwrap(report.issueURL())
        XCTAssertLessThanOrEqual(url.absoluteString.count, FeedbackReport.maxURLLength)
        XCTAssertNil(queryValue(url, "logs"))
        XCTAssertTrue(try XCTUnwrap(queryValue(url, "description")).hasSuffix("…"))
    }

    func testCrashSummaryReadsTheReport() throws {
        let header = "{\"app_name\":\"Bugbear\",\"bug_type\":\"309\"}"
        let body = "{\"exception\":{\"type\":\"EXC_BAD_ACCESS\",\"signal\":\"SIGSEGV\"},\"termination\":{\"indicator\":\"Segmentation fault: 11\"},\"asi\":{\"libswiftCore.dylib\":[\"Fatal error: boom\"]},\"faultingThread\":1,\"usedImages\":[{\"name\":\"Bugbear\"},{\"name\":\"AppKit\"}],\"threads\":[{\"frames\":[{\"imageIndex\":1,\"symbol\":\"idle\"}]},{\"frames\":[{\"imageIndex\":0,\"symbol\":\"Editor.draw()\"},{\"imageIndex\":1,\"symbol\":\"-[NSView display]\"},{\"imageIndex\":7}]}]}"
        let summary = try XCTUnwrap(CrashSummary.parse(reportText: header + "\n" + body))
        XCTAssertEqual(summary.reason, "EXC_BAD_ACCESS (SIGSEGV) - Segmentation fault: 11")
        XCTAssertEqual(summary.message, "Fatal error: boom")
        XCTAssertEqual(summary.frames, ["Bugbear  Editor.draw()", "AppKit  -[NSView display]", "???  ?"])
        XCTAssertTrue(summary.text.contains("Crashed thread:"))
    }

    func testKillsFromOutsideAreNotBugs() throws {
        let killed = "{}\n{\"exception\":{\"type\":\"EXC_BAD_ACCESS\",\"signal\":\"SIGKILL\"},\"termination\":{\"namespace\":\"CODESIGNING\",\"indicator\":\"Invalid Page\"}}"
        XCTAssertTrue(try XCTUnwrap(CrashSummary.parse(reportText: killed)).isExternalKill)
        let crashed = "{}\n{\"exception\":{\"type\":\"EXC_BAD_ACCESS\",\"signal\":\"SIGSEGV\"},\"termination\":{\"namespace\":\"SIGNAL\"}}"
        XCTAssertFalse(try XCTUnwrap(CrashSummary.parse(reportText: crashed)).isExternalKill)
    }

    func testCrashSummaryIgnoresOtherFiles() {
        XCTAssertNil(CrashSummary.parse(reportText: "not a report"))
        XCTAssertNil(CrashSummary.parse(reportText: "{}\n{\"threads\":[]}"))
    }

    func testIssueFormsHaveTheFieldsTheAppFills() throws {
        // The app prefills fields by id; a renamed field in the form would silently stay empty.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for kind in FeedbackReport.Kind.allCases {
            let file = root.appendingPathComponent(".github/ISSUE_TEMPLATE/\(kind.template)")
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(text.contains("\"\(kind.label)\""), "\(kind.template) label")
            let report = FeedbackReport(kind: kind)
            for field in report.formFields(logLineCount: 0) {
                XCTAssertTrue(text.contains("id: \(field.id)\n"), "\(kind.template) has no field \(field.id)")
            }
        }
    }
}
