import XCTest
@testable import BugbearCore

final class ContrastTests: XCTestCase {
    func testKnownRatios() {
        let black = RGBAColor(red: 0, green: 0, blue: 0)
        let white = RGBAColor(red: 1, green: 1, blue: 1)
        XCTAssertEqual(Contrast.ratio(foreground: black, background: white), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.ratio(foreground: white, background: white), 1, accuracy: 0.001)
        // #777777 on white is the classic "just fails AA" grey: 4.48:1.
        let grey = ColorConverter.parse("#777777")!
        XCTAssertEqual(Contrast.ratio(foreground: grey, background: white), 4.48, accuracy: 0.01)
        let verdict = Contrast.verdict(foreground: grey, background: white)
        XCTAssertFalse(verdict.passesAANormal)
        XCTAssertTrue(verdict.passesAALarge)
    }

    func testTransparentTextIsBlended() {
        let halfBlack = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let white = RGBAColor(red: 1, green: 1, blue: 1)
        let ratio = Contrast.ratio(foreground: halfBlack, background: white)
        XCTAssertGreaterThan(ratio, 3.5)
        XCTAssertLessThan(ratio, 4.5)
    }
}
