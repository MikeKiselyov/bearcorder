import Foundation
import XCTest

/// `AppState.bufferState` is read by the menu bar icon. Before Swift 6.2 an observed property tells its
/// observers about every write, also of the value it already has, and people's Macs build the app with
/// their own Swift. So the state is written in one place that compares first (`setBufferState`). A
/// plain write would pass every check here: the Swift on this Mac skips equal values by itself.
final class ObservedWritesTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    func testBufferStateIsWrittenInOnePlace() {
        let folder = root.appendingPathComponent("Sources/App")
        var writes: [String] = []
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension != "swift" { continue }
            // The developer tools set states for pictures and tests; they are not in a release.
            if url.path.contains("/DevTools/") { continue }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for (index, line) in text.components(separatedBy: "\n").enumerated() where line.contains("bufferState = ") {
                writes.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(writes.count, 1, "bufferState is written outside setBufferState: \(writes.sorted())")
        XCTAssertEqual(writes.first?.hasPrefix("AppState+Buffer.swift:"), true, "\(writes)")
    }
}
