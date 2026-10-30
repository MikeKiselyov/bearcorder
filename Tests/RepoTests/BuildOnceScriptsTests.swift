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
    /// (pgrep fails: no Bugbear is running).
    private func makeStubs(in folder: URL) throws -> URL {
        let stubs = folder.appendingPathComponent("stubs")
        try FileManager.default.createDirectory(at: stubs, withIntermediateDirectories: true)
        let calls = folder.appendingPathComponent("calls.txt").path
        for name in ["pkill", "pgrep", "swift", "codesign", "security", "open"] {
            let exitCode = name == "pgrep" ? "1" : "0"
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
        environment.removeValue(forKey: "BUGBEAR_APP_BUILT")
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

    func testPerfUsesTheSameAutomationBuildAsTheOthers() throws {
        // perf.sh sources test-app.sh, which exports BUGBEAR_AUTOMATION=1 for the build.
        XCTAssertTrue(try read("scripts/test/perf.sh").contains("scripts/test/lib/test-app.sh"))
        XCTAssertTrue(try read("scripts/test/lib/test-app.sh").contains("export BUGBEAR_AUTOMATION=1"))
    }

    func testAllBuildsOnceBeforeTheE2eSuites() throws {
        let text = try read("scripts/test/all.sh")
        let build = try XCTUnwrap(text.range(of: "run_suite app-build build_test_app_once"))
        let check = try XCTUnwrap(text.range(of: "case \"${RESULTS[${#RESULTS[@]} - 1]}\" in"))
        let flag = try XCTUnwrap(text.range(of: "export BUGBEAR_APP_BUILT=1"))
        let first = try XCTUnwrap(text.range(of: "run_suite e2e scripts/test/e2e.sh"))
        let skipped = try XCTUnwrap(text.range(of: "not run: app-build failed"))
        XCTAssertTrue(build.lowerBound < check.lowerBound && check.lowerBound < flag.lowerBound && flag.lowerBound < first.lowerBound)
        XCTAssertTrue(first.lowerBound < skipped.lowerBound, "the e2e suites run only in the ok branch, a failed build is reported")
        XCTAssertTrue(text.contains("BUGBEAR_AUTOMATION=1 scripts/build-app.sh"))
    }

    func testBuiltAppIsReusedWithoutBuilding() throws {
        let folder = try makeFolder()
        let fakeRoot = folder.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: fakeRoot.appendingPathComponent("scripts/lib"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeRoot.appendingPathComponent("Sources/BugbearCore/Support"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("scripts/lib/app-name.sh"), to: fakeRoot.appendingPathComponent("scripts/lib/app-name.sh"))
        try FileManager.default.copyItem(
            at: root.appendingPathComponent("Sources/BugbearCore/Support/AppInfo.swift"),
            to: fakeRoot.appendingPathComponent("Sources/BugbearCore/Support/AppInfo.swift"))
        let marker = folder.appendingPathComponent("built.txt").path
        let build = "#!/bin/bash\necho built >> \"\(marker)\"\n"
        let buildScript = fakeRoot.appendingPathComponent("scripts/build-app.sh")
        try build.write(to: buildScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: buildScript.path)
        let source = "ROOT=\"\(fakeRoot.path)\"; source \"\(root.path)/scripts/test/lib/test-app.sh\"; "

        // Built by all.sh but missing: stop with a clear message, build nothing.
        var result = try bash(source + "build_test_app", environment: ["BUGBEAR_APP_BUILT": "1"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("build/\(try XCTUnwrap(bashAppName(source))).app missing: run scripts/build-app.sh first"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))

        // Built and present: used as it is.
        let appName = try XCTUnwrap(bashAppName(source))
        try FileManager.default.createDirectory(at: fakeRoot.appendingPathComponent("build/\(appName).app"), withIntermediateDirectories: true)
        // An app without the automation marker (old or release build) is not reused.
        result = try bash(source + "build_test_app", environment: ["BUGBEAR_APP_BUILT": "1"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("not a build with automation"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
        FileManager.default.createFile(atPath: fakeRoot.appendingPathComponent("build/.automation-build").path, contents: Data())
        result = try bash(source + "build_test_app", environment: ["BUGBEAR_APP_BUILT": "1"])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker), "no build when BUGBEAR_APP_BUILT=1")

        // Without the variable the script builds, as before.
        result = try bash(source + "build_test_app", environment: [:])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker), "builds without BUGBEAR_APP_BUILT")
    }

    private func bashAppName(_ source: String) throws -> String? {
        let result = try bash(source + "echo \"name=$APP_NAME\"", environment: [:])
        let line = result.output.split(separator: "\n").first { $0.hasPrefix("name=") }
        return line.map { String($0.dropFirst(5)) }
    }

    // MARK: build-app.sh --install-only

    private func makeApp(at url: URL, bundleId: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleExecutable": "Other", "CFBundleIdentifier": bundleId]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
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
        let result = try bash(
            "\"\(root.path)/scripts/build-app.sh\" --install-only",
            environment: [
                "BUGBEAR_BUILD_DIR": buildDir.path,
                "BUGBEAR_INSTALL_DIR": installDir.path,
                "BUGBEAR_KEEP_PERMISSIONS": "1",
                "BUGBEAR_NO_OPEN": "1",
            ],
            path: stubs)
        XCTAssertEqual(result.status, 0, result.output)
        let installedPlist = installDir.appendingPathComponent("\(appName).app/Contents/Info.plist")
        let info = try XCTUnwrap(NSDictionary(contentsOf: installedPlist))
        XCTAssertTrue((info["CFBundleIdentifier"] as? String ?? "").hasPrefix("test.built."), "the built app replaced the old copy: \(result.output)")
        let calls = (try? String(contentsOf: folder.appendingPathComponent("calls.txt"), encoding: .utf8)) ?? ""
        XCTAssertFalse(calls.contains("swift "), "no swift build: \(calls)")
        XCTAssertFalse(calls.contains("codesign"), "no signing: \(calls)")
        XCTAssertFalse(calls.contains("security"), "no keychain query: \(calls)")
        XCTAssertFalse(calls.contains("open"), "BUGBEAR_NO_OPEN is honored: \(calls)")
    }

    func testInstallOnlyStopsWhenThereIsNoBuild() throws {
        let folder = try makeFolder()
        let stubs = try makeStubs(in: folder)
        let installDir = folder.appendingPathComponent("apps")
        let result = try bash(
            "\"\(root.path)/scripts/build-app.sh\" --install-only",
            environment: [
                "BUGBEAR_BUILD_DIR": folder.appendingPathComponent("empty").path,
                "BUGBEAR_INSTALL_DIR": installDir.path,
                "BUGBEAR_KEEP_PERMISSIONS": "1",
                "BUGBEAR_NO_OPEN": "1",
            ],
            path: stubs)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("is missing: run scripts/build-app.sh first"), result.output)
        let calls = (try? String(contentsOf: folder.appendingPathComponent("calls.txt"), encoding: .utf8)) ?? ""
        XCTAssertFalse(calls.contains("swift "), calls)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path), "nothing installed")
    }

    func testBuildScriptWritesTheAutomationMarkerOnlyForAutomationBuilds() throws {
        let text = try read("scripts/build-app.sh")
        XCTAssertTrue(text.contains("rm -f \"$BUILD_DIR/.automation-build\""), "removed at the start of every build")
        XCTAssertTrue(text.contains("touch \"$BUILD_DIR/.automation-build\""))
        let touch = try XCTUnwrap(text.range(of: "touch \"$BUILD_DIR/.automation-build\""))
        let guardLine = try XCTUnwrap(text.range(of: "if [ \"${BUGBEAR_AUTOMATION:-}\" = \"1\" ]; then\n        touch"))
        XCTAssertTrue(guardLine.upperBound <= touch.upperBound)
    }

    func testFeaturesWelcomeGuideUsesInstallOnly() throws {
        let text = try read("scripts/test/e2e-features.sh")
        XCTAssertEqual(text.components(separatedBy: "scripts/build-app.sh --install-only").count - 1, 2)
        XCTAssertFalse(text.contains("scripts/build-app.sh --install >"))
    }
}
