import AppCore
import XCTest

/// A recording stops by itself before the disk is full: while there is still room to save what was
/// recorded, and 1 GB on top.
final class RecordingDiskSpaceTests: XCTestCase {
    func testPlentyOfRoomKeepsRecording() {
        XCTAssertFalse(RecordingDiskSpace.shouldStop(freeBytes: 50_000_000_000, recordedBytes: 4_000_000_000))
    }

    func testUnderOneGigabyteStops() {
        XCTAssertTrue(RecordingDiskSpace.shouldStop(freeBytes: 999_999_999, recordedBytes: 0))
        XCTAssertFalse(RecordingDiskSpace.shouldStop(freeBytes: 1_000_000_000, recordedBytes: 0))
    }

    func testALongRecordingStopsWhileItsClipStillFits() {
        // 4 GB recorded: saving writes about 4 GB more, so 5 GB free is the least.
        XCTAssertTrue(RecordingDiskSpace.shouldStop(freeBytes: 4_900_000_000, recordedBytes: 4_000_000_000))
        XCTAssertFalse(RecordingDiskSpace.shouldStop(freeBytes: 5_000_000_000, recordedBytes: 4_000_000_000))
    }
}
