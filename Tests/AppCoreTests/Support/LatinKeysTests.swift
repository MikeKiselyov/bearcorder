import XCTest
@testable import AppCore

final class LatinKeysTests: XCTestCase {
    // A Russian layout types "м" on the V key and "я" on Z: shortcuts must still see v and z.
    func testShortcutsFollowTheKeyNotTheLayout() {
        XCTAssertEqual(LatinKeys.key(forKeyCode: 9, typed: "м"), "v")
        XCTAssertEqual(LatinKeys.key(forKeyCode: 6, typed: "я"), "z")
        XCTAssertEqual(LatinKeys.key(forKeyCode: 8, typed: "с"), "c")
        XCTAssertEqual(LatinKeys.key(forKeyCode: 0, typed: "ф"), "a")
    }

    func testKeysOutsideTheTableKeepWhatWasTyped() {
        XCTAssertEqual(LatinKeys.key(forKeyCode: 36, typed: "\r"), "\r")
        XCTAssertEqual(LatinKeys.key(forKeyCode: 24, typed: "+"), "=")
    }

    func testEveryLetterAndDigitIsThere() {
        var letters = Set<String>()
        for name in LatinKeys.names.values {
            letters.insert(name)
        }
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
            XCTAssertTrue(letters.contains(String(letter)), String(letter))
        }
        XCTAssertEqual(LatinKeys.names.count, Set(LatinKeys.names.values).count)
    }
}
