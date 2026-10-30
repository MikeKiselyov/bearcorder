import XCTest
@testable import AppCore

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

    func testPresetScalesDownAndKeepsEvenSizes() {
        let preset = SizeBudget.preset(sourceWidth: 2880, sourceHeight: 1801, maxHeight: 720)
        XCTAssertEqual(preset.height, 720)
        XCTAssertEqual(preset.width % 2, 0)
        XCTAssertEqual(preset.width, 1150)
    }

    func testPresetKeepsSmallerSourceAndClampsBitrate() {
        let small = SizeBudget.preset(sourceWidth: 480, sourceHeight: 270, maxHeight: 1080)
        XCTAssertEqual(small.height, 270)
        XCTAssertEqual(small.videoBitrate, 1_000_000)
        let huge = SizeBudget.preset(sourceWidth: 5120, sourceHeight: 2880, maxHeight: nil)
        XCTAssertEqual(huge.videoBitrate, 25_000_000)
    }

    func testLowerQualityIsSmaller() {
        let full = SizeBudget.preset(sourceWidth: 2880, sourceHeight: 1800, maxHeight: 1080)
        let small = SizeBudget.preset(sourceWidth: 2880, sourceHeight: 1800, maxHeight: 480)
        let fullBytes = SizeBudget.estimatedBytes(videoBitrate: full.videoBitrate, duration: 30, hasAudio: true)
        let smallBytes = SizeBudget.estimatedBytes(videoBitrate: small.videoBitrate, duration: 30, hasAudio: true)
        XCTAssertLessThan(smallBytes, fullBytes)
        XCTAssertEqual(smallBytes, Double(small.videoBitrate + SizeBudget.audioBitrate) * 30 / 8)
    }

    func testExpectedBitrateFollowsTheSource() {
        // A still screen at 0.05 bits per pixel per second needs far less than the preset.
        let still = SizeBudget.expectedVideoBitrate(presetBitrate: 4_000_000, sourceBitsPerPixelSecond: 0.05, width: 1280, height: 720)
        XCTAssertLessThan(still, 200_000)
        // A busy source is capped at the preset target.
        let busy = SizeBudget.expectedVideoBitrate(presetBitrate: 4_000_000, sourceBitsPerPixelSecond: 10, width: 1280, height: 720)
        XCTAssertEqual(busy, 4_000_000)
        // Without a measured source the preset target is the estimate.
        XCTAssertEqual(SizeBudget.expectedVideoBitrate(presetBitrate: 4_000_000, sourceBitsPerPixelSecond: nil, width: 1280, height: 720), 4_000_000)
    }
}
