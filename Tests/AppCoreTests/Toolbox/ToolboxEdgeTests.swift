import XCTest
@testable import AppCore

/// Branches of the toolbox that the main tests did not reach: unicode escapes, parse errors,
/// the formatter switch, and content detection for every kind.
final class JSONParserEdgeTests: XCTestCase {
    func testUnicodeEscapes() throws {
        XCTAssertEqual(try JSONParser.parse("\"caf\\u00e9\""), .string("café"))
        // A surrogate pair is one character, not two broken halves.
        XCTAssertEqual(try JSONParser.parse("\"\\ud83d\\ude00\""), .string("😀"))
        XCTAssertEqual(try JSONParser.parse("\"\\\"\\\\\\/\\b\\f\\n\\r\\t\""), .string("\"\\/\u{8}\u{c}\n\r\t"))
    }

    func testErrorsSayWhatAndWhere() {
        let broken = [
            "{\"a\" 1}",
            "{1: 2}",
            "{\"a\": 1",
            "{\"a\": 1 \"b\": 2}",
            "[1, 2",
            "[1 2]",
            "\"no end",
            "\"\\q\"",
            "\"\\u12\"",
            "\"\\uZZZZ\"",
            "[1] extra",
            "",
        ]
        for text in broken {
            XCTAssertThrowsError(try JSONParser.parse(text), text)
        }
        do {
            _ = try JSONParser.parse("{\n  \"a\": 1,\n  \"b\" 2\n}")
            XCTFail("should not parse")
        } catch let error as JSONParseError {
            XCTAssertEqual(error.line, 3)
            XCTAssertTrue(error.description.contains("at line 3, column"), error.description)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEquality() throws {
        XCTAssertEqual(try JSONParser.parse("{\"a\": [1, true, null]}"), try JSONParser.parse("{ \"a\" : [ 1 , true , null ] }"))
        XCTAssertNotEqual(try JSONParser.parse("{\"a\": 1}"), try JSONParser.parse("{\"a\": 2}"))
        XCTAssertNotEqual(try JSONParser.parse("{\"a\": 1}"), try JSONParser.parse("{\"a\": 1, \"b\": 2}"))
        XCTAssertNotEqual(try JSONParser.parse("[1, 2]"), try JSONParser.parse("[2, 1]"))
        XCTAssertNotEqual(try JSONParser.parse("1"), try JSONParser.parse("\"1\""))
    }
}

final class FormattersEdgeTests: XCTestCase {
    func testEmptyInputIsNotAnError() {
        for kind in FormatterKind.allCases {
            let result = Formatters.format("  \n ", kind: kind, options: FormatOptions())
            XCTAssertTrue(result.isValid, kind.rawValue)
            XCTAssertEqual(result.output, "", kind.rawValue)
        }
    }

    func testEveryKindFormatsThroughTheSwitch() {
        let samples: [FormatterKind: String] = [
            .json: "{\"b\":1,\"a\":[1,2]}",
            .xml: "<a><b>1</b></a>",
            .html: "<html><body><p>Hi</p></body></html>",
            .yaml: "a: 1\nb: [1, 2]\n",
            .sql: "select a, b from t where a = 1",
            .graphql: "query { user(id: 1) { name } }",
        ]
        for kind in FormatterKind.allCases {
            guard let sample = samples[kind] else {
                XCTFail("no sample for \(kind.rawValue)")
                continue
            }
            let result = Formatters.format(sample, kind: kind, options: FormatOptions())
            XCTAssertTrue(result.isValid, "\(kind.rawValue): \(result.message)")
            // Formatted means laid out on several lines, not the input handed back.
            XCTAssertNotEqual(result.output, sample, kind.rawValue)
            XCTAssertTrue(result.output.contains("\n"), "\(kind.rawValue): \(result.output)")
        }
    }

    func testJSONOptions() {
        var options = FormatOptions()
        options.sortKeys = true
        let sorted = Formatters.format("{\"b\":1,\"a\":2}", kind: .json, options: options).output
        let aIndex = sorted.range(of: "\"a\"")?.lowerBound
        let bIndex = sorted.range(of: "\"b\"")?.lowerBound
        XCTAssertNotNil(aIndex)
        XCTAssertNotNil(bIndex)
        if let aIndex, let bIndex {
            XCTAssertLessThan(aIndex, bIndex)
        }
        options.useTabs = true
        options.sortKeys = false
        XCTAssertTrue(Formatters.format("{\"a\":1}", kind: .json, options: options).output.contains("\n\t\"a\""))
        let invalid = Formatters.format("{\"a\":}", kind: .json, options: FormatOptions())
        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(invalid.message.contains("line 1"), invalid.message)
    }

    func testXMLMinifyAndTabs() {
        var options = FormatOptions()
        options.mode = .minify
        XCTAssertEqual(Formatters.format("<a>\n  <b>1</b>\n</a>", kind: .xml, options: options).output.contains("<a><b>1</b></a>"), true)
        options.mode = .format
        options.useTabs = true
        XCTAssertTrue(Formatters.format("<a><b>1</b></a>", kind: .xml, options: options).output.contains("\n\t<b>1</b>"))
        let invalid = Formatters.format("<a><b></a>", kind: .xml, options: FormatOptions())
        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(invalid.message.hasPrefix("Invalid XML"))
    }

    func testYAMLMinifyAndErrors() {
        var options = FormatOptions()
        options.mode = .minify
        let flow = Formatters.format("a: 1\nb:\n  - x\n", kind: .yaml, options: options)
        XCTAssertTrue(flow.isValid)
        XCTAssertEqual(flow.output, "{\"a\":1,\"b\":[\"x\"]}")
        let invalid = Formatters.format("a: [1, 2\n", kind: .yaml, options: FormatOptions())
        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(invalid.message.hasPrefix("Invalid YAML"))
    }
}

final class ContentDetectorEdgeTests: XCTestCase {
    func testEveryKindIsRecognized() {
        XCTAssertEqual(ContentDetector.detect("<!DOCTYPE html><html><body></body></html>"), .html)
        XCTAssertEqual(ContentDetector.detect("<div>hi</div>"), .html)
        XCTAssertEqual(ContentDetector.detect("<note><to>A</to></note>"), .xml)
        XCTAssertEqual(ContentDetector.detect("query { user { id } }"), .graphql)
        XCTAssertEqual(ContentDetector.detect("mutation AddUser { add { id } }"), .graphql)
        XCTAssertEqual(ContentDetector.detect("Tom &amp; Jerry &lt;3&gt;"), .htmlEntities)
        XCTAssertEqual(ContentDetector.detect("name: Sample\nversion: 1\n"), .yaml)
        XCTAssertEqual(ContentDetector.detect("---\na: 1"), .yaml)
        XCTAssertEqual(ContentDetector.detect("SELECT * FROM users"), .sql)
        XCTAssertEqual(ContentDetector.detect("hello%20world"), .url)
        XCTAssertEqual(ContentDetector.detect("#ff8800"), .quick)
        XCTAssertNil(ContentDetector.detect("just some words"))
        XCTAssertNil(ContentDetector.detect("   "))
    }

    func testBearerTokenIsAJWT() {
        let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln"
        XCTAssertEqual(ContentDetector.detect(token), .jwt)
        XCTAssertEqual(ContentDetector.detect("Bearer " + token), .jwt)
        XCTAssertNotEqual(ContentDetector.detect("eyJhbGciOiJIUzI1NiJ9.notjson.c2ln"), .jwt)
    }

    func testToolsOpenTheirFormatter() {
        XCTAssertEqual(ToolKind.json.formatter, .json)
        XCTAssertEqual(ToolKind.xml.formatter, .xml)
        XCTAssertEqual(ToolKind.yaml.formatter, .yaml)
        XCTAssertEqual(ToolKind.html.formatter, .html)
        XCTAssertEqual(ToolKind.sql.formatter, .sql)
        XCTAssertEqual(ToolKind.graphql.formatter, .graphql)
        XCTAssertNil(ToolKind.jwt.formatter)
        XCTAssertEqual(ToolKind.cron.id, "Cron")
    }
}

final class DataConverterEdgeTests: XCTestCase {
    func testCSVQuotesAndCommas() throws {
        let csv = "name,note\n\"Smith, John\",\"said \"\"hi\"\"\"\n"
        let json = try DataConverter.convert(csv, from: .csv, to: .json)
        let value = try JSONParser.parse(json)
        XCTAssertEqual(value, try JSONParser.parse("[{\"name\": \"Smith, John\", \"note\": \"said \\\"hi\\\"\"}]"))
        // And back: the comma and the quotes survive.
        let back = try DataConverter.convert(json, from: .json, to: .csv)
        XCTAssertTrue(back.contains("\"Smith, John\""), back)
        XCTAssertTrue(back.contains("\"said \"\"hi\"\"\""), back)
    }

    func testCSVErrors() {
        XCTAssertThrowsError(try DataConverter.convert("", from: .csv, to: .json))
        XCTAssertThrowsError(try DataConverter.convert("42", from: .json, to: .csv))
    }

    func testSingleObjectAndWrappedArrayToCSV() throws {
        let single = try DataConverter.convert("{\"a\": 1, \"b\": 2}", from: .json, to: .csv)
        XCTAssertEqual(single.split(separator: "\n"), ["a,b", "1,2"], single)
        let wrapped = try DataConverter.convert("{\"rows\": [{\"a\": 1}, {\"a\": 2}]}", from: .json, to: .csv)
        XCTAssertEqual(wrapped.split(separator: "\n"), ["a", "1", "2"], wrapped)
    }

    func testXMLTextAndArrays() throws {
        let json = try DataConverter.convert("<book id=\"1\">Title</book>", from: .xml, to: .json)
        XCTAssertTrue(json.contains("Title"), json)
        let xml = try DataConverter.convert("{\"list\": [1, 2], \"bad key\": 3, \"1st\": 4}", from: .json, to: .xml)
        // An array repeats its element, as XML usually does.
        XCTAssertTrue(xml.contains("<list>1</list>") && xml.contains("<list>2</list>"), xml)
        let topLevel = try DataConverter.convert("[1, 2]", from: .json, to: .xml)
        XCTAssertTrue(topLevel.contains("<item>1</item>") && topLevel.contains("<item>2</item>"), topLevel)
        XCTAssertTrue(xml.contains("<bad_key>"), xml)
        XCTAssertTrue(xml.contains("<_1st>"), xml)
        XCTAssertThrowsError(try DataConverter.convert("not xml", from: .xml, to: .json))
    }
}
