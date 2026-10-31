import AppCore
import Foundation
import XCTest

/// The full test run builds the app once (all.sh) and the e2e scripts reuse it; build-app.sh
/// --install-only installs that build without building or signing. Nothing here builds, signs or
/// installs for real: fake folders, fake pkill/pgrep/swift/codesign, no /Applications.
final class BuildOnceScriptsTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("build-once-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// Commands that must not run: the stub in front of the real one records its name and succeeds
    /// (pgrep fails: no copy of the app is running; codesign fails with `codesignFails`).
    private func makeStubs(in folder: URL, codesignFails: Bool = false) throws -> URL {
        let stubs = folder.appendingPathComponent("stubs")
        try FileManager.default.createDirectory(at: stubs, withIntermediateDirectories: true)
        let calls = folder.appendingPathComponent("calls.txt").path
        for name in ["pkill", "pgrep", "swift", "codesign", "security", "open", "tccutil", "osascript", "defaults", "lsregister"] {
            var exitCode = "0"
            if name == "pgrep" || (name == "codesign" && codesignFails) {
                exitCode = "1"
            }
            let script = "#!/bin/bash\necho \"\(name) $*\" >> \"\(calls)\"\nexit \(exitCode)\n"
            let file = stubs.appendingPathComponent(name)
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return stubs
    }

    private func bash(_ script: String, environment extra: [String: String], path stubs: URL? = nil) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        var environment = ProcessInfo.processInfo.environment
        environment["ROOT"] = root.path
        environment.removeValue(forKey: "APP_BUILT")
        if let stubs {
            environment["PATH"] = stubs.path + ":" + (environment["PATH"] ?? "")
        }
        for (key, value) in extra {
            environment[key] = value
        }
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: the e2e scripts

    func testTestScriptsBuildOnlyThroughTheGuardedHelper() throws {
        for name in ["e2e", "e2e-section", "e2e-features", "perf"] {
            let text = try read("scripts/test/\(name).sh")
            XCTAssertTrue(text.contains("build_test_app || exit 1"), "\(name).sh builds through build_test_app")
            XCTAssertFalse(text.contains("scripts/build-app.sh >/dev/null"), "\(name).sh has no direct build call")
        }
    }

    /// The log is the person's own log file: a run reads only the lines written after it started
    /// and never deletes the file.
    func testTestScriptsKeepThePersonsLog() throws {
        for name in ["e2e", "perf"] {
            let text = try read("scripts/test/\(name).sh")
            // Only the lines that define the log, count its lines and read this run's part touch it.
            let allowed = ["LOG=\"$HOME/Library/Logs/$APP_NAME/$APP_NAME.log\"", "{ wc -l < \"$LOG\"; }", "cat \"$LOG\"",
                           "tail -n +\"$((log_lines_before + 1))\" \"$LOG\"", "Log: $LOG"]
            for line in text.split(separator: "\n") where line.contains("$LOG") {
                let known = allowed.contains { line.contains($0) }
                XCTAssertTrue(known, "\(name).sh touches the whole log: \(line)")
            }
            XCTAssertFalse(text.contains("rm -f \"$LOG\""), "\(name).sh deletes the log")
            XCTAssertTrue(text.contains("log_lines_before=$(log_line_count)"), "\(name).sh notes where the log was when it started")
        }
    }

    /// The test scripts start with the bundle id: from .env, else the installer's. Run up to that
    /// line in a copy of the repository without .env and without APP_BUNDLE_ID, under `set -u`.
    func testTestScriptsFindTheBundleIdWithoutEnvFile() throws {
        let folder = try makeFolder()
        for path in ["scripts/lib/common.sh", "scripts/lib/app-name.sh", "Sources/AppCore/Support/AppInfo.swift"] {
            let target = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: root.appendingPathComponent(path), to: target)
        }
        let bundleLine = "BUNDLE_ID=\"${APP_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}\"\n"
        for name in ["e2e", "e2e-features", "e2e-section", "perf"] {
            let text = try read("scripts/test/\(name).sh")
            let line = try XCTUnwrap(text.range(of: bundleLine), "\(name).sh sets BUNDLE_ID")
            let head = String(text[..<line.upperBound]) + "echo \"bundle=$BUNDLE_ID\"\n"
            let script = folder.appendingPathComponent("scripts/test/\(name).sh")
            try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
            try head.write(to: script, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "APP_BUNDLE_ID")
            process.environment = environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let printed = String(decoding: data, as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, "\(name).sh: \(printed)")
            XCTAssertTrue(printed.contains("bundle=\(AppInfo.defaultBundleId)\n"), "\(name).sh: \(printed)")
        }
    }

    /// Runs `steps` in bash with run-log.sh sourced and LOG pointing at `log`; returns what it printed
    /// on stdout and stderr.
    private func runLogScript(_ steps: String, log: URL) throws -> (output: String, errors: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        let library = root.appendingPathComponent("scripts/test/lib/run-log.sh").path
        process.arguments = ["-c", "set -uo pipefail\nLOG=\"$1\"\nsource \"$2\"\n" + steps, "run-log-test", log.path, library]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        let complained = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (output: String(decoding: printed, as: UTF8.self), errors: String(decoding: complained, as: UTF8.self))
    }

    /// run_log gives only this run's lines. If the app started the log over during the run (past
    /// 2 MB), the lines before that are gone: run_log says so loudly, with an ERROR line the "no
    /// errors in the log" check counts, instead of letting a negative check pass on half a log.
    func testRunLogSaysWhenTheLogStartedOver() throws {
        let folder = try makeFolder()
        let log = folder.appendingPathComponent("app.log")
        try "old 1\nold 2\nold 3\n".write(to: log, atomically: false, encoding: .utf8)
        let start = "log_lines_before=$(log_line_count)\nlog_first_before=$(log_first_line)\n"

        let plain = try runLogScript(start + "printf 'new 1\\nnew 2\\n' >> \"$LOG\"\nrun_log", log: log)
        XCTAssertEqual(plain.output, "new 1\nnew 2\n")
        XCTAssertEqual(plain.errors, "")

        // Started over and grew past the old length again: counting lines alone cannot tell.
        try "old 1\nold 2\nold 3\n".write(to: log, atomically: false, encoding: .utf8)
        let regrown = try runLogScript(start + ": > \"$LOG\"\nprintf 'a\\nb\\nc\\nd\\nlast\\n' >> \"$LOG\"\nrun_log", log: log)
        XCTAssertTrue(regrown.output.contains("ERROR"), regrown.output)
        XCTAssertTrue(regrown.output.contains("last"), regrown.output)
        XCTAssertTrue(regrown.errors.contains("started its log over"), regrown.errors)

        // Started over and still shorter.
        try "old 1\nold 2\nold 3\n".write(to: log, atomically: false, encoding: .utf8)
        let shorter = try runLogScript(start + ": > \"$LOG\"\nprintf 'x\\n' >> \"$LOG\"\nrun_log", log: log)
        XCTAssertTrue(shorter.output.contains("ERROR"), shorter.output)
        XCTAssertTrue(shorter.output.contains("x\n"), shorter.output)
    }

    func testPerfUsesTheSameAutomationBuildAsTheOthers() throws {
        // perf.sh sources test-app.sh, which exports APP_AUTOMATION=1 for the build.
        XCTAssertTrue(try read("scripts/test/perf.sh").contains("scripts/test/lib/test-app.sh"))
        XCTAssertTrue(try read("scripts/test/lib/test-app.sh").contains("export APP_AUTOMATION=1"))
    }

    func testAllBuildsOnceBeforeTheE2eSuites() throws {
        let text = try read("scripts/test/all.sh")
        let build = try XCTUnwrap(text.range(of: "run_suite app-build build_test_app_once"))
        let check = try XCTUnwrap(text.range(of: "case \"${RESULTS[${#RESULTS[@]} - 1]}\" in"))
        let flag = try XCTUnwrap(text.range(of: "export APP_BUILT=1"))
        let first = try XCTUnwrap(text.range(of: "run_suite e2e scripts/test/e2e.sh"))
        let skipped = try XCTUnwrap(text.range(of: "not run: app-build failed"))
        XCTAssertTrue(build.lowerBound < check.lowerBound && check.lowerBound < flag.lowerBound && flag.lowerBound < first.lowerBound)
        XCTAssertTrue(first.lowerBound < skipped.lowerBound, "the e2e suites run only in the ok branch, a failed build is reported")
        XCTAssertTrue(text.contains("APP_AUTOMATION=1 scripts/build-app.sh"))
    }

    func testBuiltAppIsReusedWithoutBuilding() throws {
        let folder = try makeFolder()
        let fakeRoot = folder.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: fakeRoot.appendingPathComponent("scripts/lib"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeRoot.appendingPathComponent("Sources/AppCore/Support"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("scripts/lib/app-name.sh"), to: fakeRoot.appendingPathComponent("scripts/lib/app-name.sh"))
        try FileManager.default.copyItem(
            at: root.appendingPathComponent("Sources/AppCore/Support/AppInfo.swift"),
            to: fakeRoot.appendingPathComponent("Sources/AppCore/Support/AppInfo.swift"))
        let marker = folder.appendingPathComponent("built.txt").path
        let build = "#!/bin/bash\necho built >> \"\(marker)\"\n"
        let buildScript = fakeRoot.appendingPathComponent("scripts/build-app.sh")
        try build.write(to: buildScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: buildScript.path)
        let source = "ROOT=\"\(fakeRoot.path)\"; source \"\(root.path)/scripts/test/lib/test-app.sh\"; "

        // Built by all.sh but missing: stop with a clear message, build nothing.
        var result = try bash(source + "build_test_app", environment: ["APP_BUILT": "1"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("build/\(try XCTUnwrap(bashAppName(source))).app missing: run scripts/build-app.sh first"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))

        // Built and present: used as it is.
        let appName = try XCTUnwrap(bashAppName(source))
        try FileManager.default.createDirectory(at: fakeRoot.appendingPathComponent("build/\(appName).app"), withIntermediateDirectories: true)
        // An app without the automation marker (old or release build) is not reused.
        result = try bash(source + "build_test_app", environment: ["APP_BUILT": "1"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("not a build with automation"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
        FileManager.default.createFile(atPath: fakeRoot.appendingPathComponent("build/.automation-build").path, contents: Data())
        result = try bash(source + "build_test_app", environment: ["APP_BUILT": "1"])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker), "no build when APP_BUILT=1")

        // Without the variable the script builds, as before.
        result = try bash(source + "build_test_app", environment: [:])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker), "builds without APP_BUILT")
    }

    private func bashAppName(_ source: String) throws -> String? {
        let result = try bash(source + "echo \"name=$APP_NAME\"", environment: [:])
        let line = result.output.split(separator: "\n").first { $0.hasPrefix("name=") }
        return line.map { String($0.dropFirst(5)) }
    }

    // MARK: build-app.sh --install-only

    /// `built`: has the keys every build-app.sh build writes (SourcePath, SourceCommit), and an
    /// executable that reports the version in the plist, as the install checks.
    private func makeApp(at url: URL, bundleId: String, executable: String = AppInfo.name, built: Bool = true) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        var info: [String: String] = ["CFBundleExecutable": executable, "CFBundleIdentifier": bundleId]
        if built {
            info["SourcePath"] = "/somewhere/source"
            info["SourceCommit"] = "0123abc"
            info["CFBundleShortVersionString"] = "9.9.9"
        }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let binary = contents.appendingPathComponent("MacOS/\(executable)")
        try "#!/bin/bash\necho 9.9.9\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    private func appName() throws -> String {
        try XCTUnwrap(bashAppName("ROOT=\"\(root.path)\"; source \"\(root.path)/scripts/test/lib/test-app.sh\"; "))
    }

    /// build-app.sh --install-only with every folder it touches inside `folder`: a fake home, a fake
    /// /Applications, its own temporary folder, and lsregister, tccutil and osascript as stubs.
    private func install(in folder: URL, stubs: URL, extra: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let home = folder.appendingPathComponent("home")
        let temporary = folder.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        var environment: [String: String] = [
            "HOME": home.path,
            "TMPDIR": temporary.path,
            "APP_BUILD_DIR": folder.appendingPathComponent("build").path,
            "APP_APPLICATIONS_DIR": folder.appendingPathComponent("system-apps").path,
            "APP_INSTALL_DIR": "",
            "LSREGISTER": stubs.appendingPathComponent("lsregister").path,
            "APP_KEEP_PERMISSIONS": "1",
            "APP_NO_OPEN": "1",
        ]
        for (key, value) in extra {
            environment[key] = value
        }
        return try bash("\"\(root.path)/scripts/build-app.sh\" --install-only", environment: environment, path: stubs)
    }

    func testInstallOnlyCopiesTheBuiltAppWithoutBuildingOrSigning() throws {
        let folder = try makeFolder()
        let stubs = try makeStubs(in: folder)
        let buildDir = folder.appendingPathComponent("build")
        let installDir = folder.appendingPathComponent("apps")
        let appName = try XCTUnwrap(bashAppName("ROOT=\"\(root.path)\"; source \"\(root.path)/scripts/test/lib/test-app.sh\"; "))
        try makeApp(at: buildDir.appendingPathComponent("\(appName).app"), bundleId: "test.built.\(UUID().uuidString)")
        // An installed copy exists, so this counts as an update: no setting of the real app is touched.
        try makeApp(at: installDir.appendingPathComponent("\(appName).app"), bundleId: "test.old")
        let result = try install(in: folder, stubs: stubs, extra: ["APP_INSTALL_DIR": installDir.path])
        XCTAssertEqual(result.status, 0, result.output)
        let installedPlist = installDir.appendingPathComponent("\(appName).app/Contents/Info.plist")
        let info = try XCTUnwrap(NSDictionary(contentsOf: installedPlist))
        XCTAssertTrue((info["CFBundleIdentifier"] as? String ?? "").hasPrefix("test.built."), "the built app replaced the old copy: \(result.output)")
        let calls = (try? String(contentsOf: folder.appendingPathComponent("calls.txt"), encoding: .utf8)) ?? ""
        XCTAssertFalse(calls.contains("swift "), "no swift build: \(calls)")
        XCTAssertFalse(calls.contains("codesign --force"), "no signing: \(calls)")
        XCTAssertTrue(calls.contains("codesign --verify"), "the built app is checked before it goes in: \(calls)")
        XCTAssertFalse(calls.contains("security"), "no keychain query: \(calls)")
        XCTAssertFalse(calls.contains("open"), "APP_NO_OPEN is honored: \(calls)")
    }

    /// A VERSION from the environment or .env must not decide the version check of a build made earlier.
    func testInstallOnlyIgnoresAVersionFromTheEnvironment() throws {
        let folder = try makeFolder()
        let stubs = try makeStubs(in: folder)
        let buildDir = folder.appendingPathComponent("build")
        let installDir = folder.appendingPathComponent("apps")
        let appName = try appName()
        try makeApp(at: buildDir.appendingPathComponent("\(appName).app"), bundleId: "test.built.\(UUID().uuidString)")
        try makeApp(at: installDir.appendingPathComponent("\(appName).app"), bundleId: "test.old")
        let result = try install(in: folder, stubs: stubs, extra: ["APP_INSTALL_DIR": installDir.path, "VERSION": "1.0.0"])
        XCTAssertEqual(result.status, 0, result.output)
        let installedPlist = installDir.appendingPathComponent("\(appName).app/Contents/Info.plist")
        let info = try XCTUnwrap(NSDictionary(contentsOf: installedPlist))
        XCTAssertTrue((info["CFBundleIdentifier"] as? String ?? "").hasPrefix("test.built."), result.output)
    }

    func testInstallOnlyStopsWhenThereIsNoBuild() throws {
        let folder = try makeFolder()
        let stubs = try makeStubs(in: folder)
        let installDir = folder.appendingPathComponent("apps")
        let result = try install(
            in: folder, stubs: stubs,
            extra: ["APP_BUILD_DIR": folder.appendingPathComponent("empty").path, "APP_INSTALL_DIR": installDir.path])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("is missing: run scripts/build-app.sh first"), result.output)
        let calls = (try? String(contentsOf: folder.appendingPathComponent("calls.txt"), encoding: .utf8)) ?? ""
        XCTAssertFalse(calls.contains("swift "), calls)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path), "nothing installed")
    }

    /// Another app that sits where this one goes is never deleted: the install stops and says why.
    func testInstallStopsAtAnAppThatIsNotOurs() throws {
        let name = try appName()
        let cases: [(id: String, executable: String, built: Bool)] = [
            ("com.example.other", "Other", false),
            // An executable with the app's name alone is not enough: no build keys, an id the app never had.
            ("com.example.other", name, false),
        ]
        for item in cases {
            let folder = try makeFolder()
            let stubs = try makeStubs(in: folder)
            try makeApp(at: folder.appendingPathComponent("build/\(name).app"), bundleId: "test.built")
            let installDir = folder.appendingPathComponent("apps")
            let other = installDir.appendingPathComponent("\(name).app")
            try makeApp(at: other, bundleId: item.id, executable: item.executable, built: item.built)
            let result = try install(in: folder, stubs: stubs, extra: ["APP_INSTALL_DIR": installDir.path])
            XCTAssertNotEqual(result.status, 0, "\(item): \(result.output)")
            XCTAssertTrue(result.output.contains("is not a \(AppInfo.name) build"), "\(item): \(result.output)")
            let info = try XCTUnwrap(NSDictionary(contentsOf: other.appendingPathComponent("Contents/Info.plist")))
            XCTAssertEqual(info["CFBundleIdentifier"] as? String, item.id, "\(item): the other app stays")
            let calls = (try? String(contentsOf: folder.appendingPathComponent("calls.txt"), encoding: .utf8)) ?? ""
            XCTAssertFalse(calls.contains("pkill"), "\(item): stops before quitting anything: \(calls)")
        }
    }

    /// A copy without the build keys still counts when its id is one of the app's.
    func testInstallReplacesAnOlderCopyWithTheAppsId() throws {
        let name = try appName()
        let folder = try makeFolder()
        let stubs = try makeStubs(in: folder)
        try makeApp(at: folder.appendingPathComponent("build/\(name).app"), bundleId: "test.built")
        let installDir = folder.appendingPathComponent("apps")
        try makeApp(at: installDir.appendingPathComponent("\(name).app"), bundleId: AppInfo.defaultBundleId, built: false)
        let result = try install(in: folder, stubs: stubs, extra: ["APP_INSTALL_DIR": installDir.path])
        XCTAssertEqual(result.status, 0, result.output)
        let info = try XCTUnwrap(NSDictionary(contentsOf: installDir.appendingPathComponent("\(name).app/Contents/Info.plist")))
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "test.built", result.output)
    }

    /// Permissions go only for a copy the install replaces; the copy in the other Applications folder stays
    /// and keeps them.
    func testOnlyAReplacedCopyLosesItsPermissions() throws {
        let name = try appName()
        let folder = try makeFolder()
        let stubs = try makeStubs(in: folder)
        try makeApp(at: folder.appendingPathComponent("build/\(name).app"), bundleId: "test.built")
        let systemApps = folder.appendingPathComponent("system-apps")
        try makeApp(at: systemApps.appendingPathComponent("\(name).app"), bundleId: "test.replaced")
        let staying = folder.appendingPathComponent("home/Applications/\(name).app")
        try makeApp(at: staying, bundleId: "test.stays")
        let result = try install(in: folder, stubs: stubs)
        XCTAssertEqual(result.status, 0, result.output)
        let installed = try XCTUnwrap(NSDictionary(contentsOf: systemApps.appendingPathComponent("\(name).app/Contents/Info.plist")))
        XCTAssertEqual(installed["CFBundleIdentifier"] as? String, "test.built", result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staying.path), "the other copy stays")
        let calls = (try? String(contentsOf: folder.appendingPathComponent("calls.txt"), encoding: .utf8)) ?? ""
        XCTAssertTrue(calls.contains("tccutil reset All test.replaced"), "the replaced copy's permissions go: \(calls)")
        XCTAssertFalse(calls.contains("test.stays"), "the staying copy keeps its permissions: \(calls)")
        XCTAssertFalse(calls.contains("osascript"), "APP_KEEP_PERMISSIONS: no password dialog: \(calls)")
    }

    func testBuildScriptWritesTheAutomationMarkerOnlyForAutomationBuilds() throws {
        let text = try read("scripts/build-app.sh")
        XCTAssertTrue(text.contains("rm -f \"$BUILD_DIR/.automation-build\""), "removed at the start of every build")
        XCTAssertTrue(text.contains("touch \"$BUILD_DIR/.automation-build\""))
        let touch = try XCTUnwrap(text.range(of: "touch \"$BUILD_DIR/.automation-build\""))
        let guardLine = try XCTUnwrap(text.range(of: "if [ \"${APP_AUTOMATION:-}\" = \"1\" ]; then\n        touch"))
        XCTAssertTrue(guardLine.upperBound <= touch.upperBound)
    }

    func testFeaturesWelcomeGuideUsesInstallOnly() throws {
        let text = try read("scripts/test/e2e-features.sh")
        XCTAssertEqual(text.components(separatedBy: "scripts/build-app.sh --install-only").count - 1, 2)
        XCTAssertFalse(text.contains("scripts/build-app.sh --install >"))
    }

    /// A built app that fails its check is not installed: the installed copy and a renamed copy stay,
    /// nothing is opened, and no temporary copy is left.
    func testInstallKeepsTheInstalledCopyWhenTheBuildFailsItsCheck() throws {
        let name = try appName()
        let folder = try makeFolder()
        let stubs = try makeStubs(in: folder, codesignFails: true)
        try makeApp(at: folder.appendingPathComponent("build/\(name).app"), bundleId: "test.built")
        let installDir = folder.appendingPathComponent("apps")
        let installed = installDir.appendingPathComponent("\(name).app")
        try makeApp(at: installed, bundleId: "test.built")
        let renamed = installDir.appendingPathComponent("\(name) copy.app")
        try makeApp(at: renamed, bundleId: "test.built")
        let result = try install(in: folder, stubs: stubs, extra: ["APP_INSTALL_DIR": installDir.path, "APP_BUNDLE_ID": "test.built"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("signature check"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/Info.plist").path), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path), "the renamed copy stays: \(result.output)")
        XCTAssertFalse(result.output.contains("==> installed to"), result.output)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("tmp").path)
        XCTAssertEqual(leftovers, [], "no temporary copy left")
    }

    /// After a failed install the old copy, quit for the install, is started again (unless
    /// APP_NO_OPEN); a first install that fails has nothing to start.
    func testAFailedInstallStartsTheOldCopyAgain() throws {
        let name = try appName()
        for hadCopy in [true, false] {
            let folder = try makeFolder()
            let stubs = try makeStubs(in: folder, codesignFails: true)
            try makeApp(at: folder.appendingPathComponent("build/\(name).app"), bundleId: "test.built")
            let installDir = folder.appendingPathComponent("apps")
            let installed = installDir.appendingPathComponent("\(name).app")
            if hadCopy {
                try makeApp(at: installed, bundleId: "test.built")
            }
            let result = try install(in: folder, stubs: stubs,
                                     extra: ["APP_INSTALL_DIR": installDir.path, "APP_BUNDLE_ID": "test.built", "APP_NO_OPEN": ""])
            XCTAssertNotEqual(result.status, 0, "\(hadCopy): \(result.output)")
            let calls = (try? String(contentsOf: folder.appendingPathComponent("calls.txt"), encoding: .utf8)) ?? ""
            XCTAssertEqual(calls.contains("open \(installed.path)"), hadCopy, "\(hadCopy): \(calls)")
            if hadCopy {
                XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/Info.plist").path))
            }
        }
    }
}
