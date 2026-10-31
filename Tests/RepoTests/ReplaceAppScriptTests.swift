import AppCore
import Foundation
import XCTest

/// scripts/lib/replace-app.sh: an installed copy is replaced only by a build that is signed and
/// reports the expected version. The old copy waits in a temporary folder outside the Applications
/// folder until the new one is in place, and comes back when anything fails. codesign and cp are
/// stand-ins where a test needs them to fail; everything lives in a folder of the test's own.
final class ReplaceAppScriptTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("replace-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        addTeardownBlock {
            // A read-only folder from a test is made writable again so it can go.
            let apps = folder.appendingPathComponent("apps").path
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: apps)
            try? FileManager.default.removeItem(at: folder)
        }
        return folder
    }

    private func write(_ text: String, to url: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    /// An app whose executable prints `version`, with a file `marker` that tells the copies apart.
    private func makeApp(at url: URL, version: String, marker: String) throws {
        let contents = url.appendingPathComponent("Contents")
        let info: [String: String] = [
            "CFBundleExecutable": AppInfo.name, "CFBundleIdentifier": "test.app", "CFBundleShortVersionString": version,
        ]
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try write("#!/bin/bash\necho \(version)\n", to: contents.appendingPathComponent("MacOS/\(AppInfo.name)"), executable: true)
        try write(marker, to: url.appendingPathComponent(marker))
    }

    /// Runs replace_app with stubs in front of PATH. `codesignFails`: the signature check fails.
    /// `cpFails`: cp leaves half a copy behind and fails. `stubs`: more stand-ins, name to script body.
    /// `before` and `after` run in the same shell around replace_app.
    private func replace(in folder: URL, expected: String, codesignFails: Bool = false, cpFails: Bool = false,
                         stubs extraStubs: [String: String] = [:], before: String = "", after: String = "")
        throws -> (status: Int32, output: String)
    {
        let stubs = folder.appendingPathComponent("stubs")
        let codesignExit = codesignFails ? "echo 'a sealed resource is missing' >&2\nexit 1" : "exit 0"
        try write("#!/bin/bash\n\(codesignExit)\n", to: stubs.appendingPathComponent("codesign"), executable: true)
        if cpFails {
            // The last argument is where the copy goes.
            try write("#!/bin/bash\nmkdir -p \"${@: -1}/Contents\"\necho 'cp: no space left' >&2\nexit 1\n",
                      to: stubs.appendingPathComponent("cp"), executable: true)
        }
        for (name, body) in extraStubs {
            try write("#!/bin/bash\n" + body, to: stubs.appendingPathComponent(name), executable: true)
        }
        let newApp = folder.appendingPathComponent("build/\(AppInfo.name).app").path
        let target = folder.appendingPathComponent("apps/\(AppInfo.name).app").path
        let script = """
        set -euo pipefail
        source '\(root.appendingPathComponent("scripts/lib/app-name.sh").path)'
        source '\(root.appendingPathComponent("scripts/lib/replace-app.sh").path)'
        \(before)
        replace_app "$1" "$2" "$3"
        echo "replace_app done"
        \(after)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "replace-app-test", newApp, target, expected]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = stubs.path + ":" + (environment["PATH"] ?? "")
        environment["HOME"] = folder.appendingPathComponent("home").path
        environment["TMPDIR"] = folder.appendingPathComponent("tmp").path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func setUpApps(in folder: URL, newVersion: String = "1.2.0") throws -> URL {
        try makeApp(at: folder.appendingPathComponent("build/\(AppInfo.name).app"), version: newVersion, marker: "new")
        let target = folder.appendingPathComponent("apps/\(AppInfo.name).app")
        try makeApp(at: target, version: "1.1.0", marker: "old")
        return target
    }

    private func leftovers(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("tmp").path)
    }

    private func appsFolder(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("apps").path).sorted()
    }

    func testABuildThatFailsTheSignatureCheckLeavesTheOldCopy() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        let result = try replace(in: folder, expected: "1.2.0", codesignFails: true)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(result.output.contains("replace_app done"), result.output)
        XCTAssertTrue(result.output.contains("signature"), "the message names the reason: \(result.output)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
        XCTAssertEqual(try appsFolder(folder), ["\(AppInfo.name).app"], "no second copy beside it")
        XCTAssertEqual(try leftovers(in: folder), [])
    }

    func testABuildWithAnotherVersionLeavesTheOldCopy() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder, newVersion: "1.0.0")
        let result = try replace(in: folder, expected: "1.2.0")
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("1.0.0") && result.output.contains("1.2.0"),
                      "the message names both versions: \(result.output)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("new").path), result.output)
        XCTAssertEqual(try leftovers(in: folder), [])
    }

    /// A build without an executable has no version to check.
    func testABuildWithoutItsExecutableLeavesTheOldCopy() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("build/\(AppInfo.name).app/Contents/MacOS"))
        let result = try replace(in: folder, expected: "1.2.0")
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("reports version"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
    }

    /// The copy fails half way: the half copy goes and the old app is back where it was.
    func testAFailedCopyPutsTheOldCopyBack() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        let result = try replace(in: folder, expected: "1.2.0", cpFails: true)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Could not copy"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: target.appendingPathComponent("Contents/MacOS/\(AppInfo.name)").path))
        XCTAssertEqual(try appsFolder(folder), ["\(AppInfo.name).app"])
        XCTAssertEqual(try leftovers(in: folder), [], "nothing left in the temporary folder")
    }

    /// A folder the app cannot be written to: nothing moves, the old copy stays.
    func testAReadOnlyFolderLeavesTheOldCopy() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.appendingPathComponent("apps").path)
        let result = try replace(in: folder, expected: "1.2.0")
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Could not move"), result.output)
        XCTAssertTrue(result.output.contains("stays as it was"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("new").path), result.output)
        XCTAssertEqual(try leftovers(in: folder), [])
    }

    func testAGoodBuildReplacesTheOldCopy() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        let result = try replace(in: folder, expected: "1.2.0")
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("replace_app done"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("new").path), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
        XCTAssertEqual(try appsFolder(folder), ["\(AppInfo.name).app"])
        XCTAssertEqual(try leftovers(in: folder), [], "the old copy is gone from the temporary folder")
    }

    /// The first install: nothing to move away.
    func testAGoodBuildInstallsWhereNothingWas() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        try FileManager.default.removeItem(at: target)
        let result = try replace(in: folder, expected: "1.2.0")
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("new").path), result.output)
        XCTAssertEqual(try leftovers(in: folder), [])
    }

    /// The scripts that install the app replace it only through replace_app.
    func testTheInstallingScriptsReplaceThroughTheHelper() throws {
        for path in ["scripts/update.sh", "scripts/build-app.sh"] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(text.contains("source=lib/replace-app.sh"), "\(path) sources the helper")
            XCTAssertTrue(text.contains("replace_app "), "\(path) calls replace_app")
            XCTAssertFalse(text.contains("rm -rf \"$TARGET_APP\""), "\(path) deletes the app itself")
            XCTAssertFalse(text.contains("rm -rf \"$target_app\""), "\(path) deletes the app itself")
        }
    }

    /// Without an expected version nothing passes, even an app with no executable to ask.
    func testAnEmptyExpectedVersionNeverPasses() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("build/\(AppInfo.name).app/Contents/MacOS"))
        let result = try replace(in: folder, expected: "")
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("No expected version"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
    }

    /// The copy is in place but does not check out (codesign fails only for the installed copy):
    /// it goes and the old copy is back.
    func testACopyThatFailsItsCheckPutsTheOldCopyBack() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        let codesign = "case \"${@: -1}\" in */apps/*) exit 1 ;; esac\nexit 0\n"
        let result = try replace(in: folder, expected: "1.2.0", stubs: ["codesign": codesign])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("old copy is back"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("new").path), result.output)
        XCTAssertEqual(try leftovers(in: folder), [])
    }

    /// A move that fails half way (across volumes mv copies first) may leave the only full copy in the
    /// temporary folder: it is kept and the message says where.
    func testAFailedMoveKeepsWhatItMoved() throws {
        let folder = try makeFolder()
        _ = try setUpApps(in: folder)
        let move = "/bin/cp -R \"$1\" \"$2\"\necho 'mv: rename failed' >&2\nexit 1\n"
        let result = try replace(in: folder, expected: "1.2.0", stubs: ["mv": move])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("kept in"), result.output)
        let kept = try leftovers(in: folder)
        XCTAssertEqual(kept.count, 1, "the temporary folder stays: \(result.output)")
        let keptFolder = try XCTUnwrap(kept.first)
        let copy = folder.appendingPathComponent("tmp/\(keptFolder)/\(AppInfo.name).app/old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path), "what was moved is still there")
    }

    /// Stopped (TERM) while the copy runs: the half copy goes, the old copy is back and the script
    /// stops. The cp stand-in sends TERM to the script; bash runs the trap when cp returns.
    func testAStopWhileCopyingPutsTheOldCopyBack() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        let copy = "kill -TERM \"$PPID\"\nmkdir -p \"${@: -1}/Contents\"\nexit 0\n"
        let result = try replace(in: folder, expected: "1.2.0", stubs: ["cp": copy])
        XCTAssertEqual(result.status, 143, result.output)
        XCTAssertFalse(result.output.contains("replace_app done"), result.output)
        XCTAssertTrue(result.output.contains("Stopped while"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: target.appendingPathComponent("Contents/MacOS/\(AppInfo.name)").path))
        XCTAssertEqual(try appsFolder(folder), ["\(AppInfo.name).app"])
        XCTAssertEqual(try leftovers(in: folder), [])
    }

    /// The caller's own traps are back after replace_app, whichever way it ends.
    func testTheCallersTrapsComeBack() throws {
        // A good copy, and one that fails its check after the copy (the traps were set by then).
        let failsAfterCopy = "case \"${@: -1}\" in */apps/*) exit 1 ;; esac\nexit 0\n"
        for codesignFails in [false, true] {
            let folder = try makeFolder()
            _ = try setUpApps(in: folder)
            let stubs = codesignFails ? ["codesign": failsAfterCopy] : [:]
            let result = try replace(in: folder, expected: "1.2.0", stubs: stubs,
                                     before: "trap 'echo caller-term' TERM\nset +e",
                                     after: "trap -p TERM INT HUP")
            XCTAssertTrue(result.output.contains("trap -- 'echo caller-term' SIGTERM"), "\(codesignFails): \(result.output)")
            XCTAssertFalse(result.output.contains("replace_app_interrupted"), "\(codesignFails): \(result.output)")
        }
    }

    /// A stop while the old copy is moved back after a failed copy: the move back finishes and the
    /// stop does not run the rollback a second time (that would delete the old copy just put back).
    func testAStopWhileMovingBackKeepsTheOldCopy() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        let move = "case \"$2\" in */apps/*) kill -TERM \"$PPID\" ;; esac\nexec /bin/mv \"$@\"\n"
        let result = try replace(in: folder, expected: "1.2.0", cpFails: true, stubs: ["mv": move])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: target.appendingPathComponent("Contents/MacOS/\(AppInfo.name)").path))
        XCTAssertEqual(try leftovers(in: folder), [])
    }

    /// A stop while the old copy moves out of the way: it comes back.
    func testAStopWhileMovingOutPutsTheOldCopyBack() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        let move = "case \"$2\" in */tmp/*) kill -TERM \"$PPID\" ;; esac\nexec /bin/mv \"$@\"\n"
        let result = try replace(in: folder, expected: "1.2.0", stubs: ["mv": move])
        XCTAssertEqual(result.status, 143, result.output)
        XCTAssertTrue(result.output.contains("old copy is back"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("old").path), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("new").path), result.output)
        XCTAssertEqual(try leftovers(in: folder), [])
    }

    /// The half copy cannot be removed: the old copy is never moved inside it, it stays in the
    /// temporary folder and the message says where.
    func testAHalfCopyThatStaysNeverSwallowsTheOldCopy() throws {
        let folder = try makeFolder()
        let target = try setUpApps(in: folder)
        let result = try replace(in: folder, expected: "1.2.0", cpFails: true, stubs: ["rm": "exit 0\n"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("The old copy is in"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("\(AppInfo.name).app").path),
                       "the old copy is not inside the half copy: \(result.output)")
        let kept = try leftovers(in: folder)
        let keptFolder = try XCTUnwrap(kept.first, result.output)
        let old = folder.appendingPathComponent("tmp/\(keptFolder)/\(AppInfo.name).app/old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path), result.output)
    }
}
