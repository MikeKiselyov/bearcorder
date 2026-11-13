import XCTest
@testable import AppCore

final class ExportTimeoutTests: XCTestCase {
    func testShortClipGetsTheFloor() {
        XCTAssertEqual(ExportTimeout.seconds(forClip: 0), 300)
        XCTAssertEqual(ExportTimeout.seconds(forClip: 20), 300)
    }

    func testLongClipGetsTenTimesItsLength() {
        XCTAssertEqual(ExportTimeout.seconds(forClip: 180), 1800)
    }

    func testBrokenLengthGetsTheFloor() {
        XCTAssertEqual(ExportTimeout.seconds(forClip: .nan), 300)
        XCTAssertEqual(ExportTimeout.seconds(forClip: -5), 300)
    }
}
