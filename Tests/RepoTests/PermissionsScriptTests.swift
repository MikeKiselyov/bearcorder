import AppCore
import Foundation
import XCTest

/// scripts/lib/permissions.sh: replacing a copy with another bundle id removes that id's permission
/// records, the user's and the system's, so System Settings lists the app once. tccutil and osascript
/// are stand-ins here that only write down how they were called.
final class PermissionsScriptTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func run(_ environment: String, oldId: String = AppInfo.defaultBundleId) throws -> (calls: String, output: String, folder: String) {
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
        source '\(root.appendingPathComponent("scripts/lib/app-name.sh").path)'
        source '\(root.appendingPathComponent("scripts/lib/permissions.sh").path)'
        forget_permissions '\(oldId)' "/tmp/it's \\"kept\\"/My app.app"
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
        let user = "lsregister\n  -f\n  /tmp/it's \"kept\"/My app.app\ntccutil\n  reset\n  All\n  \(AppInfo.defaultBundleId)\nlsregister\n  -u\n  /tmp/it's \"kept\"/My app.app\n"
        XCTAssertTrue(result.calls.hasPrefix(user), "the user's records first: \(result.calls)")
        // A path with a quote, double quotes and a space reaches osascript as one argument, untouched.
        // Root runs the system's lsregister, never the one LSREGISTER points to.
        let systemLsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        XCTAssertTrue(result.calls.contains("osascript\n  -\n  \(systemLsregister)\n  /tmp/it's \"kept\"/My app.app\n  \(AppInfo.defaultBundleId)\n"), result.calls)
        XCTAssertFalse(result.calls.contains("osascript\n  -\n  \(result.folder)/lsregister\n"), "LSREGISTER never reaches root: \(result.calls)")
        XCTAssertTrue(result.calls.contains("quoted form of item 2 of arguments"), "AppleScript quotes the path for the shell")
        XCTAssertTrue(result.calls.contains("& \" -f \" & kept & \"; tccutil reset All \" & oldId & \"; \" & lsregister & \" -u \" & kept with administrator privileges"), "register, reset, unregister as root: \(result.calls)")
        XCTAssertTrue(result.output.contains("password"), "says a password dialog is coming: \(result.output)")
    }

    /// The agent behind macOS's Screen Recording alert keeps the bundle id it once saw at an app's
    /// path. After a copy with another id sat there, it files the new copy's request under the old id
    /// and the app never shows up in the list. Every install quits it; macOS starts it for the next alert.
    func testTheScreenRecordingAlertForgetsOldIds() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alert-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let calls = folder.appendingPathComponent("calls.txt")
        let stub = folder.appendingPathComponent("killall")
        try "#!/bin/bash\necho \"killall $*\" >> '\(calls.path)'\nexit 1\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let script = """
        set -euo pipefail
        export PATH='\(folder.path)':"$PATH"
        source '\(root.appendingPathComponent("scripts/lib/app-name.sh").path)'
        source '\(root.appendingPathComponent("scripts/lib/permissions.sh").path)'
        forget_cached_app_ids
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "a missing agent does not stop the install")
        let recorded = (try? String(contentsOf: calls, encoding: .utf8)) ?? ""
        XCTAssertEqual(recorded, "killall universalAccessAuthWarn\n")
    }

    /// Every install quits the alert's agent, not only one that replaced a copy with another id: the
    /// old copy may be gone already (uninstalled, then installed). The call is a line of its own at
    /// the level of the install steps, after the new copy is in place and before it opens and asks.
    func testEveryInstallQuitsTheAlertAgent() throws {
        let cases: [(script: String, after: String, call: String, before: String)] = [
            ("scripts/build-app.sh", "                kept_dir=\"\"\n            fi\n", "            forget_cached_app_ids\n", "            if [ -z \"${APP_NO_OPEN:-}\" ]; then\n"),
            // The Update button runs update.sh with the installed app's path.
            ("scripts/update.sh", "    exit 5\nfi\n", "forget_cached_app_ids\n", "open \"$TARGET_APP\"\n"),
        ]
        for item in cases {
            let text = try String(contentsOf: root.appendingPathComponent(item.script), encoding: .utf8)
            XCTAssertTrue(text.contains(item.after + item.call + item.before), "\(item.script): forget_cached_app_ids is not between the install and the open")
        }
    }

    func testKeepingPermissionsSkipsThePasswordDialog() throws {
        let result = try run("export APP_KEEP_PERMISSIONS=1")
        XCTAssertFalse(result.calls.contains("osascript"), result.calls)
        XCTAssertTrue(result.calls.contains("tccutil\n  reset\n  All\n  \(AppInfo.defaultBundleId)\n"), result.calls)
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

    /// Only an earlier copy with another id is replaced together with its permissions; another app
    /// that happens to sit at /Applications/<name>.app keeps them.
    func testOnlyAnEarlierCopyLosesItsPermissions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("earlier-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cases: [(id: String, executable: String, expected: String)] = [
            (AppInfo.defaultBundleId, AppInfo.name, AppInfo.defaultBundleId),
            ("com.example.other", "Other", ""),
            ("com.mikekiselyov.qahelper", AppInfo.name, ""),
        ]
        for (index, item) in cases.enumerated() {
            let contents = folder.appendingPathComponent("\(index)/\(AppInfo.name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: String] = ["CFBundleIdentifier": item.id, "CFBundleExecutable": item.executable]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            let script = """
            source '\(root.appendingPathComponent("scripts/lib/app-name.sh").path)'
            source '\(root.appendingPathComponent("scripts/lib/permissions.sh").path)'
            is_our_earlier_app '\(contents.deletingLastPathComponent().path)' com.mikekiselyov.qahelper || echo no
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
