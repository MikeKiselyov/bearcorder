import AppCore
import CoreGraphics
import XCTest

/// An area recording can cross displays: each display's picture keeps its place in the clip.
final class AreaCompositionTests: XCTestCase {
    /// A Retina laptop on the left, a 1x display on the right whose top sits 200 pt higher.
    let laptop = AreaComposition.Source(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), pixels: CGSize(width: 3024, height: 1964))
    let monitor = AreaComposition.Source(frame: CGRect(x: 1512, y: -18, width: 1920, height: 1200), pixels: CGSize(width: 1920, height: 1200))

    func testAnAreaOnOneDisplayIsACrop() throws {
        let area = CGRect(x: 100, y: 200, width: 640, height: 360)
        let plan = try XCTUnwrap(AreaComposition.plan(area: area, sources: [laptop, monitor]))
        XCTAssertEqual(plan.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(plan.placements.count, 1, "the monitor is not in the area")
        XCTAssertEqual(plan.placements[0].index, 0)
        XCTAssertEqual(plan.placements[0].scale, 1)
        // The laptop's picture moves left by the area's x and up by its distance from the top (982 - 560).
        XCTAssertEqual(plan.placements[0].offset, CGPoint(x: -200, y: -844))
    }

    func testAnAreaAcrossTwoDisplaysKeepsTheirPlaces() throws {
        let area = CGRect(x: 1312, y: 300, width: 400, height: 300)
        let plan = try XCTUnwrap(AreaComposition.plan(area: area, sources: [laptop, monitor]))
        XCTAssertEqual(plan.renderSize, CGSize(width: 800, height: 600), "the sharper display sets the density")
        XCTAssertEqual(plan.placements.map(\.index), [0, 1])
        let left = plan.placements[0]
        let right = plan.placements[1]
        XCTAssertEqual(left.scale, 1)
        XCTAssertEqual(left.offset, CGPoint(x: -2624, y: -764))
        XCTAssertEqual(right.scale, 2, "the 1x display is scaled up to match")
        XCTAssertEqual(right.offset, CGPoint(x: 400, y: -1164))
        // The seam: the laptop's right edge and the monitor's left edge meet at x = 400 in the clip.
        XCTAssertEqual(left.offset.x + laptop.pixels.width * left.scale, 400)
    }

    func testTheClipSizeIsEven() throws {
        let plan = try XCTUnwrap(AreaComposition.plan(area: CGRect(x: 1500.5, y: 10, width: 300.75, height: 101.3), sources: [laptop, monitor]))
        XCTAssertEqual(Int(plan.renderSize.width) % 2, 0)
        XCTAssertEqual(Int(plan.renderSize.height) % 2, 0)
    }

    func testNoDisplayNoClip() {
        XCTAssertNil(AreaComposition.plan(area: CGRect(x: 5000, y: 0, width: 200, height: 200), sources: [laptop, monitor]))
        XCTAssertNil(AreaComposition.plan(area: CGRect(x: 10, y: 10, width: 0.4, height: 200), sources: [laptop]))
    }

    func testClicksLandWhereTheyWereInTheArea() throws {
        let area = CGRect(x: 1312, y: 300, width: 400, height: 300)
        let center = try XCTUnwrap(AreaComposition.normalizedPoint(CGPoint(x: 1512, y: 450), area: area))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
        let nearTop = try XCTUnwrap(AreaComposition.normalizedPoint(CGPoint(x: 1352, y: 570), area: area))
        XCTAssertEqual(nearTop.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(nearTop.y, 0.1, accuracy: 0.0001, "the clip counts from the top")
        XCTAssertNil(AreaComposition.normalizedPoint(CGPoint(x: 1000, y: 450), area: area))
    }

    func testTheMainDisplayIsTheOneMostOfTheAreaIsOn() {
        let frames = [laptop.frame, monitor.frame]
        XCTAssertEqual(AreaComposition.mainDisplay(of: CGRect(x: 1412, y: 300, width: 400, height: 300), frames: frames), 1)
        XCTAssertEqual(AreaComposition.mainDisplay(of: CGRect(x: 1412, y: 300, width: 150, height: 300), frames: frames), 0)
        XCTAssertNil(AreaComposition.mainDisplay(of: CGRect(x: 9000, y: 0, width: 10, height: 10), frames: frames))
    }
}
