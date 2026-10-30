import XCTest
@testable import AppCore

final class MenuBarPlacementTests: XCTestCase {
    // A 14" MacBook: the menu bar right of the notch is 848-1512.
    private let right = CGRect(x: 848, y: 949, width: 664, height: 33)

    // Seen on this Mac: the bear at 796 sat under the notch.
    func testBehindTheNotchIsHidden() {
        XCTAssertTrue(MenuBarPlacement.isHidden(itemFrame: CGRect(x: 796, y: 949, width: 36, height: 33), rightArea: right, occlusionVisible: true))
        XCTAssertTrue(MenuBarPlacement.isHidden(itemFrame: CGRect(x: 300, y: 949, width: 36, height: 33), rightArea: right, occlusionVisible: true))
    }

    func testRightOfTheNotchIsVisible() {
        XCTAssertFalse(MenuBarPlacement.isHidden(itemFrame: CGRect(x: 1262, y: 949, width: 36, height: 33), rightArea: right, occlusionVisible: true))
    }

    func testMacOSSayingHiddenWins() {
        XCTAssertTrue(MenuBarPlacement.isHidden(itemFrame: CGRect(x: 1262, y: 949, width: 36, height: 33), rightArea: right, occlusionVisible: false))
    }

    func testWithoutANotchOnlyMacOSDecides() {
        XCTAssertFalse(MenuBarPlacement.isHidden(itemFrame: CGRect(x: 700, y: 1050, width: 36, height: 30), rightArea: nil, occlusionVisible: true))
        XCTAssertFalse(MenuBarPlacement.isHidden(itemFrame: CGRect(x: 700, y: 1050, width: 36, height: 30), rightArea: .zero, occlusionVisible: true))
    }
}
