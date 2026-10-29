import Foundation
import XCTest

/// scripts/lib/permissions.sh: replacing a copy with another bundle id removes that id's permission
/// records, the user's and the system's, so System Settings lists one Bugbear. tccutil and osascript
/// are stand-ins here that only write down how they were called.
final class PermissionsScriptTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func run(_ environment: String, oldId: String = "io.github.bugbear.app") throws -> (calls: String, output: String, folder: String) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("permissions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let calls = folder.appendingPathComponent("calls.txt")
        for tool in ["tccutil", "osascript", "lsregister"] {
            let stub = folder.appendingPathComponent(tool)
            // Each argument on a line of its own after the tool's name, then what came on stdin.
            let body = "#!/bin/bash\n{ echo \"\(tool)\"; printf '  %s\\n' \"$@\"; if [ \"$1\" = - ]; then cat; fi; } >> '\(calls.path)'\n"
            try body.write(to: stub, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        }
        let script = """
        export PATH='\(folder.path)':"$PATH"
        export LSREGISTER='\(folder.path)/lsregister'
        \(environment)
        source '\(root.appendingPathComponent("scripts/lib/permissions.sh").path)'
        forget_permissions '\(oldId)' "/tmp/it's \\"kept\\"/Bug bear.app"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let recorded = (try? String(contentsOf: calls, encoding: .utf8)) ?? ""
        return (recorded, String(decoding: data, as: UTF8.self), folder.path)
    }

    func testTheOldIdLosesItsRecordsEverywhere() throws {
        let result = try run("")
        // The old app is gone by now: its copy is registered around the reset, or tccutil does not know the id.
        let user = "lsregister\n  -f\n  /tmp/it's \"kept\"/Bug bear.app\ntccutil\n  reset\n  All\n  io.github.bugbear.app\nlsregister\n  -u\n  /tmp/it's \"kept\"/Bug bear.app\n"
        XCTAssertTrue(result.calls.hasPrefix(user), "the user's records first: \(result.calls)")
        // A path with a quote, double quotes and a space reaches osascript as one argument, untouched.
        XCTAssertTrue(result.calls.contains("osascript\n  -\n  \(result.folder)/lsregister\n  /tmp/it's \"kept\"/Bug bear.app\n  io.github.bugbear.app\n"), result.calls)
        XCTAssertTrue(result.calls.contains("quoted form of item 2 of arguments"), "AppleScript quotes the path for the shell")
        XCTAssertTrue(result.calls.contains("& \" -f \" & kept & \"; tccutil reset All \" & oldId & \"; \" & lsregister & \" -u \" & kept with administrator privileges"), "register, reset, unregister as root: \(result.calls)")
        XCTAssertTrue(result.output.contains("password"), "says a password dialog is coming: \(result.output)")
    }

    func testKeepingPermissionsSkipsThePasswordDialog() throws {
        let result = try run("export BUGBEAR_KEEP_PERMISSIONS=1")
        XCTAssertFalse(result.calls.contains("osascript"), result.calls)
        XCTAssertTrue(result.calls.contains("tccutil\n  reset\n  All\n  io.github.bugbear.app\n"), result.calls)
    }

    /// The id is read from the old copy's Info.plist: anything but a plain reverse-DNS id never
    /// reaches tccutil or the password dialog.
    func testAnOddIdNeverReachesRoot() throws {
        for oddId in ["-x", "a;b", "a b", "a$(id)", ""] {
            let result = try run("", oldId: oddId)
            XCTAssertEqual(result.calls, "", "\(oddId): \(result.calls)")
            XCTAssertTrue(result.output.contains("skipped"), "\(oddId): \(result.output)")
        }
    }

    /// Only an earlier Bugbear with another id is replaced together with its permissions; another app
    /// that happens to sit at /Applications/Bugbear.app keeps them.
    func testOnlyAnEarlierBugbearLosesItsPermissions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("earlier-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cases: [(id: String, executable: String, expected: String)] = [
            ("io.github.bugbear.app", "Bugbear", "io.github.bugbear.app"),
            ("com.example.other", "Other", ""),
            ("com.mikekiselyov.qahelper", "Bugbear", ""),
        ]
        for (index, item) in cases.enumerated() {
            let contents = folder.appendingPathComponent("\(index)/Bugbear.app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: String] = ["CFBundleIdentifier": item.id, "CFBundleExecutable": item.executable]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            let script = """
            source '\(root.appendingPathComponent("scripts/lib/permissions.sh").path)'
            is_earlier_bugbear '\(contents.deletingLastPathComponent().path)' com.mikekiselyov.qahelper || echo no
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let printed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(printed, item.expected.isEmpty ? "no" : item.expected, "\(item.id) / \(item.executable)")
        }
    }
}
