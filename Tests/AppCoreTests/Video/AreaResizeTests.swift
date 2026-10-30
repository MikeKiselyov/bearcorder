import AppCore
import CoreGraphics
import XCTest

/// The recording area can be resized while recording, and the video editor crops a clip.
final class AreaResizeTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testACornerMovesTwoSides() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        let corner = AreaEdges(maxX: true, maxY: true)
        let resized = AreaResize.resized(area, edges: corner, dx: 50, dy: -20, bounds: screen, minimum: 40)
        XCTAssertEqual(resized, CGRect(x: 100, y: 100, width: 450, height: 280))
    }

    func testAnEdgeMovesOneSide() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        let resized = AreaResize.resized(area, edges: AreaEdges(minX: true), dx: -30, dy: 999, bounds: screen, minimum: 40)
        XCTAssertEqual(resized, CGRect(x: 70, y: 100, width: 430, height: 300))
    }

    func testTheAreaStaysOnTheScreen() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        let resized = AreaResize.resized(area, edges: AreaEdges(minX: true, maxY: true), dx: -500, dy: 900, bounds: screen, minimum: 40)
        XCTAssertEqual(resized, CGRect(x: 0, y: 100, width: 500, height: 700))
    }

    func testTheAreaNeverFlipsOrVanishes() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        let resized = AreaResize.resized(area, edges: AreaEdges(minX: true, minY: true), dx: 900, dy: 900, bounds: screen, minimum: 40)
        XCTAssertEqual(resized, CGRect(x: 460, y: 360, width: 40, height: 40))
    }

    func testMovingStopsAtTheEdge() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(AreaResize.moved(area, dx: 900, dy: -900, bounds: screen), CGRect(x: 600, y: 0, width: 400, height: 300))
    }

    func testDrawingInAnyDirection() {
        let drawn = AreaResize.drawn(from: CGPoint(x: 0.8, y: 0.9), to: CGPoint(x: 0.2, y: 1.4), bounds: VideoCrop.whole)
        XCTAssertEqual(drawn.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(drawn.maxX, 0.8, accuracy: 0.0001)
        XCTAssertEqual(drawn.minY, 0.9, accuracy: 0.0001)
        XCTAssertEqual(drawn.maxY, 1, accuracy: 0.0001)
    }

    func testHandlesSitOnCornersAndEdges() {
        let area = CGRect(x: 10, y: 20, width: 100, height: 50)
        XCTAssertEqual(AreaEdges.handles.count, 8)
        XCTAssertEqual(AreaEdges(minY: true, maxX: true).point(on: area), CGPoint(x: 110, y: 20))
        XCTAssertEqual(AreaEdges(maxY: true).point(on: area), CGPoint(x: 60, y: 70))
    }

    func testAPressTakesHoldOfAHandleTheAreaOrNothing() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(AreaEdges.grabbed(at: CGPoint(x: 503, y: 398), area: area, reach: 8), AreaEdges(maxX: true, maxY: true), "a corner")
        XCTAssertEqual(AreaEdges.grabbed(at: CGPoint(x: 96, y: 250), area: area, reach: 8), AreaEdges(minX: true), "the middle of an edge")
        XCTAssertEqual(AreaEdges.grabbed(at: CGPoint(x: 300, y: 250), area: area, reach: 8), .all, "inside: the whole area")
        XCTAssertNil(AreaEdges.grabbed(at: CGPoint(x: 700, y: 250), area: area, reach: 8), "outside: a new area is drawn")
    }

    func testDraggingInsideMovesWithoutResizing() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(AreaResize.dragged(area, edges: .all, dx: 50, dy: -30, bounds: screen, minimum: 40), CGRect(x: 150, y: 70, width: 400, height: 300))
        XCTAssertEqual(AreaResize.dragged(area, edges: .all, dx: 900, dy: 0, bounds: screen, minimum: 40).size, area.size, "keeps its size at the screen edge")
        XCTAssertEqual(AreaResize.dragged(area, edges: AreaEdges(maxX: true), dx: 50, dy: -30, bounds: screen, minimum: 40), CGRect(x: 100, y: 100, width: 450, height: 300))
    }

    func testThePointerSaysWhatADragDoes() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(AreaCursor.at(CGPoint(x: 300, y: 250), area: area, reach: 8), .move)
        XCTAssertEqual(AreaCursor.at(CGPoint(x: 100, y: 100), area: area, reach: 8), .corner)
        XCTAssertEqual(AreaCursor.at(CGPoint(x: 500, y: 250), area: area, reach: 8), .leftRight)
        XCTAssertEqual(AreaCursor.at(CGPoint(x: 300, y: 400), area: area, reach: 8), .upDown)
        XCTAssertEqual(AreaCursor.at(CGPoint(x: 900, y: 700), area: area, reach: 8), .draw)
    }

    /// A laptop (0...1512 wide, 982 tall) and a shorter monitor to its right (0...700 tall).
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let monitor = CGRect(x: 1512, y: 0, width: 1920, height: 700)

    func testAnAreaCrossesScreens() throws {
        let area = CGRect(x: 1000, y: 100, width: 400, height: 300)
        let moved = try XCTUnwrap(AreaResize.dragged(area, edges: .all, dx: 300, dy: 0, screens: [laptop, monitor], minimum: 40))
        XCTAssertEqual(moved, CGRect(x: 1300, y: 100, width: 400, height: 300), "across the seam")
    }

    func testAnAreaSlidesAlongTheEdgeOfNoScreen() throws {
        // High on the laptop, dragged right and up: right of the laptop at that height is the
        // corner above the shorter monitor, no screen. The area goes up along the laptop's edge.
        let area = CGRect(x: 1000, y: 750, width: 300, height: 200)
        let slid = try XCTUnwrap(AreaResize.dragged(area, edges: .all, dx: 1000, dy: 100, screens: [laptop, monitor], minimum: 40))
        XCTAssertEqual(slid, CGRect(x: 1000, y: 782, width: 300, height: 200), "only the part of the drag that stays on a screen")
        // Entirely into the empty corner: only the part of the move that stays on a screen is taken.
        let corner = CGRect(x: 3000, y: 600, width: 300, height: 90)
        let kept = try XCTUnwrap(AreaResize.dragged(corner, edges: .all, dx: 0, dy: 200, screens: [laptop, monitor], minimum: 40))
        XCTAssertEqual(kept, corner.offsetBy(dx: 0, dy: 0), "nothing on a screen up there: it stays")
        XCTAssertNil(AreaResize.dragged(corner, edges: .all, dx: 0, dy: 0, screens: [], minimum: 40))
    }

    func testTheSizeLabelClearsTheGrip() {
        let grip = CGRect(x: 100, y: 10, width: 56, height: 16)
        let far = CGRect(x: 0, y: 10, width: 60, height: 18)
        XCTAssertEqual(AreaResize.label(far, clearOf: grip, gap: 4), far, "already clear")
        let near = CGRect(x: 80, y: 10, width: 60, height: 18)
        let moved = AreaResize.label(near, clearOf: grip, gap: 4)
        XCTAssertEqual(moved.maxX, 96)
        XCTAssertFalse(moved.intersects(grip))
    }

    func testTheWholeFrameIsNoCrop() {
        XCTAssertNil(VideoCrop.normalized(nil))
        XCTAssertNil(VideoCrop.normalized(VideoCrop.whole))
        XCTAssertNil(VideoCrop.normalized(CGRect(x: 0.001, y: 0, width: 0.999, height: 1)))
        XCTAssertNil(VideoCrop.normalized(CGRect(x: 0.5, y: 0.5, width: 0.01, height: 0.4)), "too thin to show anything")
        let clipped = VideoCrop.normalized(CGRect(x: 0.5, y: -0.2, width: 0.8, height: 0.7)) ?? .zero
        XCTAssertEqual(clipped.minX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(clipped.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(clipped.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(clipped.height, 0.5, accuracy: 0.0001)
    }

    func testMarksStayOnThePicture() {
        let crop = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let onFrame = CGPoint(x: 0.5, y: 0.625)
        let onPicture = VideoCrop.toPicture(onFrame, crop: crop)
        XCTAssertEqual(onPicture.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(onPicture.y, 0.5, accuracy: 0.0001)
        let back = VideoCrop.toFrame(onPicture, crop: crop)
        XCTAssertEqual(back.x, onFrame.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, onFrame.y, accuracy: 0.0001)
        let box = VideoCrop.toPicture(CGRect(x: 0.25, y: 0.5, width: 0.25, height: 0.125), crop: crop)
        XCTAssertEqual(box.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(box.height, 0.5, accuracy: 0.0001)
    }

    func testPixelsAreEvenAndInsideTheFrame() {
        let pixels = VideoCrop.pixelRect(CGRect(x: 0.1, y: 0.333, width: 0.5, height: 0.667), width: 1919, height: 1081)
        XCTAssertEqual(Int(pixels.minX) % 2, 0)
        XCTAssertEqual(Int(pixels.minY) % 2, 0)
        XCTAssertEqual(Int(pixels.width) % 2, 0)
        XCTAssertEqual(Int(pixels.height) % 2, 0)
        XCTAssertLessThanOrEqual(pixels.maxX, 1919)
        XCTAssertLessThanOrEqual(pixels.maxY, 1081)
        XCTAssertEqual(pixels.width, 960, accuracy: 2)
        let tiny = VideoCrop.pixelRect(CGRect(x: 0.999, y: 0.999, width: 0.001, height: 0.001), width: 100, height: 100)
        XCTAssertGreaterThanOrEqual(tiny.width, 2)
        XCTAssertGreaterThanOrEqual(tiny.height, 2)
    }

    func testThePreviewCropIsTheRenderedOne() {
        let aligned = CGRect(x: 0.1, y: 0.333, width: 0.5, height: 0.5).pixelAligned(to: CGSize(width: 1920, height: 1080))
        let pixels = VideoCrop.pixelRect(aligned, width: 1920, height: 1080)
        XCTAssertEqual(aligned.minX * 1920, pixels.minX, accuracy: 0.001)
        XCTAssertEqual(aligned.minY * 1080, pixels.minY, accuracy: 0.001)
        XCTAssertEqual(aligned.width * 1920, pixels.width, accuracy: 0.001)
        XCTAssertEqual(VideoCrop.whole.pixelAligned(to: CGSize(width: 1919, height: 1081)), VideoCrop.whole)
    }
}
