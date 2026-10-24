import XCTest
@testable import QAHelperCore

final class CrashReportTests: XCTestCase {
    let chromeTabCrash = #"{"app_name":"Google Chrome Helper (Renderer)","timestamp":"2026-10-24 14:13:35.00 +0300","bundleID":"com.google.Chrome.helper.renderer","bug_type":"309","name":"Google Chrome Helper (Renderer)"}"#

    func testParsesCrashHeader() {
        let report = CrashReport.parse(headerLine: chromeTabCrash)
        XCTAssertEqual(report?.appName, "Google Chrome Helper (Renderer)")
        XCTAssertEqual(report?.bundleId, "com.google.Chrome.helper.renderer")
        XCTAssertEqual(report?.date, Date(timeIntervalSince1970: 1_792_840_415))
    }

    func testIgnoresNonCrashes() {
        let hang = #"{"app_name":"Safari","timestamp":"2026-10-24 14:13:35.00 +0300","bug_type":"288"}"#
        XCTAssertNil(CrashReport.parse(headerLine: hang))
        XCTAssertNil(CrashReport.parse(headerLine: "not json"))
    }

    func testHelperBelongsToItsApp() {
        let report = CrashReport.parse(headerLine: chromeTabCrash)!
        XCTAssertTrue(report.belongs(toAppNamed: "Google Chrome", bundleId: "com.google.Chrome"))
        XCTAssertFalse(report.belongs(toAppNamed: "Google", bundleId: "com.google.Drive"))
        XCTAssertFalse(report.belongs(toAppNamed: "Safari", bundleId: "com.apple.Safari"))
    }
}
