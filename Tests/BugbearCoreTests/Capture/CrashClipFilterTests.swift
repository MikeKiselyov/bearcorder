import XCTest
@testable import BugbearCore

final class CrashClipFilterTests: XCTestCase {
    private let chrome = CrashReport(appName: "Google Chrome Helper (Renderer)", bundleId: "com.google.Chrome.helper.renderer", date: Date())
    private let notes = CrashReport(appName: "Notes", bundleId: "com.apple.Notes", date: Date())

    func testAppUsedRecentlyGetsAClip() {
        var filter = CrashClipFilter(ownName: "Bugbear")
        filter.appActivated(name: "Google Chrome", bundleId: "com.google.Chrome", at: 1000)
        XCTAssertEqual(filter.decide(chrome, frontApp: nil, now: 1100), .clip)
    }

    func testAppNotUsedForTenMinutesIsIgnored() {
        var filter = CrashClipFilter(ownName: "Bugbear")
        filter.appActivated(name: "Google Chrome", bundleId: "com.google.Chrome", at: 1000)
        XCTAssertEqual(filter.decide(chrome, frontApp: nil, now: 1000 + CrashClipFilter.recentSeconds + 1), .notUsedRecently)
        XCTAssertEqual(filter.decide(notes, frontApp: nil, now: 1001), .notUsedRecently)
    }

    func testTheAppInFrontCountsWithoutAnActivation() {
        var filter = CrashClipFilter(ownName: "Bugbear")
        XCTAssertEqual(filter.decide(notes, frontApp: (name: "Notes", bundleId: "com.apple.Notes"), now: 5), .clip)
    }

    func testBugbearItselfNeverGetsAClip() {
        var filter = CrashClipFilter(ownName: "Bugbear")
        let own = CrashReport(appName: "Bugbear", bundleId: "io.github.bugbear.app", date: Date())
        XCTAssertEqual(filter.decide(own, frontApp: (name: "Bugbear", bundleId: "io.github.bugbear.app"), now: 5), .ownApp)
    }

    func testOneClipPerAppInTheRepeatWindow() {
        var filter = CrashClipFilter(ownName: "Bugbear")
        filter.appActivated(name: "Google Chrome", bundleId: "com.google.Chrome", at: 1000)
        XCTAssertEqual(filter.decide(chrome, frontApp: nil, now: 1001), .clip)
        XCTAssertEqual(filter.decide(chrome, frontApp: nil, now: 1002), .repeated)
        XCTAssertEqual(filter.decide(chrome, frontApp: nil, now: 1001 + CrashClipFilter.repeatSeconds), .clip)
        // Another app is not held back by Chrome's window.
        XCTAssertEqual(filter.decide(notes, frontApp: (name: "Notes", bundleId: "com.apple.Notes"), now: 1032), .clip)
    }

    func testOldActivationsAreForgotten() {
        var filter = CrashClipFilter(ownName: "Bugbear")
        filter.appActivated(name: "Notes", bundleId: "com.apple.Notes", at: 0)
        filter.appActivated(name: "Google Chrome", bundleId: "com.google.Chrome", at: 1000)
        filter.appActivated(name: "Google Chrome", bundleId: "com.google.Chrome", at: 1010)
        XCTAssertEqual(filter.recentApps.count, 1)
        XCTAssertEqual(filter.recentApps[0].time, 1010)
    }

    func testAutomationAcceptsAnyAppButStillOncePerWindow() {
        var filter = CrashClipFilter(ownName: "Bugbear")
        filter.acceptsAnyApp = true
        XCTAssertEqual(filter.decide(notes, frontApp: nil, now: 1), .clip)
        XCTAssertEqual(filter.decide(notes, frontApp: nil, now: 2), .repeated)
    }
}
