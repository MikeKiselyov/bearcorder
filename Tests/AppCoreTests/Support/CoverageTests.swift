import XCTest
@testable import AppCore

/// Functions that other tests only reach indirectly.
final class CoverageTests: XCTestCase {
    func testStepLinesMergeTypingAndDoubleClicks() {
        let actions = [
            BugReport.Action(kind: .click, time: 1, target: "\"Email\" field", app: "Chrome"),
            BugReport.Action(kind: .key, time: 2, label: BugReport.typingLabel),
            BugReport.Action(kind: .key, time: 2.5, label: BugReport.typingLabel),
            BugReport.Action(kind: .click, time: 4, target: "\"Pay\" button", app: "Chrome"),
            BugReport.Action(kind: .click, time: 4.2, target: "\"Pay\" button", app: "Chrome"),
            BugReport.Action(kind: .marker, time: 6),
        ]
        let lines = BugReport.stepLines(from: actions)
        var texts: [String] = []
        for line in lines {
            texts.append(line.text)
        }
        XCTAssertEqual(texts.count, 4)
        XCTAssertEqual(texts[1], "Type text")
        XCTAssertTrue(texts[2].hasPrefix("Double-click"), texts[2])
        XCTAssertEqual(texts[3], "⚑ Bug moment")
        XCTAssertEqual(lines[2].time, 4)
    }

    func testStepLinesSortByTime() {
        let actions = [
            BugReport.Action(kind: .key, time: 5, label: "⌘ Enter"),
            BugReport.Action(kind: .key, time: 1, label: "Tab"),
        ]
        let lines = BugReport.stepLines(from: actions)
        XCTAssertEqual(lines[0].text, "Press Tab")
        XCTAssertEqual(lines[1].text, "Press ⌘ Enter")
    }

    func testBase64DecodeDataAcceptsURLSafeAndMissingPadding() {
        let expected = Data([0xFB, 0xFF, 0xBF])
        XCTAssertEqual(Base64Codec.decodeData("-_-_"), expected)
        XCTAssertEqual(Base64Codec.decodeData("+/+/"), expected)
        XCTAssertEqual(Base64Codec.decodeData("aGk"), Data("hi".utf8))
        XCTAssertEqual(Base64Codec.decodeData(" aGk=\n"), Data("hi".utf8))
        XCTAssertNil(Base64Codec.decodeData("a"))
    }

    func testLuminanceEnds() {
        XCTAssertEqual(Contrast.luminance(RGBAColor(red: 0, green: 0, blue: 0)), 0, accuracy: 0.0001)
        XCTAssertEqual(Contrast.luminance(RGBAColor(red: 1, green: 1, blue: 1)), 1, accuracy: 0.0001)
        let green = Contrast.luminance(RGBAColor(red: 0, green: 1, blue: 0))
        let blue = Contrast.luminance(RGBAColor(red: 0, green: 0, blue: 1))
        XCTAssertGreaterThan(green, blue)
    }

    func testUUIDVersions() {
        let random = UUIDGenerator.v4()
        XCTAssertNotNil(UUID(uuidString: random))
        XCTAssertEqual(Array(random)[14], "4")
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let ordered = UUIDGenerator.v7(date: date)
        XCTAssertNotNil(UUID(uuidString: ordered))
        XCTAssertEqual(Array(ordered)[14], "7")
        // The first 48 bits are the Unix time in milliseconds.
        let hex = ordered.replacingOccurrences(of: "-", with: "").prefix(12)
        XCTAssertEqual(UInt64(hex, radix: 16), 1_700_000_000_123)
        let later = UUIDGenerator.v7(date: date.addingTimeInterval(1))
        XCTAssertLessThan(ordered, later)
    }

    func testJSONQuoteEscapes() {
        XCTAssertEqual(JSONPrinter.quote("a\"b\\c\nd"), #""a\"b\\c\nd""#)
        XCTAssertEqual(JSONPrinter.quote("plain"), "\"plain\"")
    }

    func testHSLRoundTrip() {
        let red = ColorConverter.hslToRGB(hue: 0, saturation: 1, lightness: 0.5)
        XCTAssertEqual(red.red, 1, accuracy: 0.001)
        XCTAssertEqual(red.green, 0, accuracy: 0.001)
        let gray = ColorConverter.rgbToHSL(RGBAColor(red: 0.5, green: 0.5, blue: 0.5))
        XCTAssertEqual(gray.saturation, 0)
        XCTAssertEqual(gray.lightness, 0.5, accuracy: 0.001)
        let samples = [RGBAColor(red: 0.2, green: 0.6, blue: 0.9), RGBAColor(red: 1, green: 0.42, blue: 0.29), RGBAColor(red: 0.1, green: 0.9, blue: 0.3)]
        for color in samples {
            let hsl = ColorConverter.rgbToHSL(color)
            let back = ColorConverter.hslToRGB(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)
            XCTAssertEqual(back.red, color.red, accuracy: 0.001)
            XCTAssertEqual(back.green, color.green, accuracy: 0.001)
            XCTAssertEqual(back.blue, color.blue, accuracy: 0.001)
        }
    }

    func testCardExpiryIsInTheFuture() {
        var generator = SeededGenerator(seed: 7)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let year = Calendar(identifier: .gregorian).component(.year, from: now) % 100
        for _ in 0..<50 {
            let expiry = TestData.cardExpiry(now: now, using: &generator)
            let parts = expiry.split(separator: "/")
            XCTAssertEqual(parts.count, 2)
            let month = Int(parts[0]) ?? 0
            let expiryYear = Int(parts[1]) ?? 0
            XCTAssertTrue((1...12).contains(month), expiry)
            XCTAssertTrue(expiryYear > year && expiryYear <= year + 5, expiry)
        }
    }

    func testISOStringKeepsFractionsOnlyWhenPresent() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(TimeConverter.isoString(Date(timeIntervalSince1970: 0), timeZone: utc), "1970-01-01T00:00:00Z")
        XCTAssertEqual(TimeConverter.isoString(Date(timeIntervalSince1970: 0.25), timeZone: utc), "1970-01-01T00:00:00.250Z")
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        XCTAssertEqual(TimeConverter.isoString(Date(timeIntervalSince1970: 0), timeZone: berlin), "1970-01-01T01:00:00+01:00")
    }

    func testZoneTimeDayHint() {
        // 23:30 UTC is already the next day in Tokyo and the same day in New York.
        // 2023-11-14 23:30:00 UTC.
        let date = Date(timeIntervalSince1970: 1_700_004_600)
        let utc = TimeZone(identifier: "UTC")!
        let tokyo = TimeConverter.zoneTime(date, zone: TimeZone(identifier: "Asia/Tokyo")!, localZone: utc)
        XCTAssertEqual(tokyo.time, "08:30")
        XCTAssertEqual(tokyo.dayHint, "+1 day")
        let newYork = TimeConverter.zoneTime(date, zone: TimeZone(identifier: "America/New_York")!, localZone: utc)
        XCTAssertEqual(newYork.dayHint, "")
        let same = TimeConverter.zoneTime(date, zone: utc, localZone: utc)
        XCTAssertEqual(same.time, "23:30")
    }

    func testRegionOfZone() {
        XCTAssertEqual(WorldClock.region(of: "America/New_York"), "America")
        XCTAssertEqual(WorldClock.region(of: "America/Argentina/Buenos_Aires"), "America")
        XCTAssertEqual(WorldClock.region(of: "UTC"), "")
    }

    func testStationaryRowsAndShift() {
        var page: [[UInt8]?] = []
        for index in 0..<300 {
            page.append(ScrollStitcherTests.profile(index + 1))
        }
        XCTAssertTrue(ScrollStitcher.isStationary(page[3], page[3]))
        XCTAssertFalse(ScrollStitcher.isStationary(page[3], page[90]))
        XCTAssertFalse(ScrollStitcher.isStationary(nil, page[3]))
        let previous = Array(page[0..<120])
        let next = Array(page[40..<160])
        let result = ScrollStitcher.bestShift(previous: previous, next: next)
        XCTAssertEqual(result.shift, 40)
        XCTAssertFalse(ScrollStitcher.diagnose(previous: previous, next: next, shift: 40).isEmpty)
        let still = ScrollStitcher.bestShift(previous: previous, next: previous)
        XCTAssertNil(still.shift)
    }
}
