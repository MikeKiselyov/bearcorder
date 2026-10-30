import Foundation
import XCTest

/// The app was renamed, and the old name is gone from the repository: no file is named with it and
/// no file says it, in any case. Only git history keeps it.
final class OldNameTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    /// Put together here, so this file does not say it either.
    private let oldName = "bug" + "bear"

    func testNoTrackedFileHasTheOldName() throws {
        let paths = try trackedFiles()
        XCTAssertGreaterThan(paths.count, 100, "git ls-files found the repository")
        var found: [String] = []
        for path in paths {
            if path.lowercased().contains(oldName) {
                found.append("\(path): in the path")
                continue
            }
            guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(path).path) else {
                continue
            }
            let text = String(decoding: data, as: UTF8.self).lowercased()
            if text.contains(oldName) {
                found.append("\(path): in the text")
            }
        }
        XCTAssertEqual(found, [], "files with the old name")
    }

    private func trackedFiles() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "ls-files"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let listing = String(decoding: data, as: UTF8.self)
        var paths: [String] = []
        for line in listing.split(separator: "\n") {
            let path = String(line)
            if path.hasPrefix("docs/superpowers/") {
                continue
            }
            paths.append(path)
        }
        return paths
    }
}
