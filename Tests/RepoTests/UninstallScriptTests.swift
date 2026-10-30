import BugbearCore
import Foundation
import XCTest

/// scripts/uninstall.sh on a made-up home folder: it removes every trace of the app and keeps the
/// person's saved files and other apps. Steps that touch the running app, settings and
/// permissions are only printed (BUGBEAR_DRY_SYSTEM), so the real Bugbear is left alone.
final class UninstallScriptTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func makeApp(at url: URL, executable: String, bundleId: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleExecutable": executable, "CFBundleIdentifier": bundleId]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func makeFile(_ path: String, in home: URL) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    /// `answers`: what is typed at the questions, one per line, in place of the terminal.
    private func run(home: URL, arguments: [String], answers: String? = nil) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/uninstall.sh").path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["TMPDIR"] = home.appendingPathComponent("tmp").path
        environment["BUGBEAR_APPS_DIRS"] = home.appendingPathComponent("Applications").path
        environment["BUGBEAR_DRY_SYSTEM"] = "1"
        environment["NO_COLOR"] = "1"
        // The real lsregister dump takes 5-7 s: a small one with a copy that is gone stands in.
        let dump = home.appendingPathComponent("lsregister-dump.txt")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let gonePath = home.appendingPathComponent("Gone/\(AppInfo.name).app").path
        try "path:               \(gonePath) (0x1234)\n".write(to: dump, atomically: true, encoding: .utf8)
        environment["BUGBEAR_LSREGISTER_DUMP"] = dump.path
        if let answers {
            let file = home.appendingPathComponent("answers.txt")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try answers.write(to: file, atomically: true, encoding: .utf8)
            environment["BUGBEAR_TTY"] = file.path
        }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }

    private func exists(_ path: String, in home: URL) -> Bool {
        return FileManager.default.fileExists(atPath: home.appendingPathComponent(path).path)
    }

    func testRemovesEverythingAndKeepsSavedFiles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let storage = AppInfo.storageName
        // A renamed copy is still found: its executable keeps the name.
        try makeApp(at: home.appendingPathComponent("Applications/Renamed.app"), executable: "Bugbear", bundleId: "test.bugbear")
        try makeApp(at: home.appendingPathComponent("Applications/Other.app"), executable: "Other", bundleId: "com.other")
        try makeFile("Library/Application Support/\(storage)/Captures/one/screenshot.png", in: home)
        try makeFile("Library/Logs/\(storage)/bugbear.log", in: home)
        try makeFile(".bugbear/scripts/install.sh", in: home)
        try makeFile("Library/Preferences/test.bugbear.plist", in: home)
        try makeFile("Library/Caches/test.bugbear/cache.db", in: home)
        try makeFile("Library/HTTPStorages/test.bugbear/cookies", in: home)
        try makeFile("Library/Saved Application State/test.bugbear.savedState/windows.plist", in: home)
        try makeFile("tmp/\(storage)/export.mp4", in: home)
        try makeFile("Library/Caches/com.other/keep.db", in: home)
        try makeFile("Desktop/\(storage)/bug.png", in: home)
        // Leftovers of builds run from the source and of the checks.
        try makeFile("Library/Preferences/Bugbear.plist", in: home)
        try makeFile("Library/Preferences/bugbear.selftest.memory.1234.plist", in: home)
        try makeFile("Library/Preferences/bugbear.selftest.5678.plist", in: home)
        try makeFile("Library/Preferences/bugbear-crash-check.plist", in: home)
        try makeFile("Library/Preferences/bugbear-feedback-check.plist", in: home)
        try makeFile("Library/Preferences/com.other.plist", in: home)

        let result = try run(home: home, arguments: ["--yes"])
        XCTAssertEqual(result.status, 0, result.output)

        XCTAssertFalse(exists("Applications/Renamed.app", in: home), "the app")
        XCTAssertFalse(exists("Library/Application Support/\(storage)", in: home), "captures and buffer")
        XCTAssertFalse(exists("Library/Logs/\(storage)", in: home), "logs")
        XCTAssertFalse(exists(".bugbear", in: home), "the source kept for updates")
        XCTAssertFalse(exists("Library/Preferences/test.bugbear.plist", in: home), "settings")
        XCTAssertFalse(exists("Library/Caches/test.bugbear", in: home), "caches")
        XCTAssertFalse(exists("Library/HTTPStorages/test.bugbear", in: home), "cookies")
        XCTAssertFalse(exists("Library/Saved Application State/test.bugbear.savedState", in: home), "windows to restore")
        XCTAssertFalse(exists("tmp/\(storage)", in: home), "temporary files")

        XCTAssertFalse(exists("Library/Preferences/Bugbear.plist", in: home), "settings of a build run from the source")
        XCTAssertFalse(exists("Library/Preferences/bugbear.selftest.memory.1234.plist", in: home), "self-test scratch settings")
        XCTAssertFalse(exists("Library/Preferences/bugbear.selftest.5678.plist", in: home), "self-test scratch settings")
        XCTAssertFalse(exists("Library/Preferences/bugbear-crash-check.plist", in: home), "crash check settings")
        XCTAssertFalse(exists("Library/Preferences/bugbear-feedback-check.plist", in: home), "feedback check settings")
        XCTAssertTrue(exists("Library/Preferences/com.other.plist", in: home), "another app's settings stay")

        XCTAssertTrue(exists("Applications/Other.app", in: home), "another app stays")
        XCTAssertTrue(exists("Library/Caches/com.other/keep.db", in: home), "another app's cache stays")
        XCTAssertTrue(exists("Desktop/\(storage)/bug.png", in: home), "saved files stay")

        XCTAssertTrue(result.output.contains("would run: pkill -x Bugbear"), "quits the app first")
        XCTAssertTrue(result.output.contains("Renamed.app/Contents/MacOS/Bugbear --forget-login-item"), "takes it off the login items")
        XCTAssertTrue(result.output.contains("would run: tccutil reset All test.bugbear"), "removes the permissions")
        XCTAssertTrue(result.output.contains("would run: tccutil reset All io.github.bugbear.app"), "also for the installer's bundle id")
        XCTAssertTrue(result.output.contains("would run: defaults delete test.bugbear"), "removes the settings")
        // A remembered copy would file the next install's Screen Recording request under its id.
        XCTAssertTrue(result.output.contains("lsregister -u \(home.path)/Applications/Renamed.app"), "macOS forgets the removed app")
        XCTAssertTrue(result.output.contains("lsregister -u \(home.path)/.bugbear/build/Bugbear.app"), "and the installer's build")
        XCTAssertTrue(result.output.contains("lsregister -u \(home.path)/Gone/\(AppInfo.name).app"), "and a remembered copy that is gone")
        // Permissions first: tccutil refuses a bundle id whose app is already gone.
        if let reset = result.output.range(of: "tccutil reset All test.bugbear"), let removed = result.output.range(of: "Removed \(home.path)/Applications/Renamed.app") {
            XCTAssertTrue(reset.lowerBound < removed.lowerBound, "permissions are reset before the app is removed")
        } else {
            XCTFail("permission reset or app removal missing: \(result.output)")
        }
    }

    /// Leaving is met with a sorry and a link to say what did not work; a --yes run never waits on
    /// a question or opens a browser.
    func testSaysSorryAndAsksForFeedback() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: "Bugbear", bundleId: "test.bugbear")
        let result = try run(home: home, arguments: ["--yes"])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Oh no, you are leaving? The bear is already crying."), result.output)
        XCTAssertTrue(result.output.contains("▀▀████████"), "the crying bear is drawn")
        let link = "https://github.com/\(FeedbackReport.defaultRepository)/issues/new?template=uninstall_feedback.yml"
        XCTAssertTrue(result.output.contains("The bear will miss you."), result.output)
        XCTAssertTrue(result.output.contains("please tell us what you did not like"), result.output)
        XCTAssertTrue(result.output.contains(link), "the feedback form of the app's own repository: \(result.output)")
        XCTAssertFalse(result.output.contains("Open the feedback form?"), "no question in a --yes run")
        XCTAssertFalse(result.output.contains("would run: open"), "no browser in a --yes run")
        if let done = result.output.range(of: "is uninstalled"), let ask = result.output.range(of: link) {
            XCTAssertTrue(done.lowerBound < ask.lowerBound, "the link comes after the uninstall, not before it")
        }
        // The form the link opens, with the field that asks what was not liked.
        let form = try String(contentsOf: root.appendingPathComponent(".github/ISSUE_TEMPLATE/uninstall_feedback.yml"), encoding: .utf8)
        XCTAssertTrue(form.contains("id: reason"), form)
    }

    func testAsksFirstAndRemovesNothingWithoutAnAnswer() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: "Bugbear", bundleId: "test.bugbear")
        try makeFile("Library/Logs/\(AppInfo.storageName)/bugbear.log", in: home)

        // No terminal to answer from and no --yes.
        let result = try run(home: home, arguments: [])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("--yes"), result.output)
        XCTAssertTrue(exists("Applications/\(AppInfo.name).app", in: home))
        XCTAssertTrue(exists("Library/Logs/\(AppInfo.storageName)/bugbear.log", in: home))
    }

    /// In a terminal: yes to uninstall, then Return opens the feedback form; "n" leaves it closed.
    func testOffersToOpenTheFeedbackForm() throws {
        let link = "https://github.com/\(FeedbackReport.defaultRepository)/issues/new?template=uninstall_feedback.yml"
        for (answers, opens) in [("y\n\n", true), ("y\nn\n", false)] {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: home) }
            try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: "Bugbear", bundleId: "test.bugbear")
            let result = try run(home: home, arguments: [], answers: answers)
            XCTAssertEqual(result.status, 0, result.output)
            XCTAssertFalse(exists("Applications/\(AppInfo.name).app", in: home), "uninstalled after yes")
            XCTAssertTrue(result.output.contains("Open the feedback form? [Y/n]"), result.output)
            XCTAssertEqual(result.output.contains("would run: open \(link)"), opens, "answers \(answers.debugDescription): \(result.output)")
            XCTAssertTrue(result.output.contains("Bye!"), result.output)
        }
    }

    /// A no keeps everything, and the bear is relieved.
    func testNoKeepsEverything() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: "Bugbear", bundleId: "test.bugbear")
        let result = try run(home: home, arguments: [], answers: "n\n")
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(exists("Applications/\(AppInfo.name).app", in: home))
        XCTAssertTrue(result.output.contains("Phew! The bear wipes its tears. Nothing was removed."), result.output)
        XCTAssertFalse(result.output.contains("feedback form"), result.output)
    }
}
