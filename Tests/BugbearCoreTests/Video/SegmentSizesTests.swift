import BugbearCore
import CoreGraphics
import XCTest

/// A display that goes to native resolution in the middle of an area recording starts a new segment
/// at the new size; the clip scales each part of its picture by that part's own size.
final class SegmentSizesTests: XCTestCase {
    let small = CGSize(width: 1512, height: 982)
    let large = CGSize(width: 3024, height: 1964)

    func testOneSizeIsOneSpan() {
        let segments = [
            SegmentSizes.Segment(start: 0, end: 10, pixels: small),
            SegmentSizes.Segment(start: 10, end: 20, pixels: small),
        ]
        let pieces = [SegmentSizes.Piece(hostStart: 5, hostEnd: 15, outputStart: 0)]
        XCTAssertEqual(SegmentSizes.spans(segments: segments, pieces: pieces), [SegmentSizes.Span(outputStart: 0, pixels: small)])
    }

    func testSizeChangeStartsASpanAtItsClipTime() {
        let segments = [
            SegmentSizes.Segment(start: 0, end: 10, pixels: small),
            SegmentSizes.Segment(start: 10, end: 12.5, pixels: small),
            SegmentSizes.Segment(start: 12.5, end: 20, pixels: large),
        ]
        let pieces = [SegmentSizes.Piece(hostStart: 5, hostEnd: 18, outputStart: 0)]
        XCTAssertEqual(SegmentSizes.spans(segments: segments, pieces: pieces), [
            SegmentSizes.Span(outputStart: 0, pixels: small),
            SegmentSizes.Span(outputStart: 7.5, pixels: large),
        ])
    }

    func testPausesShiftTheClipTime() {
        // A pause from 8 to 14 s is cut out: the second piece starts at 3 s in the clip.
        let segments = [
            SegmentSizes.Segment(start: 0, end: 12, pixels: small),
            SegmentSizes.Segment(start: 12, end: 20, pixels: large),
        ]
        let pieces = [
            SegmentSizes.Piece(hostStart: 5, hostEnd: 8, outputStart: 0),
            SegmentSizes.Piece(hostStart: 14, hostEnd: 18, outputStart: 3),
        ]
        XCTAssertEqual(SegmentSizes.spans(segments: segments, pieces: pieces), [
            SegmentSizes.Span(outputStart: 0, pixels: small),
            SegmentSizes.Span(outputStart: 3, pixels: large),
        ])
    }

    func testSegmentsOutsideTheClipDoNotCount() {
        let segments = [
            SegmentSizes.Segment(start: 0, end: 10, pixels: small),
            SegmentSizes.Segment(start: 10, end: 20, pixels: large),
        ]
        let pieces = [SegmentSizes.Piece(hostStart: 11, hostEnd: 18, outputStart: 0)]
        XCTAssertEqual(SegmentSizes.spans(segments: segments, pieces: pieces), [SegmentSizes.Span(outputStart: 0, pixels: large)])
        XCTAssertEqual(SegmentSizes.largest(SegmentSizes.spans(segments: segments, pieces: pieces)), large)
    }

    func testLargestOfTwo() {
        let spans = [SegmentSizes.Span(outputStart: 0, pixels: small), SegmentSizes.Span(outputStart: 4, pixels: large)]
        XCTAssertEqual(SegmentSizes.largest(spans), large)
        XCTAssertNil(SegmentSizes.largest([]))
    }

    func testPlacementScalesASmallerPartUp() throws {
        let laptop = AreaComposition.Source(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), pixels: large)
        let area = CGRect(x: 100, y: 200, width: 640, height: 360)
        let plan = try XCTUnwrap(AreaComposition.plan(area: area, sources: [laptop]))
        let placement = plan.placements[0]
        XCTAssertEqual(placement.transform(for: large, planned: large), placement.transform)
        let early = placement.transform(for: small, planned: large)
        XCTAssertEqual(early.a, placement.scale * 2, "the half-size part is scaled up twice as much")
        XCTAssertEqual(early.d, placement.scale * 2)
        XCTAssertEqual(early.tx, placement.offset.x, "it lands in the same place")
        XCTAssertEqual(early.ty, placement.offset.y)
        // The same point of the display ends up at the same clip pixel either way.
        let corner = CGPoint(x: 1512, y: 982).applying(early)
        let sameCorner = CGPoint(x: 3024, y: 1964).applying(placement.transform)
        XCTAssertEqual(corner, sameCorner)
    }
}
