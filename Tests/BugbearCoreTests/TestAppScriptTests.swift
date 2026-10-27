import Foundation
import XCTest

/// scripts/test-app.sh keeps a copy of the person's settings before a test run and puts all of it
/// back on exit, also when the run is stopped half way. Checked on a scratch settings domain.
final class TestAppScriptTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func bash(_ script: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        var environment = ProcessInfo.processInfo.environment
        environment["ROOT"] = root.path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }

    private func forget(_ domain: String) {
        _ = try? bash("defaults delete \(domain) 2>/dev/null")
        let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences/\(domain).plist")
        try? FileManager.default.removeItem(at: file)
    }

    func testSettingsChangedByATestRunComeBack() throws {
        let domain = "bugbear.selftest.testapp.\(UUID().uuidString)"
        defer { forget(domain) }
        let script = """
        set -e
        source "$ROOT/scripts/test-app.sh"
        defaults write \(domain) outputFolderPath "/Users/someone/Desktop/Bugbear"
        defaults write \(domain) bufferMinutes -int 3
        save_settings \(domain)
        defaults write \(domain) outputFolderPath "/tmp/e2e-features/video-out"
        defaults write \(domain) automationEnabled -bool true
        defaults delete \(domain) bufferMinutes
        restore_settings \(domain)
        echo "folder=$(defaults read \(domain) outputFolderPath)"
        echo "minutes=$(defaults read \(domain) bufferMinutes)"
        echo "automation=$(defaults read \(domain) automationEnabled 2>/dev/null || echo none)"
        """
        let result = try bash(script)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("folder=/Users/someone/Desktop/Bugbear"), "a changed setting is put back: \(result.output)")
        XCTAssertTrue(result.output.contains("minutes=3"), "a deleted setting is put back: \(result.output)")
        XCTAssertTrue(result.output.contains("automation=none"), "a setting the run added goes: \(result.output)")
    }

    func testNoSettingsBeforeMeansNoneAfter() throws {
        let domain = "bugbear.selftest.testapp.\(UUID().uuidString)"
        defer { forget(domain) }
        let script = """
        set -e
        source "$ROOT/scripts/test-app.sh"
        save_settings \(domain)
        defaults write \(domain) automationEnabled -bool true
        restore_settings \(domain)
        defaults read \(domain) 2>/dev/null && echo "still there" || echo "gone"
        """
        let result = try bash(script)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("gone"), result.output)
    }
}
