import CoreGraphics
import XCTest
@testable import AppCore

final class PictureAreaTests: XCTestCase {
    private let size = CGSize(width: 1600, height: 1000)

    func testMarginIsAQuarterOfTheShorterSide() {
        let editing = PictureArea.editing(imageSize: size)
        XCTAssertEqual(editing, CGRect(x: -250, y: -250, width: 2100, height: 1500))
    }

    func testSmallPicturesStillGetRoomToDraw() {
        let editing = PictureArea.editing(imageSize: CGSize(width: 300, height: 100))
        XCTAssertEqual(editing, CGRect(x: -200, y: -200, width: 700, height: 500))
    }

    func testMarksInsideKeepThePictureSize() {
        let marks = [CGRect(x: 10, y: 10, width: 100, height: 50)]
        XCTAssertEqual(PictureArea.grown(imageSize: size, marks: [PictureArea.Mark(rect: marks[0], slack: 0)]), CGRect(origin: .zero, size: size))
    }

    func testPictureGrowsToMarksOutside() {
        let above = CGRect(x: 100, y: -120.4, width: 300, height: 80)
        let right = CGRect(x: 1500, y: 400, width: 200.2, height: 50)
        let grown = PictureArea.grown(imageSize: size, marks: [PictureArea.Mark(rect: above, slack: 0), PictureArea.Mark(rect: right, slack: 0)])
        XCTAssertEqual(grown, CGRect(x: 0, y: -121, width: 1701, height: 1121))
    }

    func testGrowingStopsAtTheMargin() {
        let far = CGRect(x: -5000, y: 200, width: 100, height: 100)
        let grown = PictureArea.grown(imageSize: size, marks: [PictureArea.Mark(rect: far, slack: 0)])
        XCTAssertEqual(grown, CGRect(x: -250, y: 0, width: 1850, height: 1000))
    }

    /// A mark dragged a few pixels past the edge is cut off as before, not given a thin black strip.
    func testSmallOvershootIsCutOff() {
        let overshoot = CGRect(x: -6, y: 100, width: 300, height: 904)
        let note = CGRect(x: 200, y: -80, width: 300, height: 60)
        let grown = PictureArea.grown(imageSize: size, marks: [PictureArea.Mark(rect: overshoot, slack: 10), PictureArea.Mark(rect: note, slack: 10)])
        XCTAssertEqual(grown, CGRect(x: 0, y: -80, width: 1600, height: 1080))
    }

    /// Each mark has its own slack: a thick arrow at the edge adds nothing, a small note just above
    /// the picture is kept whole.
    func testSlackIsPerMark() {
        let thickArrow = CGRect(x: 100, y: -15, width: 40, height: 200)
        let note = CGRect(x: 400, y: -12, width: 200, height: 40)
        let arrowOnly = PictureArea.grown(imageSize: size, marks: [PictureArea.Mark(rect: thickArrow, slack: 21)])
        XCTAssertEqual(arrowOnly, CGRect(origin: .zero, size: size))
        let both = PictureArea.grown(imageSize: size, marks: [PictureArea.Mark(rect: thickArrow, slack: 21), PictureArea.Mark(rect: note, slack: 8)])
        XCTAssertEqual(both, CGRect(x: 0, y: -12, width: 1600, height: 1012))
    }
}
