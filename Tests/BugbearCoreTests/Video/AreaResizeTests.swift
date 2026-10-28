import BugbearCore
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
