import XCTest
@testable import AppCore

final class StreamTailTests: XCTestCase {
    private func tail(of chunks: [String], limit: Int) -> (text: String, isCut: Bool) {
        var stream = StreamTail(limit: limit)
        for chunk in chunks {
            stream.append(Data(chunk.utf8))
        }
        return (text: String(decoding: stream.tail(), as: UTF8.self), isCut: stream.isCut)
    }

    func testShortStreamIsKeptWhole() {
        let result = tail(of: ["one\ntw", "o\nthree\n"], limit: 100)
        XCTAssertEqual(result.text, "one\ntwo\nthree\n")
        XCTAssertFalse(result.isCut)
    }

    func testStreamOfExactlyTheLimitIsNotCut() {
        let result = tail(of: ["one\n", "two\n"], limit: 8)
        XCTAssertEqual(result.text, "one\ntwo\n")
        XCTAssertFalse(result.isCut)
    }

    func testLongStreamKeepsWholeLinesFromTheEnd() {
        // The last 10 bytes are "ee\nfour\nfi": the cut line "three" goes.
        let result = tail(of: ["one\ntwo\nth", "ree\nfour\nfi"], limit: 10)
        XCTAssertEqual(result.text, "four\nfi")
        XCTAssertTrue(result.isCut)
    }

    func testCutAtALineStartKeepsThatLine() {
        let result = tail(of: ["one\ntwo\nthree\n"], limit: 10)
        XCTAssertEqual(result.text, "two\nthree\n")
        XCTAssertTrue(result.isCut)
    }

    func testManySmallChunksGiveTheSameTailAsOne() {
        var text = ""
        for number in 0..<5000 {
            text += "line \(number)\n"
        }
        var chunks: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            chunks.append(String(rest.prefix(7)))
            rest = rest.dropFirst(7)
        }
        let whole = tail(of: [text], limit: 300)
        let pieces = tail(of: chunks, limit: 300)
        XCTAssertEqual(pieces.text, whole.text)
        XCTAssertTrue(pieces.text.hasPrefix("line "))
        XCTAssertTrue(pieces.text.hasSuffix("line 4999\n"))
        XCTAssertLessThanOrEqual(pieces.text.utf8.count, 300)
        XCTAssertGreaterThan(pieces.text.utf8.count, 280)
    }

    /// The point of it: a long stream does not pile up in memory.
    func testLongStreamHoldsLittleMoreThanTwiceTheLimit() {
        var stream = StreamTail(limit: 1000)
        let chunk = Data((String(repeating: "x", count: 99) + "\n").utf8)
        var most = 0
        for _ in 0..<1000 {
            stream.append(chunk)
            most = max(most, stream.heldBytes)
        }
        XCTAssertLessThanOrEqual(most, 2000 + chunk.count)
    }

    func testOneLineLongerThanTheLimitKeepsItsEnd() {
        let result = tail(of: ["abcdefghij"], limit: 4)
        XCTAssertEqual(result.text, "ghij")
        XCTAssertTrue(result.isCut)
    }
}
