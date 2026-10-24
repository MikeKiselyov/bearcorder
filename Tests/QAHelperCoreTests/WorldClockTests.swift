import XCTest
@testable import QAHelperCore

final class WorldClockTests: XCTestCase {
    // 2026-10-24 10:58:12 UTC, before the EU and US clock changes.
    let date = Date(timeIntervalSince1970: 1_792_839_492)
    let istanbul = TimeZone(identifier: "Europe/Istanbul")!

    func testSearchByCityAliasAbbreviationAndOffset() {
        XCTAssertEqual(WorldClock.search("tokyo", at: date).first, "Asia/Tokyo")
        XCTAssertEqual(WorldClock.search("India", at: date).first, "Asia/Kolkata")
        XCTAssertEqual(WorldClock.search("san francisco", at: date).first, "America/Los_Angeles")
        XCTAssertTrue(WorldClock.search("new", at: date).contains("America/New_York"))
        XCTAssertTrue(WorldClock.search("+5:30", at: date).contains("Asia/Kolkata"))
        XCTAssertTrue(WorldClock.search("UTC+9", at: date).contains("Asia/Tokyo"))
        XCTAssertFalse(WorldClock.search("UTC+9", at: date).contains("Europe/Berlin"))
        XCTAssertTrue(WorldClock.search("pacific", at: date).contains("America/Los_Angeles"))
    }

    func testOffsetParsing() {
        XCTAssertEqual(WorldClock.parseOffset("+3"), 10800)
        XCTAssertEqual(WorldClock.parseOffset("gmt-8"), -28800)
        XCTAssertEqual(WorldClock.parseOffset("+0530"), 19800)
        XCTAssertNil(WorldClock.parseOffset("+25"))
        XCTAssertNil(WorldClock.parseOffset("tokyo"))
    }

    func testComparisonAgainstReference() {
        let tokyo = WorldClock.compare("Asia/Tokyo", at: date, reference: istanbul)!
        XCTAssertEqual(tokyo.time, "19:58")
        XCTAssertEqual(tokyo.differenceText, "+6h")
        XCTAssertEqual(tokyo.offsetText, "UTC+9")
        XCTAssertEqual(tokyo.dayPart, .evening)

        let newYork = WorldClock.compare("America/New_York", at: date, reference: istanbul)!
        XCTAssertEqual(newYork.time, "06:58")
        XCTAssertEqual(newYork.differenceText, "−7h")
        XCTAssertTrue(newYork.isDaylightSaving)
        XCTAssertEqual(newYork.dayPart, .night)

        let kolkata = WorldClock.compare("Asia/Kolkata", at: date, reference: istanbul)!
        XCTAssertEqual(kolkata.differenceText, "+2h 30m")
        XCTAssertEqual(WorldClock.compare("Europe/Istanbul", at: date, reference: istanbul)?.differenceText, "same time")
    }

    func testHourStripAndSharedHours() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let strip = WorldClock.hourStrip(for: tokyo, on: date, reference: istanbul)
        XCTAssertEqual(strip.count, 24)
        XCTAssertEqual(strip[0], 6)
        XCTAssertEqual(strip[12], 18)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let shared = WorldClock.sharedWorkingHours(zones: [istanbul, berlin], on: date, reference: istanbul)
        // Berlin is one hour behind: both work from 10:00 to 17:59 Istanbul time.
        XCTAssertEqual(shared, [10, 11, 12, 13, 14, 15, 16, 17])
    }
}

final class WorldClockNamingTests: XCTestCase {
    func testModernNames() {
        let date = Date(timeIntervalSince1970: 1_792_839_492)
        XCTAssertEqual(WorldClock.search("kolkata", at: date).first, "Asia/Kolkata")
        XCTAssertFalse(WorldClock.search("+5:30", at: date).contains("Asia/Calcutta"))
        XCTAssertEqual(WorldClock.search("ho chi", at: date).first, "Asia/Ho_Chi_Minh")
    }
}
