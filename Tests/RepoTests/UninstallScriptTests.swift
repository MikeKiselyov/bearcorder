import AppCore
import Foundation
import XCTest

/// scripts/uninstall.sh on a made-up home folder: it removes every trace of the app and keeps the
/// person's saved files and other apps. Steps that touch the running app, settings and
/// permissions are only printed (APP_DRY_SYSTEM), so the real app is left alone.
final class UninstallScriptTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    /// `built`: has the keys every build-app.sh build writes.
    private func makeApp(at url: URL, executable: String, bundleId: String, built: Bool = true) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: String] = ["CFBundleExecutable": executable, "CFBundleIdentifier": bundleId]
        if built && executable == AppInfo.name {
            info["SourcePath"] = "/somewhere/source"
            info["SourceCommit"] = "0123abc"
        }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func makeFile(_ path: String, in home: URL) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    /// Runs git in `folder` with no personal or system git settings.
    @discardableResult
    private func git(_ arguments: [String], in folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "-c", "user.name=Test", "-c", "user.email=test@example.com"] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let printed = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments): \(printed)")
        return printed
    }

    /// The source the installer keeps: a clone of a repository with one commit, nothing changed.
    private func makeSourceClone(in home: URL) throws -> URL {
        let origin = home.appendingPathComponent("origin")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: origin)
        try Data("echo install\n".utf8).write(to: origin.appendingPathComponent("install.sh"))
        try git(["add", "install.sh"], in: origin)
        try git(["commit", "-q", "-m", "first"], in: origin)
        let source = home.appendingPathComponent(AppInfo.sourceFolder)
        try git(["clone", "-q", origin.path, source.path], in: home)
        return source
    }

    /// `answers`: what is typed at the questions, one per line, in place of the terminal.
    private func run(home: URL, arguments: [String], answers: String? = nil, extraEnvironment: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/uninstall.sh").path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["TMPDIR"] = home.appendingPathComponent("tmp").path
        environment["APP_APPS_DIRS"] = home.appendingPathComponent("Applications").path
        // Every folder the script reads from the environment is inside the made-up home, so an exported
        // variable of the person running the tests is never removed.
        environment["APP_SOURCE_DIR"] = home.appendingPathComponent(AppInfo.sourceFolder).path
        environment.removeValue(forKey: "APP_TTY")
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["APP_DRY_SYSTEM"] = "1"
        environment["NO_COLOR"] = "1"
        // The real lsregister dump takes 5-7 s: a small one with a copy that is gone stands in.
        let dump = home.appendingPathComponent("lsregister-dump.txt")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let gonePath = home.appendingPathComponent("Gone/\(AppInfo.name).app").path
        try "path:               \(gonePath) (0x1234)\n".write(to: dump, atomically: true, encoding: .utf8)
        environment["APP_LSREGISTER_DUMP"] = dump.path
        if let answers {
            let file = home.appendingPathComponent("answers.txt")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try answers.write(to: file, atomically: true, encoding: .utf8)
            environment["APP_TTY"] = file.path
        }
        for (name, value) in extraEnvironment {
            environment[name] = value
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
        let storage = AppInfo.name
        // A copy renamed in Finder is still found: its executable has the app's name.
        try makeApp(at: home.appendingPathComponent("Applications/Renamed.app"), executable: AppInfo.name, bundleId: "test.ourapp")
        try makeApp(at: home.appendingPathComponent("Applications/Other.app"), executable: "Other", bundleId: "com.other")
        try makeFile("Library/Application Support/\(storage)/Captures/one/screenshot.png", in: home)
        try makeFile("Library/Logs/\(storage)/\(AppInfo.name).log", in: home)
        _ = try makeSourceClone(in: home)
        try makeFile("Library/Preferences/test.ourapp.plist", in: home)
        try makeFile("Library/Caches/test.ourapp/cache.db", in: home)
        try makeFile("Library/HTTPStorages/test.ourapp/cookies", in: home)
        try makeFile("Library/Saved Application State/test.ourapp.savedState/windows.plist", in: home)
        try makeFile("tmp/\(storage)/export.mp4", in: home)
        try makeFile("Library/Caches/com.other/keep.db", in: home)
        try makeFile("Desktop/\(storage)/bug.png", in: home)
        // Leftovers of debug runs from the source and of the checks.
        try makeFile("Library/Preferences/io.github.\(AppInfo.slug).debug.plist", in: home)
        try makeFile("Library/Preferences/\(AppInfo.name).selftest.memory.1234.plist", in: home)
        try makeFile("Library/Preferences/\(AppInfo.name).selftest.5678.plist", in: home)
        try makeFile("Library/Preferences/\(AppInfo.name)-crash-check.plist", in: home)
        try makeFile("Library/Preferences/\(AppInfo.name)-feedback-check.plist", in: home)
        try makeFile("Library/Preferences/com.other.plist", in: home)

        let result = try run(home: home, arguments: ["--yes"])
        XCTAssertEqual(result.status, 0, result.output)

        XCTAssertFalse(exists("Applications/Renamed.app", in: home), "the app")
        XCTAssertFalse(exists("Library/Application Support/\(storage)", in: home), "captures and buffer")
        XCTAssertFalse(exists("Library/Logs/\(storage)", in: home), "logs")
        XCTAssertFalse(exists(AppInfo.sourceFolder, in: home), "the source kept for updates")
        XCTAssertFalse(exists("Library/Preferences/test.ourapp.plist", in: home), "settings")
        XCTAssertFalse(exists("Library/Caches/test.ourapp", in: home), "caches")
        XCTAssertFalse(exists("Library/HTTPStorages/test.ourapp", in: home), "cookies")
        XCTAssertFalse(exists("Library/Saved Application State/test.ourapp.savedState", in: home), "windows to restore")
        XCTAssertFalse(exists("tmp/\(storage)", in: home), "temporary files")

        XCTAssertFalse(exists("Library/Preferences/io.github.\(AppInfo.slug).debug.plist", in: home), "settings of debug runs from the source")
        XCTAssertFalse(exists("Library/Preferences/\(AppInfo.name).selftest.memory.1234.plist", in: home), "self-test scratch settings")
        XCTAssertFalse(exists("Library/Preferences/\(AppInfo.name).selftest.5678.plist", in: home), "self-test scratch settings")
        XCTAssertFalse(exists("Library/Preferences/\(AppInfo.name)-crash-check.plist", in: home), "crash check settings")
        XCTAssertFalse(exists("Library/Preferences/\(AppInfo.name)-feedback-check.plist", in: home), "feedback check settings")
        XCTAssertTrue(exists("Library/Preferences/com.other.plist", in: home), "another app's settings stay")

        XCTAssertTrue(exists("Applications/Other.app", in: home), "another app stays")
        XCTAssertTrue(exists("Library/Caches/com.other/keep.db", in: home), "another app's cache stays")
        XCTAssertTrue(exists("Desktop/\(storage)/bug.png", in: home), "saved files stay")

        XCTAssertTrue(result.output.contains("would run: pkill -x \(AppInfo.name)"), "quits the app first")
        XCTAssertTrue(result.output.contains("Renamed.app/Contents/MacOS/\(AppInfo.name) --forget-login-item"), "takes it off the login items")
        XCTAssertTrue(result.output.contains("would run: tccutil reset All test.ourapp"), "removes the permissions")
        XCTAssertTrue(result.output.contains("would run: tccutil reset All \(AppInfo.defaultBundleId)"), "also for the installer's bundle id")
        XCTAssertTrue(result.output.contains("would run: defaults delete test.ourapp"), "removes the settings")
        // A remembered copy would file the next install's Screen Recording request under its id.
        XCTAssertTrue(result.output.contains("lsregister -u \(home.path)/Applications/Renamed.app"), "macOS forgets the removed app")
        XCTAssertTrue(result.output.contains("lsregister -u \(home.path)/\(AppInfo.sourceFolder)/build/\(AppInfo.name).app"), "and the installer's build")
        XCTAssertTrue(result.output.contains("lsregister -u \(home.path)/Gone/\(AppInfo.name).app"), "and a remembered copy that is gone")
        // Permissions first: tccutil refuses a bundle id whose app is already gone.
        if let reset = result.output.range(of: "tccutil reset All test.ourapp"), let removed = result.output.range(of: "Removed \(home.path)/Applications/Renamed.app") {
            XCTAssertTrue(reset.lowerBound < removed.lowerBound, "permissions are reset before the app is removed")
        } else {
            XCTFail("permission reset or app removal missing: \(result.output)")
        }
    }

    /// An app with this app's executable name but nothing else of it (no build keys, an id the app
    /// never had) is another app: it stays with its settings and permissions.
    func testKeepsAnAppThatOnlyHasTheExecutableName() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try makeApp(at: home.appendingPathComponent("Applications/Tool.app"), executable: AppInfo.name, bundleId: "com.example.tool", built: false)
        try makeApp(at: home.appendingPathComponent("Applications/Installed.app"), executable: AppInfo.name, bundleId: AppInfo.defaultBundleId, built: false)
        try makeFile("Library/Caches/com.example.tool/keep.db", in: home)
        let result = try run(home: home, arguments: ["--yes"])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(exists("Applications/Tool.app", in: home), result.output)
        XCTAssertTrue(exists("Library/Caches/com.example.tool/keep.db", in: home), result.output)
        XCTAssertFalse(result.output.contains("com.example.tool"), result.output)
        XCTAssertFalse(exists("Applications/Installed.app", in: home), "a copy with the installer's id goes: \(result.output)")
    }

    /// A bundle id is read from an app's Info.plist: one that is not a plain reverse-DNS id never
    /// reaches rm, defaults or tccutil (\"../../Desktop\" would remove the saved files).
    func testAnOddBundleIdRemovesNothing() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let storage = AppInfo.name
        try makeApp(at: home.appendingPathComponent("Applications/Odd.app"), executable: AppInfo.name, bundleId: "../../Desktop")
        try makeFile("Desktop/\(storage)/bug.png", in: home)
        try makeFile("Desktop/notes.txt", in: home)
        // The folders a real home has, so "Library/Caches/../../Desktop" leads to the Desktop.
        for folder in ["Library/Caches", "Library/HTTPStorages", "Library/WebKit", "Library/Preferences"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let result = try run(home: home, arguments: ["--yes"])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(exists("Desktop/\(storage)/bug.png", in: home), result.output)
        XCTAssertTrue(exists("Desktop/notes.txt", in: home), result.output)
        XCTAssertFalse(result.output.contains("../../Desktop"), result.output)
    }

    /// The source kept for updates goes only when nothing in it would be lost: a git clone with no
    /// changes and no commits that are not on its upstream. Otherwise it stays and the script says why.
    func testKeepsTheSourceWithWorkInIt() throws {
        let cases = ["not a clone", "changed file", "new file", "local commit", "no upstream", "clean"]
        for name in cases {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: home) }
            try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: AppInfo.name, bundleId: "test.ourapp")
            var source = home.appendingPathComponent(AppInfo.sourceFolder)
            switch name {
            case "not a clone":
                try makeFile("\(AppInfo.sourceFolder)/work.txt", in: home)
            case "changed file":
                source = try makeSourceClone(in: home)
                try Data("changed\n".utf8).write(to: source.appendingPathComponent("install.sh"))
            case "new file":
                source = try makeSourceClone(in: home)
                try Data("mine\n".utf8).write(to: source.appendingPathComponent("mine.txt"))
            case "local commit":
                source = try makeSourceClone(in: home)
                try Data("changed\n".utf8).write(to: source.appendingPathComponent("install.sh"))
                try git(["commit", "-q", "-am", "mine"], in: source)
            case "no upstream":
                source = try makeSourceClone(in: home)
                try git(["checkout", "-q", "-b", "mine"], in: source)
            default:
                source = try makeSourceClone(in: home)
            }
            let result = try run(home: home, arguments: ["--yes"])
            XCTAssertEqual(result.status, 0, "\(name): \(result.output)")
            XCTAssertFalse(exists("Applications/\(AppInfo.name).app", in: home), "\(name): the app goes")
            if name == "clean" {
                XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "\(name): \(result.output)")
            } else {
                XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "\(name): \(result.output)")
                XCTAssertTrue(result.output.contains("Kept \(source.path)"), "\(name): says why: \(result.output)")
            }
        }
    }

    /// Leaving is met with a sorry and a link to say what did not work; a --yes run never waits on
    /// a question or opens a browser.
    func testSaysSorryAndAsksForFeedback() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: AppInfo.name, bundleId: "test.ourapp")
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
        try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: AppInfo.name, bundleId: "test.ourapp")
        try makeFile("Library/Logs/\(AppInfo.name)/\(AppInfo.name).log", in: home)

        // No terminal to answer from and no --yes.
        let result = try run(home: home, arguments: [])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("--yes"), result.output)
        XCTAssertTrue(exists("Applications/\(AppInfo.name).app", in: home))
        XCTAssertTrue(exists("Library/Logs/\(AppInfo.name)/\(AppInfo.name).log", in: home))
    }

    /// In a terminal: yes to uninstall, then Return opens the feedback form; "n" leaves it closed.
    func testOffersToOpenTheFeedbackForm() throws {
        let link = "https://github.com/\(FeedbackReport.defaultRepository)/issues/new?template=uninstall_feedback.yml"
        for (answers, opens) in [("y\n\n", true), ("y\nn\n", false)] {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: home) }
            try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: AppInfo.name, bundleId: "test.ourapp")
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
        try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: AppInfo.name, bundleId: "test.ourapp")
        let result = try run(home: home, arguments: [], answers: "n\n")
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(exists("Applications/\(AppInfo.name).app", in: home))
        XCTAssertTrue(result.output.contains("Phew! The bear wipes its tears. Nothing was removed."), result.output)
        XCTAssertFalse(result.output.contains("feedback form"), result.output)
    }

    /// Without Command Line Tools or Xcode, /usr/bin/git shows macOS's dialog to install them: git is
    /// not run at all and the source stays, even a clean clone.
    func testKeepsTheSourceWithoutDeveloperToolsAndDoesNotRunGit() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try makeApp(at: home.appendingPathComponent("Applications/\(AppInfo.name).app"), executable: AppInfo.name, bundleId: "test.ourapp")
        let source = try makeSourceClone(in: home)
        // A git first on PATH that notes every call.
        let tools = home.appendingPathComponent("fake-bin")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let calls = home.appendingPathComponent("git-calls.txt")
        let fakeGit = tools.appendingPathComponent("git")
        try "#!/bin/bash\necho \"$*\" >> \"\(calls.path)\"\nexec /usr/bin/git \"$@\"\n".write(to: fakeGit, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGit.path)
        let path = tools.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")

        let result = try run(home: home, arguments: ["--yes"], extraEnvironment: ["PATH": path, "APP_NO_DEVELOPER_TOOLS": "1"])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertFalse(exists("Applications/\(AppInfo.name).app", in: home), "the app goes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), result.output)
        XCTAssertTrue(result.output.contains("Kept \(source.path)"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: calls.path), "git was run: \((try? String(contentsOf: calls, encoding: .utf8)) ?? "")")
    }

}
