import XCTest
@testable import BugbearCore

final class SizeBudgetTests: XCTestCase {
    func testBitrateFitsTheLimit() {
        let bitrate = SizeBudget.videoBitrate(limitMB: 10, duration: 60, hasAudio: true)
        let totalBytes = Double(bitrate + SizeBudget.audioBitrate) * 60 / 8
        XCTAssertLessThan(totalBytes, 10_000_000)
        XCTAssertGreaterThan(totalBytes, 8_000_000)
    }

    func testLowBitrateDropsTo720p() {
        let longClip = SizeBudget.videoBitrate(limitMB: 8, duration: 120, hasAudio: false)
        XCTAssertEqual(SizeBudget.maxHeight(forVideoBitrate: longClip), 720)
        let shortClip = SizeBudget.videoBitrate(limitMB: 25, duration: 10, hasAudio: false)
        XCTAssertNil(SizeBudget.maxHeight(forVideoBitrate: shortClip))
    }

    func testTooLongClipIsReported() {
        XCTAssertTrue(SizeBudget.cannotFit(limitMB: 8, duration: 600, hasAudio: true))
        XCTAssertFalse(SizeBudget.cannotFit(limitMB: 8, duration: 60, hasAudio: true))
    }
}
