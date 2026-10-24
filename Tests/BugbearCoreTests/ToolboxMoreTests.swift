import XCTest
@testable import BugbearCore

final class JSONDiffTests: XCTestCase {
    func testFindsAddedRemovedAndChanged() throws {
        let before = try JSONParser.parse(#"{"id":1,"status":"PAID","total":49.0,"items":[{"sku":"A"},{"sku":"B"}],"note":"x"}"#)
        let after = try JSONParser.parse(#"{"status":"FAILED","id":1,"total":49,"items":[{"sku":"A"}],"error":{"code":"DECLINED"}}"#)
        let changes = JSONDiff.compare(before, after)
        XCTAssertEqual(changes, [
            JSONDiff.Change(path: "$.status", kind: .changed, old: "\"PAID\"", new: "\"FAILED\""),
            JSONDiff.Change(path: "$.items[1]", kind: .removed, old: #"{"sku":"B"}"#, new: nil),
            JSONDiff.Change(path: "$.note", kind: .removed, old: "\"x\"", new: nil),
            JSONDiff.Change(path: "$.error", kind: .added, old: nil, new: #"{"code":"DECLINED"}"#),
        ])
    }

    func testIdenticalDocuments() throws {
        let value = try JSONParser.parse(#"{"a":[1,2,{"b":null}]}"#)
        XCTAssertTrue(JSONDiff.compare(value, value).isEmpty)
    }
}

final class JSONPathTests: XCTestCase {
    let document = try! JSONParser.parse(#"{"store":{"items":[{"name":"Pro","price":49,"tags":["a"]},{"name":"Team","price":99},{"name":"Free","price":0}],"odd key":true}}"#)

    func paths(_ expression: String) throws -> [String] {
        var result: [String] = []
        for match in try JSONPath.query(expression, in: document) {
            result.append(match.path)
        }
        return result
    }

    func testCommonExpressions() throws {
        XCTAssertEqual(try paths("$.store.items[*].price"), ["$.store.items[0].price", "$.store.items[1].price", "$.store.items[2].price"])
        XCTAssertEqual(try paths("$.store.items[-1].name"), ["$.store.items[2].name"])
        XCTAssertEqual(try paths("$.store.items[0:2]"), ["$.store.items[0]", "$.store.items[1]"])
        XCTAssertEqual(try paths("$.store.items[0,2].name"), ["$.store.items[0].name", "$.store.items[2].name"])
        XCTAssertEqual(try paths("$..name").count, 3)
        XCTAssertEqual(try paths("$.store['odd key']"), ["$.store['odd key']"])
        XCTAssertEqual(try JSONPath.query("$.store.items[1].price", in: document).first?.value, .number("99"))
    }

    func testErrors() {
        XCTAssertThrowsError(try JSONPath.query("$.items[?(@.price > 1)]", in: document))
        XCTAssertThrowsError(try JSONPath.query("$.items[", in: document))
    }
}

final class CronTests: XCTestCase {
    var utc: TimeZone { TimeZone(identifier: "UTC")! }

    func testDescriptions() throws {
        XCTAssertEqual(try CronExpression.parse("30 9 * * 1-5").description, "At 09:30, Monday through Friday")
        XCTAssertEqual(try CronExpression.parse("*/15 * * * *").description, "Every 15 minutes")
        XCTAssertEqual(try CronExpression.parse("@daily").description, "At 00:00")
        XCTAssertEqual(try CronExpression.parse("0 12 1 JAN,JUL *").description, "At 12:00, on day 1 of the month, in January, July")
    }

    func testNextRuns() throws {
        // Saturday 2026-10-24 10:58 UTC.
        let now = Date(timeIntervalSince1970: 1_792_839_492)
        let weekdays = try CronExpression.parse("30 9 * * MON-FRI").nextRuns(after: now, count: 2, timeZone: utc)
        XCTAssertEqual(weekdays.count, 2)
        XCTAssertEqual(weekdays[0], Date(timeIntervalSince1970: 1_793_007_000)) // Monday 26 Oct 09:30
        XCTAssertEqual(weekdays[1].timeIntervalSince(weekdays[0]), 24 * 3600)
        let everyFive = try CronExpression.parse("*/5 * * * *").nextRuns(after: now, count: 3, timeZone: utc)
        XCTAssertEqual(everyFive[0], Date(timeIntervalSince1970: 1_792_839_600)) // 11:00
        XCTAssertEqual(everyFive[1].timeIntervalSince(everyFive[0]), 300)
        XCTAssertTrue(try CronExpression.parse("0 0 30 2 *").nextRuns(after: now, count: 1, timeZone: utc).isEmpty)
    }

    func testErrors() {
        XCTAssertThrowsError(try CronExpression.parse("* * *"))
        XCTAssertThrowsError(try CronExpression.parse("61 * * * *"))
        XCTAssertThrowsError(try CronExpression.parse("0 0 * FOO *"))
    }
}

final class HTTPMessageTests: XCTestCase {
    func testRequestWithQueryCookiesAndJSONBody() {
        let raw = "POST /api/orders?debug=1&q=two%20words HTTP/1.1\r\nHost: stage.example.com\r\nCookie: session=abc; theme=dark\r\nContent-Type: application/json\r\n\r\n{\"id\":5}"
        let message = HTTPMessage.parse(raw)
        XCTAssertEqual(message.kind, .request)
        XCTAssertEqual(message.method, "POST")
        XCTAssertEqual(message.path, "/api/orders")
        XCTAssertEqual(message.query, [HTTPMessage.Field(name: "debug", value: "1"), HTTPMessage.Field(name: "q", value: "two words")])
        XCTAssertEqual(message.header("host"), "stage.example.com")
        XCTAssertEqual(message.cookies.count, 2)
        XCTAssertEqual(message.prettyBody, "{\n  \"id\": 5\n}")
    }

    func testResponseWithSetCookieAndForm() {
        let raw = "HTTP/2 302 Found\nSet-Cookie: sid=xyz; Path=/; HttpOnly; Max-Age=3600\nContent-Type: application/x-www-form-urlencoded\n\nname=Anna+Smith&city=Minsk"
        let message = HTTPMessage.parse(raw)
        XCTAssertEqual(message.kind, .response)
        XCTAssertEqual(message.statusCode, 302)
        XCTAssertEqual(message.cookies, [HTTPMessage.Cookie(name: "sid", value: "xyz", attributes: ["Path=/", "HttpOnly", "Max-Age=3600"])])
        XCTAssertEqual(message.formFields.first, HTTPMessage.Field(name: "name", value: "Anna Smith"))
    }

    func testDevtoolsPseudoHeaders() {
        let message = HTTPMessage.parse(":method: GET\n:path: /v1/me?x=2\naccept: */*")
        XCTAssertEqual(message.kind, .request)
        XCTAssertEqual(message.method, "GET")
        XCTAssertEqual(message.path, "/v1/me")
        XCTAssertEqual(message.header("accept"), "*/*")
    }
}

final class LengthStringTests: XCTestCase {
    func testExactLengths() {
        for style in LengthString.Style.allCases {
            for length in [0, 1, 9, 10, 11, 255, 256, 1000] {
                XCTAssertEqual(LengthString.make(length: length, style: style).count, length, "\(style) \(length)")
            }
        }
    }

    func testCounterstringMarksPositions() {
        let text = Array(LengthString.make(length: 35, style: .counter))
        XCTAssertEqual(text.last, "*")
        XCTAssertEqual(String(text[(35 - 3)..<35]), "35*")
        XCTAssertEqual(LengthString.make(length: 11, style: .counter), "2*4*6*8*11*")
    }

    func testCounts() {
        let counts = LengthString.counts("Привет 😀\nok")
        XCTAssertEqual(counts.characters, 11)
        XCTAssertEqual(counts.utf16, 12)
        XCTAssertEqual(counts.utf8Bytes, 20)
        XCTAssertEqual(counts.lines, 2)
        XCTAssertEqual(counts.words, 2)
    }
}

final class DetectorMoreTests: XCTestCase {
    func testDetectsHTTPAndCron() {
        XCTAssertEqual(ContentDetector.detect("GET /api/me?x=1 HTTP/1.1\nHost: a.com"), .http)
        XCTAssertEqual(ContentDetector.detect("HTTP/2 404 Not Found\ncontent-type: text/html"), .http)
        XCTAssertEqual(ContentDetector.detect("*/5 * * * *"), .cron)
        XCTAssertEqual(ContentDetector.detect("0 9 * * 1-5"), .cron)
    }
}
