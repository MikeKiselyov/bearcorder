import XCTest
@testable import AppCore

final class StoragePolicyLimitsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000_000)

    func makeItem(daysAgo: Double, megabytes: Int64, isCrashClip: Bool = false) -> StoragePolicy.Item {
        let createdAt = now.addingTimeInterval(-daysAgo * 24 * 3600)
        return StoragePolicy.Item(id: UUID(), createdAt: createdAt, bytes: megabytes * 1_000_000, isCrashClip: isCrashClip)
    }

    func testProtectedItemIsKeptWhenTooOldAndOverSize() {
        let protectedItem = makeItem(daysAgo: 400, megabytes: 5000)
        let doomed = StoragePolicy.itemsToDelete([protectedItem], now: now, maxAgeDays: 30, maxBytes: 1_000_000, protected: [protectedItem.id])
        XCTAssertTrue(doomed.isEmpty)
    }

    func testOnlyProtectedItemsLeftOverSizeDeletesNothing() {
        let first = makeItem(daysAgo: 3, megabytes: 500)
        let second = makeItem(daysAgo: 2, megabytes: 500)
        let doomed = StoragePolicy.itemsToDelete([first, second], now: now, maxAgeDays: 0, maxBytes: 100_000_000, protected: [first.id, second.id])
        XCTAssertTrue(doomed.isEmpty)
    }

    func testSizeLimitDeletesOldestFirstAndStopsOnceItFits() {
        let oldest = makeItem(daysAgo: 9, megabytes: 100)
        let middle = makeItem(daysAgo: 5, megabytes: 100)
        let newest = makeItem(daysAgo: 1, megabytes: 100)
        // 300 MB total, limit 250 MB: only the oldest has to go.
        let doomed = StoragePolicy.itemsToDelete([newest, oldest, middle], now: now, maxAgeDays: 0, maxBytes: 250_000_000, protected: [])
        XCTAssertEqual(doomed, [oldest.id])
    }

    func testSizeLimitDeletesSeveralInAgeOrder() {
        let oldest = makeItem(daysAgo: 9, megabytes: 100)
        let middle = makeItem(daysAgo: 5, megabytes: 100)
        let newest = makeItem(daysAgo: 1, megabytes: 100)
        let doomed = StoragePolicy.itemsToDelete([newest, oldest, middle], now: now, maxAgeDays: 0, maxBytes: 150_000_000, protected: [])
        XCTAssertEqual(doomed, [oldest.id, middle.id])
    }

    func testTotalExactlyAtTheLimitDeletesNothing() {
        let first = makeItem(daysAgo: 5, megabytes: 100)
        let second = makeItem(daysAgo: 1, megabytes: 100)
        let doomed = StoragePolicy.itemsToDelete([first, second], now: now, maxAgeDays: 0, maxBytes: 200_000_000, protected: [])
        XCTAssertTrue(doomed.isEmpty)
    }

    func testZeroMaxAgeMeansNoAgeLimit() {
        let ancient = makeItem(daysAgo: 5000, megabytes: 1)
        let doomed = StoragePolicy.itemsToDelete([ancient], now: now, maxAgeDays: 0, maxBytes: 0, protected: [])
        XCTAssertTrue(doomed.isEmpty)
    }

    func testZeroMaxBytesMeansNoSizeLimit() {
        let huge = makeItem(daysAgo: 1, megabytes: 900_000)
        let doomed = StoragePolicy.itemsToDelete([huge], now: now, maxAgeDays: 30, maxBytes: 0, protected: [])
        XCTAssertTrue(doomed.isEmpty)
    }

    func testItemsDeletedByAgeDoNotCountTowardsTheSizeLimit() {
        let tooOld = makeItem(daysAgo: 60, megabytes: 800)
        let older = makeItem(daysAgo: 10, megabytes: 100)
        let newer = makeItem(daysAgo: 2, megabytes: 100)
        // Without the 800 MB item the rest is 200 MB, which fits.
        let doomed = StoragePolicy.itemsToDelete([tooOld, older, newer], now: now, maxAgeDays: 30, maxBytes: 250_000_000, protected: [])
        XCTAssertEqual(doomed, [tooOld.id])
    }

    func testAgeDeletionsComeBeforeSizeDeletions() {
        let tooOld = makeItem(daysAgo: 60, megabytes: 10)
        let oldest = makeItem(daysAgo: 10, megabytes: 100)
        let newest = makeItem(daysAgo: 2, megabytes: 100)
        let doomed = StoragePolicy.itemsToDelete([newest, oldest, tooOld], now: now, maxAgeDays: 30, maxBytes: 150_000_000, protected: [])
        XCTAssertEqual(doomed, [tooOld.id, oldest.id])
    }

    func testItemExactlyAtTheAgeLimitIsKept() {
        let boundary = makeItem(daysAgo: 30, megabytes: 1)
        let doomed = StoragePolicy.itemsToDelete([boundary], now: now, maxAgeDays: 30, maxBytes: 0, protected: [])
        XCTAssertTrue(doomed.isEmpty)
    }

    func testCrashClipUsesItsOwnLimitNotTheGeneralOne() {
        let crashClip = makeItem(daysAgo: 10, megabytes: 5, isCrashClip: true)
        // General limit 30 days keeps it, crash limit 7 days removes it.
        let doomed = StoragePolicy.itemsToDelete([crashClip], now: now, maxAgeDays: 30, maxBytes: 0, protected: [], crashClipMaxAgeDays: 7)
        XCTAssertEqual(doomed, [crashClip.id])
    }

    func testCrashClipIsStillDeletedByTheGeneralAgeLimit() {
        let crashClip = makeItem(daysAgo: 40, megabytes: 5, isCrashClip: true)
        let doomed = StoragePolicy.itemsToDelete([crashClip], now: now, maxAgeDays: 30, maxBytes: 0, protected: [], crashClipMaxAgeDays: 90)
        XCTAssertEqual(doomed, [crashClip.id])
    }

    func testCrashClipLimitDoesNotTouchRegularItems() {
        let regular = makeItem(daysAgo: 10, megabytes: 5)
        let doomed = StoragePolicy.itemsToDelete([regular], now: now, maxAgeDays: 0, maxBytes: 0, protected: [], crashClipMaxAgeDays: 7)
        XCTAssertTrue(doomed.isEmpty)
    }

    func testEmptyListDeletesNothing() {
        let doomed = StoragePolicy.itemsToDelete([], now: now, maxAgeDays: 30, maxBytes: 1, protected: [])
        XCTAssertTrue(doomed.isEmpty)
    }
}
