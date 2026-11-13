import AppCore
import XCTest

final class CreatedFoldersTests: XCTestCase {
    func testFolderIsMadeOncePerPath() throws {
        let folders = CreatedFolders()
        let first = URL(fileURLWithPath: "/tmp/created-folders/first", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/created-folders/second", isDirectory: true)
        var made: [String] = []
        for _ in 0..<3 {
            try folders.ensure(first) { folder in made.append(folder.path) }
        }
        // Another path (the support folder override of a test) is made too.
        try folders.ensure(second) { folder in made.append(folder.path) }
        XCTAssertEqual(made, [first.path, second.path])
    }

    func testFailedFolderIsTriedAgain() throws {
        struct Failure: Error {}
        let folders = CreatedFolders()
        let folder = URL(fileURLWithPath: "/tmp/created-folders/failing", isDirectory: true)
        var tries = 0
        XCTAssertThrowsError(try folders.ensure(folder) { _ in
            tries += 1
            throw Failure()
        })
        try folders.ensure(folder) { _ in tries += 1 }
        try folders.ensure(folder) { _ in tries += 1 }
        XCTAssertEqual(tries, 2)
    }
}
