import XCTest
@testable import BugbearCore

final class JSONTests: XCTestCase {
    func testPrettyKeepsKeyOrderAndNumberText() throws {
        let input = #"{"b":1,"a":-49.00,"list":[true,null,"x"],"empty":{}}"#
        let value = try JSONParser.parse(input)
        let pretty = JSONPrinter().pretty(value)
        let expected = """
        {
          "b": 1,
          "a": -49.00,
          "list": [
            true,
            null,
            "x"
          ],
          "empty": {}
        }
        """
        XCTAssertEqual(pretty, expected)
    }

    func testSortKeysAndMinify() throws {
        let value = try JSONParser.parse(#"{ "b": 2, "a": { "d": 1, "c": 0 } }"#)
        let printer = JSONPrinter(indent: "  ", sortKeys: true)
        XCTAssertEqual(printer.minified(value), #"{"a":{"c":0,"d":1},"b":2}"#)
    }

    func testInvalidJSONReportsPosition() {
        XCTAssertThrowsError(try JSONParser.parse("{\n  \"a\": ,\n}")) { error in
            let parseError = error as? JSONParseError
            XCTAssertEqual(parseError?.line, 2)
        }
    }

    func testEscapesAndUnicode() throws {
        let value = try JSONParser.parse(#"{"s":"line\n\"q\" é 😀"}"#)
        guard case .object(let pairs) = value, case .string(let text) = pairs[0].value else {
            return XCTFail("expected string")
        }
        XCTAssertEqual(text, "line\n\"q\" é 😀")
        XCTAssertEqual(JSONPrinter().minified(value), #"{"s":"line\n\"q\" é 😀"}"#)
    }

    func testUnescapeNestedJSON() {
        var options = FormatOptions()
        options.unescapeStrings = true
        options.mode = .minify
        let result = Formatters.formatJSON(#"{"body":"{\"id\":7}"}"#, options: options)
        XCTAssertEqual(result.output, #"{"body":{"id":7}}"#)
    }

    func testStats() throws {
        let value = try JSONParser.parse(#"{"a":{"b":1},"c":[{"d":2}]}"#)
        let stats = value.stats()
        XCTAssertEqual(stats.keys, 4)
        XCTAssertEqual(stats.depth, 3)
    }
}

final class FormatterTests: XCTestCase {
    func testXMLPrettyWithTwoSpaces() {
        let result = Formatters.formatXML("<a><b x=\"1\">t</b><c/></a>", options: FormatOptions(), html: false)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.output.contains("\n  <b x=\"1\">t</b>"), result.output)
    }

    func testInvalidXML() {
        let result = Formatters.formatXML("<a><b></a>", options: FormatOptions(), html: false)
        XCTAssertFalse(result.isValid)
    }

    func testYAMLRoundTrip() {
        let result = Formatters.formatYAML("a:   1\nlist: [x, y]", options: FormatOptions())
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.output.contains("list:\n- x\n- y") || result.output.contains("list:\n  - x"), result.output)
    }

    func testSQLFormatting() {
        let input = "select id, name from users u join orders o on o.user_id = u.id where u.active = true and o.total > 10 order by id"
        let result = Formatters.formatSQL(input, options: FormatOptions())
        let expected = """
        SELECT
          id,
          name
        FROM users u
        JOIN orders o
          ON o.user_id = u.id
        WHERE u.active = TRUE
          AND o.total > 10
        ORDER BY id
        """
        XCTAssertEqual(result.output, expected)
    }

    func testSQLMinify() {
        var options = FormatOptions()
        options.mode = .minify
        let result = Formatters.formatSQL("SELECT a,\n  b\nFROM t WHERE x IN (1, 2)", options: options)
        XCTAssertEqual(result.output, "SELECT a, b FROM t WHERE x IN(1, 2)")
    }

    func testGraphQL() {
        let result = Formatters.formatGraphQL("query { user(id: 1) { name friends { id } } }", options: FormatOptions())
        XCTAssertTrue(result.isValid)
        let expected = """
        query {
          user(id: 1) {
            name friends {
              id
            }
          }
        }
        """
        XCTAssertEqual(result.output, expected)
    }
}

final class CodecTests: XCTestCase {
    func testBase64() throws {
        XCTAssertEqual(Base64Codec.encode("hello?>", urlSafe: false), "aGVsbG8/Pg==")
        XCTAssertEqual(Base64Codec.encode("hello?>", urlSafe: true), "aGVsbG8_Pg")
        XCTAssertEqual(try Base64Codec.decode("aGVsbG8_Pg"), "hello?>")
        XCTAssertThrowsError(try Base64Codec.decode("a"))
    }

    func testURL() {
        XCTAssertEqual(URLCodec.encode("a b&c=d/é", componentOnly: true), "a%20b%26c%3Dd%2F%C3%A9")
        XCTAssertEqual(URLCodec.decode("a%20b+c"), "a b c")
        let items = URLCodec.queryItems("https://x.io/p?q=a%20b&flag&n=1#top")
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].value, "a b")
        XCTAssertEqual(items[1].name, "flag")
    }

    func testHTMLEntities() {
        XCTAssertEqual(HTMLEntityCodec.encode("<a href=\"x\">Tom & 'Jerry'</a>", nonASCII: false), "&lt;a href=&quot;x&quot;&gt;Tom &amp; &#39;Jerry&#39;&lt;/a&gt;")
        XCTAssertEqual(HTMLEntityCodec.decode("&lt;b&gt; &#169; &#x20AC; &unknown; &amp;"), "<b> © € &unknown; &")
    }

    func testJWT() throws {
        // {"alg":"HS256","typ":"JWT"} . {"sub":"42","exp":1700000000}
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImV4cCI6MTcwMDAwMDAwMH0.sig"
        let decoded = try JWTDecoder.decode("Bearer " + token, now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(decoded.algorithm, "HS256")
        XCTAssertTrue(decoded.payload.contains("\"sub\": \"42\""))
        XCTAssertEqual(decoded.isExpired, true)
        XCTAssertEqual(decoded.claims.first?.name, "exp")
        XCTAssertTrue(decoded.claims.first?.value.hasPrefix("2023-11-14T22:13:20Z") ?? false)
    }
}

final class TimeTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!

    func testNumericUnits() {
        XCTAssertEqual(TimeConverter.parse("1792839492")?.format, "Unix seconds")
        XCTAssertEqual(TimeConverter.parse("1792839492000")?.format, "Unix milliseconds")
        XCTAssertEqual(TimeConverter.parse("1792839492000000")?.format, "Unix microseconds")
        XCTAssertEqual(TimeConverter.parse("1792839492000000000")?.format, "Unix nanoseconds")
        XCTAssertEqual(TimeConverter.parse("1792839492000")?.date.timeIntervalSince1970, 1792839492)
    }

    func testISOAndRFC() {
        let iso = TimeConverter.parse("2026-10-24T10:58:12Z")
        XCTAssertEqual(iso?.date.timeIntervalSince1970, 1792839492)
        let rfc = TimeConverter.parse("Sat, 24 Oct 2026 10:58:12 +0000")
        XCTAssertEqual(rfc?.format, "RFC 2822")
        XCTAssertEqual(rfc?.date.timeIntervalSince1970, 1792839492)
        let local = TimeConverter.parse("2026-10-24 13:58:12", timeZone: TimeZone(identifier: "Europe/Istanbul")!)
        XCTAssertEqual(local?.date.timeIntervalSince1970, 1792839492)
    }

    func testObjectIdAndUUID() {
        let objectId = TimeConverter.parse("507f1f77bcf86cd799439011")
        XCTAssertEqual(objectId?.format, "MongoDB ObjectId")
        XCTAssertEqual(objectId?.date.timeIntervalSince1970, 1350508407)

        let v7 = UUIDGenerator.v7(date: Date(timeIntervalSince1970: 1792839492.5))
        let parsed = TimeConverter.parse(v7)
        XCTAssertEqual(parsed?.format, "UUID v7")
        XCTAssertEqual(parsed?.date.timeIntervalSince1970 ?? 0, 1792839492.5, accuracy: 0.001)

        // Known v1 UUID: c232ab00-9414-11ec-b3c8-9f6bdeced846 -> 2022-02-22T19:22:22Z
        let v1 = TimeConverter.parse("c232ab00-9414-11ec-b3c8-9f6bdeced846")
        XCTAssertEqual(v1?.format, "UUID v1")
        XCTAssertEqual(v1?.date.timeIntervalSince1970 ?? 0, 1645557742, accuracy: 0.001)
    }

    func testRelative() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(TimeConverter.parse("in 3 days", now: now)?.date.timeIntervalSince1970, 1_000_000 + 3 * 86400)
        XCTAssertEqual(TimeConverter.parse("2 hours ago", now: now)?.date.timeIntervalSince1970, 1_000_000 - 7200)
        XCTAssertEqual(TimeConverter.parse("-90m", now: now)?.date.timeIntervalSince1970, 1_000_000 - 5400)
        XCTAssertEqual(TimeConverter.relativeString(from: now, to: now.addingTimeInterval(3 * 86400)), "in 3 days")
        XCTAssertEqual(TimeConverter.relativeString(from: now, to: now.addingTimeInterval(-3600)), "1 hour ago")
    }

    func testRepresentations() {
        let date = Date(timeIntervalSince1970: 1792839492)
        let list = TimeConverter.representations(of: date, now: date, localTimeZone: TimeZone(identifier: "Europe/Istanbul")!)
        XCTAssertEqual(list[0].value, "2026-10-24T10:58:12Z")
        XCTAssertEqual(list[1].value, "2026-10-24T13:58:12+03:00")
        XCTAssertEqual(list[3].value, "1792839492000")
        XCTAssertEqual(list[4].value, "Sat, 24 Oct 2026 10:58:12 +0000")
        XCTAssertEqual(list[6].value, "just now")
    }
}

final class QuickConverterTests: XCTestCase {
    func testNumberBases() {
        let bases = NumberBaseConverter.convert("0xFF")
        XCTAssertEqual(bases?.decimal, "255")
        XCTAssertEqual(bases?.binary, "1111 1111")
        XCTAssertEqual(bases?.octal, "0o377")
        XCTAssertEqual(NumberBaseConverter.convert("0b101")?.decimal, "5")
    }

    func testColors() {
        let color = ColorConverter.parse("#FF6B4A")!
        let formats = ColorConverter.formats(color)
        XCTAssertEqual(formats.rgb, "rgb(255, 107, 74)")
        XCTAssertEqual(formats.hsl, "hsl(11, 100%, 65%)")
        XCTAssertEqual(ColorConverter.formats(ColorConverter.parse("rgb(255, 107, 74)")!).hex, "#FF6B4A")
        XCTAssertEqual(ColorConverter.formats(ColorConverter.parse("hsl(11, 100%, 65%)")!).hex, "#FF6D4D")
        XCTAssertEqual(ColorConverter.formats(ColorConverter.parse("#f00")!).hex, "#FF0000")
    }

    func testCase() {
        let variants = CaseConverter.variants("orderTotalAmount")
        XCTAssertEqual(variants.snake, "order_total_amount")
        XCTAssertEqual(variants.kebab, "order-total-amount")
        XCTAssertEqual(variants.constant, "ORDER_TOTAL_AMOUNT")
        XCTAssertEqual(variants.pascal, "OrderTotalAmount")
        XCTAssertEqual(CaseConverter.variants("HTTPServer error_code").camel, "httpServerErrorCode")
    }

    func testDataSizeAndDuration() {
        XCTAssertEqual(DataSizeConverter.parseBytes("5 MiB"), 5_242_880)
        XCTAssertEqual(DataSizeConverter.describe(5_242_880).binary, "5 MiB")
        XCTAssertEqual(DataSizeConverter.describe(5_242_880).decimal, "5.24 MB")
        XCTAssertEqual(DurationConverter.parseSeconds("PT26H3M4S"), 93784)
        XCTAssertEqual(DurationConverter.parseSeconds("1d 2h 3m 4s"), 93784)
        XCTAssertEqual(DurationConverter.describe(93784).components, "1d 2h 3m 4s")
        XCTAssertEqual(DurationConverter.describe(93784).iso, "PT26H3M4S")
    }

    func testHashes() {
        let hashes = HashGenerator.hashes(of: "abc")
        XCTAssertEqual(hashes[0].value, "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(hashes[2].value, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

final class DataConverterTests: XCTestCase {
    func testJSONToCSVAndBack() throws {
        let json = #"[{"id":"007","user":{"name":"Ann"},"total":5},{"id":"8","user":{"name":"B, Jr"},"total":1.5}]"#
        let csv = try DataConverter.convert(json, from: .json, to: .csv)
        XCTAssertEqual(csv, "id,user.name,total\n007,Ann,5\n8,\"B, Jr\",1.5")
        let back = try DataConverter.read(csv, format: .csv)
        XCTAssertEqual(JSONPrinter().minified(back), #"[{"id":"007","user.name":"Ann","total":5},{"id":8,"user.name":"B, Jr","total":1.5}]"#)
    }

    func testXMLToJSON() throws {
        let xml = "<order id=\"5\"><item>a</item><item>b</item><total>3</total></order>"
        let value = try DataConverter.read(xml, format: .xml)
        XCTAssertEqual(JSONPrinter().minified(value), #"{"order":{"@id":"5","item":["a","b"],"total":"3"}}"#)
        let xmlBack = try DataConverter.write(value, format: .xml)
        XCTAssertTrue(xmlBack.contains("<order id=\"5\">"), xmlBack)
        XCTAssertTrue(xmlBack.contains("<item>b</item>"), xmlBack)
    }

    func testYAMLToJSON() throws {
        let value = try DataConverter.read("name: Ann\ntags:\n  - a\n  - b\nage: 30", format: .yaml)
        XCTAssertEqual(JSONPrinter().minified(value), #"{"age":30,"name":"Ann","tags":["a","b"]}"#)
    }
}

final class DetectorTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(ContentDetector.detect(#"{"a":1}"#), .json)
        XCTAssertEqual(ContentDetector.detect("<root><a/></root>"), .xml)
        XCTAssertEqual(ContentDetector.detect("1792839492"), .time)
        XCTAssertEqual(ContentDetector.detect("2026-10-24T10:58:12Z"), .time)
        XCTAssertEqual(ContentDetector.detect("select * from t"), .sql)
        XCTAssertEqual(ContentDetector.detect("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiJ9.sig"), .jwt)
        XCTAssertEqual(ContentDetector.detect("aGVsbG8gd29ybGQ="), .base64)
        XCTAssertEqual(ContentDetector.detect("a%20b%2Fc"), .url)
        XCTAssertEqual(ContentDetector.detect("#FF6B4A"), .quick)
        XCTAssertNil(ContentDetector.detect("just some words"))
        XCTAssertNil(ContentDetector.detect("42"))
    }
}

final class TimelineTests: XCTestCase {
    func testNoEditsIsIdentity() {
        let timeline = EditTimeline(sourceDuration: 10)
        let pieces = timeline.pieces()
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(timeline.outputDuration, 10)
        XCTAssertFalse(timeline.hasEdits)
    }

    func testTrimCutSpeedFreeze() {
        var timeline = EditTimeline(sourceDuration: 60)
        timeline.trim = TimeSpan(start: 10, end: 50)
        timeline.cuts = [TimeSpan(start: 20, end: 25)]
        timeline.speeds = [SpeedEdit(span: TimeSpan(start: 40, end: 44), factor: 0.5)]
        timeline.freezes = [FreezeEdit(at: 30, duration: 2)]
        // 10..20 (10) + 25..30 (5) + freeze 2 + 30..40 (10) + 40..44 slow (8) + 44..50 (6)
        XCTAssertEqual(timeline.outputDuration, 41, accuracy: 0.0001)
        XCTAssertTrue(timeline.hasEdits)

        let map = TimeMap(pieces: timeline.pieces())
        XCTAssertEqual(map.sourceTime(forOutput: 0), 10, accuracy: 0.0001)
        XCTAssertEqual(map.sourceTime(forOutput: 12), 27, accuracy: 0.0001)
        XCTAssertEqual(map.sourceTime(forOutput: 16), 30, accuracy: 0.0001)
        XCTAssertEqual(map.sourceTime(forOutput: 29), 41, accuracy: 0.0001)
        XCTAssertEqual(map.outputTime(forSource: 41), 29, accuracy: 0.0001)
        XCTAssertEqual(map.outputTime(forSource: 22), 10, accuracy: 0.0001)
        XCTAssertFalse(map.isVisible(source: 22))
        XCTAssertFalse(map.isVisible(source: 5))
        XCTAssertTrue(map.isVisible(source: 45))
    }

    func testFreezeAtEnd() {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.freezes = [FreezeEdit(at: 10, duration: 3)]
        let pieces = timeline.pieces()
        XCTAssertEqual(pieces.count, 2)
        XCTAssertTrue(pieces[1].isFreeze)
        XCTAssertEqual(timeline.outputDuration, 13, accuracy: 0.0001)
    }
}
