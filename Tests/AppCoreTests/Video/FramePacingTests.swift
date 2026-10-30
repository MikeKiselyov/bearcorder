import CoreGraphics
import XCTest
@testable import AppCore

final class FramePacingTests: XCTestCase {
    private let menuBar = CGRect(x: 0, y: 0, width: 1662, height: 37)
    private let recordingBar = CGRect(x: 605, y: 0, width: 450, height: 134)

    func testChangeOnlyInTheMenuBarIsQuiet() {
        let dirty = [CGRect(x: 1311, y: 0, width: 36, height: 30)]
        XCTAssertTrue(FramePacing.changedOnlyIn([menuBar, recordingBar], dirty: dirty))
    }

    func testChangeUnderTheRecordingBarIsQuiet() {
        let dirty = [CGRect(x: 615, y: 29, width: 430, height: 98)]
        XCTAssertTrue(FramePacing.changedOnlyIn([menuBar, recordingBar], dirty: dirty))
    }

    func testAnyChangeOutsideCounts() {
        let dirty = [CGRect(x: 1311, y: 0, width: 36, height: 30), CGRect(x: 100, y: 400, width: 200, height: 50)]
        XCTAssertFalse(FramePacing.changedOnlyIn([menuBar, recordingBar], dirty: dirty))
    }

    func testUnknownChangeOrNoZonesCounts() {
        XCTAssertFalse(FramePacing.changedOnlyIn([menuBar], dirty: []))
        XCTAssertFalse(FramePacing.changedOnlyIn([], dirty: [CGRect(x: 0, y: 0, width: 10, height: 10)]))
    }

    func testFractionsOfAPointStayInside() {
        let dirty = [CGRect(x: 994.78, y: 0.28, width: 39.57, height: 37.6)]
        XCTAssertTrue(FramePacing.changedOnlyIn([menuBar], dirty: dirty))
    }

    func testQuietFramesAreKeptAFewTimesASecond() {
        let quiet = [CGRect(x: 1311, y: 0, width: 36, height: 30)]
        var lastKept = 0.0
        var kept = 0
        // 30 frames a second for 2 seconds.
        for index in 1...60 {
            let now = Double(index) / 30
            if FramePacing.shouldKeep(dirty: quiet, quietZones: [menuBar], now: now, lastKept: lastKept) {
                kept += 1
                lastKept = now
            }
        }
        XCTAssertGreaterThanOrEqual(kept, 4)
        XCTAssertLessThanOrEqual(kept, 6)
    }

    func testRealChangesAreAlwaysKept() {
        let real = [CGRect(x: 100, y: 400, width: 200, height: 50)]
        XCTAssertTrue(FramePacing.shouldKeep(dirty: real, quietZones: [menuBar], now: 1.01, lastKept: 1.0))
    }

    func testPartlyOutsideCounts() {
        let dirty = [CGRect(x: 1600, y: 20, width: 100, height: 40)]
        XCTAssertFalse(FramePacing.changedOnlyIn([menuBar], dirty: dirty))
    }

    func testUnknownChangeIsAlwaysKept() {
        XCTAssertTrue(FramePacing.shouldKeep(dirty: [], quietZones: [menuBar], now: 1.01, lastKept: 1.0))
    }

    // MARK: Zones in frame pixels

    func testZonesOnTheMainDisplayScaledByMaxHeight() {
        // A 1512 x 982 pt display captured at 1662 x 1080 px; the bar at the top centre.
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let bar = CGRect(x: 571, y: 880, width: 370, height: 102)
        let zones = FramePacing.zones(displayFrame: display, menuBarHeight: 34, busyWindows: [bar], outputSize: CGSize(width: 1662, height: 1080))
        XCTAssertEqual(zones.count, 2)
        let scale = 1662.0 / 1512.0
        XCTAssertEqual(zones[0].width, 1662, accuracy: 0.5)
        XCTAssertEqual(zones[0].height, 34 * 1080.0 / 982.0, accuracy: 0.5)
        XCTAssertEqual(zones[1].minX, 571 * scale, accuracy: 0.5)
        XCTAssertEqual(zones[1].minY, 0, accuracy: 0.5)
        XCTAssertEqual(zones[1].width, 370 * scale, accuracy: 0.5)
    }

    func testZonesOnASecondDisplayLeftOfTheMain() {
        // Native 2x capture of a display to the left, its top 200 pt above the main one.
        let display = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let bar = CGRect(x: -1200, y: 900, width: 400, height: 80)
        let zones = FramePacing.zones(displayFrame: display, menuBarHeight: 0, busyWindows: [bar], outputSize: CGSize(width: 3840, height: 2160))
        XCTAssertEqual(zones, [CGRect(x: 1440, y: 0, width: 800, height: 160)])
    }

    func testAWindowOnAnotherDisplayGivesNoZone() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let elsewhere = CGRect(x: 2000, y: 100, width: 300, height: 80)
        let zones = FramePacing.zones(displayFrame: display, menuBarHeight: 0, busyWindows: [elsewhere], outputSize: CGSize(width: 1512, height: 982))
        XCTAssertTrue(zones.isEmpty)
    }

    func testAWindowAcrossTwoDisplaysIsCut() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let across = CGRect(x: 900, y: 700, width: 300, height: 100)
        let zones = FramePacing.zones(displayFrame: display, menuBarHeight: 0, busyWindows: [across], outputSize: CGSize(width: 1000, height: 800))
        XCTAssertEqual(zones, [CGRect(x: 900, y: 0, width: 100, height: 100)])
    }

    // MARK: Held frames

    func testTheLastQuietChangeIsWrittenLater() {
        var pacer = FramePacer()
        pacer.zones = [menuBar]
        let quiet = [CGRect(x: 1311, y: 0, width: 36, height: 30)]
        XCTAssertEqual(pacer.receive(dirty: quiet, at: 1.1, lastKept: 1.0), .hold)
        // Not yet due.
        XCTAssertNil(pacer.takeHeld(now: 1.2, lastKept: 1.0, force: false))
        // Then the screen goes still: the held frame comes out once the interval has passed.
        XCTAssertEqual(pacer.takeHeld(now: 1.45, lastKept: 1.0, force: false), 1.1)
        XCTAssertNil(pacer.takeHeld(now: 2.0, lastKept: 1.1, force: false))
    }

    func testSavingTakesTheHeldFrameAtOnce() {
        var pacer = FramePacer()
        pacer.zones = [menuBar]
        _ = pacer.receive(dirty: [CGRect(x: 10, y: 0, width: 20, height: 20)], at: 1.1, lastKept: 1.0)
        XCTAssertEqual(pacer.takeHeld(now: 1.15, lastKept: 1.0, force: true), 1.1)
    }

    func testAKeptFrameDropsTheHeldOne() {
        var pacer = FramePacer()
        pacer.zones = [menuBar]
        _ = pacer.receive(dirty: [CGRect(x: 10, y: 0, width: 20, height: 20)], at: 1.1, lastKept: 1.0)
        XCTAssertEqual(pacer.receive(dirty: [CGRect(x: 100, y: 400, width: 20, height: 20)], at: 1.2, lastKept: 1.0), .encode)
        XCTAssertNil(pacer.heldTime)
        XCTAssertNil(pacer.takeHeld(now: 2.0, lastKept: 1.2, force: true))
    }

    // MARK: Zones together, the bar's own zone, the pointer

    func testAChangeAcrossTheMenuBarAndTheBarIsQuiet() {
        // The bar right under the menu bar; macOS redraws both in one rect.
        let bar = CGRect(x: 627, y: 36, width: 400, height: 70)
        let dirty = [CGRect(x: 640, y: 20, width: 380, height: 80)]
        XCTAssertFalse(FramePacing.changedOnlyIn([bar], dirty: dirty))
        XCTAssertTrue(FramePacing.changedOnlyIn([menuBar, bar], dirty: dirty))
    }

    func testAChangeReachingPastBothZonesCounts() {
        let bar = CGRect(x: 627, y: 36, width: 400, height: 70)
        let dirty = [CGRect(x: 640, y: 20, width: 380, height: 200)]
        XCTAssertFalse(FramePacing.changedOnlyIn([menuBar, bar], dirty: dirty))
    }

    func testTheBarZoneIsTheBarAndItsShadowOnly() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        // Dragged down to the middle: the zone must not run up to the top of the screen.
        let dragged = FramePacing.recordingBarZone(barFrame: CGRect(x: 600, y: 400, width: 380, height: 44), screenFrame: screen)
        XCTAssertEqual(dragged, CGRect(x: 568, y: 368, width: 444, height: 108))
        // Near an edge it stays on its screen.
        let corner = FramePacing.recordingBarZone(barFrame: CGRect(x: 1400, y: 930, width: 380, height: 44), screenFrame: screen)
        XCTAssertEqual(corner.maxX, 1512)
        XCTAssertEqual(corner.maxY, 982)
    }

    func testThePointerInAZoneKeepsEveryFrame() {
        var pacer = FramePacer()
        pacer.zones = [menuBar]
        let quiet = [CGRect(x: 1311, y: 0, width: 36, height: 30)]
        XCTAssertEqual(pacer.receive(dirty: quiet, at: 1.1, lastKept: 1.0, pointer: CGPoint(x: 1320, y: 15)), .encode)
        XCTAssertEqual(pacer.receive(dirty: quiet, at: 1.2, lastKept: 1.1, pointer: CGPoint(x: 700, y: 500)), .hold)
    }

    func testPointerInFramePixels() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let point = FramePacing.pixelPoint(CGPoint(x: 756, y: 982), displayFrame: display, outputSize: CGSize(width: 1662, height: 1080))
        XCTAssertEqual(point?.x ?? -1, 831, accuracy: 0.5)
        XCTAssertEqual(point?.y ?? -1, 0, accuracy: 0.5)
        XCTAssertNil(FramePacing.pixelPoint(CGPoint(x: -10, y: 10), displayFrame: display, outputSize: CGSize(width: 1662, height: 1080)))
    }

    func testResetForgetsTheHeldFrame() {
        var pacer = FramePacer()
        pacer.zones = [menuBar]
        _ = pacer.receive(dirty: [CGRect(x: 10, y: 0, width: 20, height: 20)], at: 1.1, lastKept: 1.0)
        pacer.reset()
        XCTAssertNil(pacer.takeHeld(now: 5, lastKept: 1.0, force: true))
    }
}
