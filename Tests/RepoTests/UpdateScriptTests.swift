import AppCore
import Foundation
import XCTest

/// scripts/update.sh with a pretend git, build and app: an update from this folder's own build
/// relaunches it, it never deletes the fresh build. Nothing touches the real app or repository.
final class UpdateScriptTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
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

    private var appName: String {
        get throws {
            try String(contentsOf: root.appendingPathComponent("Sources/AppCore/Support/AppInfo.swift"), encoding: .utf8)
                .components(separatedBy: "static let name = \"")[1].components(separatedBy: "\"")[0]
        }
    }

    /// `built`: has the keys every build-app.sh build writes.
    private func makeApp(at url: URL, bundleId: String, executable: String = AppInfo.name, built: Bool = true) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: String] = ["CFBundleExecutable": executable, "CFBundleIdentifier": bundleId]
        if built {
            info["SourcePath"] = "/somewhere/source"
        }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    /// Runs the repository's update.sh copied into `folder/repo` with a pretend git and build, through
    /// `folder/link` (a symlink to the repo), for `target`. Returns how it ended and the stubs' calls.
    /// `codesignFails`: the fresh build fails the signature check.
    private func update(in folder: URL, target: URL, codesignFails: Bool = false) throws -> (status: Int32, output: String, calls: String) {
        let repo = folder.appendingPathComponent("repo")
        let paths = ["scripts/update.sh", "scripts/lib/app-name.sh", "scripts/lib/permissions.sh", "scripts/lib/replace-app.sh",
                     "Sources/AppCore/Support/AppInfo.swift"]
        for path in paths {
            let target = repo.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: root.appendingPathComponent(path), to: target)
        }
        // The build writes the app with a file in it, as build-app.sh would, and an executable that
        // reports the version the plist has.
        let plist = "<?xml version=\\\"1.0\\\" encoding=\\\"UTF-8\\\"?><plist version=\\\"1.0\\\"><dict>"
            + "<key>CFBundleExecutable</key><string>$APP_NAME</string><key>CFBundleIdentifier</key><string>test.built</string>"
            + "<key>CFBundleShortVersionString</key><string>9.9.9</string>"
            + "<key>SourcePath</key><string>/somewhere</string></dict></plist>"
        let build = "#!/bin/bash\nsource scripts/lib/app-name.sh\nmkdir -p \"build/$APP_NAME.app/Contents/MacOS\"\n"
            + "echo fresh > \"build/$APP_NAME.app/fresh\"\necho \"\(plist)\" > \"build/$APP_NAME.app/Contents/Info.plist\"\n"
            + "printf '#!/bin/bash\\necho 9.9.9\\n' > \"build/$APP_NAME.app/Contents/MacOS/$APP_NAME\"\n"
            + "chmod +x \"build/$APP_NAME.app/Contents/MacOS/$APP_NAME\"\n"
        try write(build, to: repo.appendingPathComponent("scripts/build-app.sh"), executable: true)
        let stubs = folder.appendingPathComponent("stubs")
        let calls = folder.appendingPathComponent("calls.txt").path
        for name in ["git", "pkill", "pgrep", "open", "codesign"] {
            var body = "#!/bin/bash\necho \"\(name) $*\" >> \"\(calls)\"\n"
            if name == "git" {
                body += "if [ \"$1\" = rev-parse ]; then echo main; fi\n"
            }
            if name == "pgrep" || (name == "codesign" && codesignFails) {
                body += "exit 1\n"
            }
            try write(body, to: stubs.appendingPathComponent(name), executable: true)
        }
        let link = folder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [link.appendingPathComponent("scripts/update.sh").path, target.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = stubs.path + ":" + (environment["PATH"] ?? "")
        environment["HOME"] = folder.appendingPathComponent("home").path
        let temporary = folder.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        environment["TMPDIR"] = temporary.path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let printed = String(decoding: data, as: UTF8.self)
        let recorded = (try? String(contentsOf: URL(fileURLWithPath: calls), encoding: .utf8)) ?? ""
        return (process.terminationStatus, printed, recorded)
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// The same build reached by another path (a symlinked folder) is still the fresh build.
    func testUpdatingTheBuildInPlaceKeepsIt() throws {
        let folder = try makeFolder()
        let built = folder.appendingPathComponent("repo/build/\(try appName).app")
        let result = try update(in: folder, target: built)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: built.appendingPathComponent("fresh").path), "the fresh build stays: \(result.output)")
        XCTAssertFalse(result.output.contains("==> replacing"), result.output)
        XCTAssertTrue(result.calls.contains("open \(built.path)"), "the build is opened: \(result.calls)")
    }

    /// Another app at the path the update was given is never deleted: the update stops before quitting
    /// anything and says why.
    func testUpdateStopsAtAnAppThatIsNotOurs() throws {
        let cases: [(id: String, executable: String, built: Bool)] = [
            ("com.example.other", "Other", false),
            ("com.example.other", AppInfo.name, false),
        ]
        for item in cases {
            let folder = try makeFolder()
            let target = folder.appendingPathComponent("apps/\(try appName).app")
            try makeApp(at: target, bundleId: item.id, executable: item.executable, built: item.built)
            let result = try update(in: folder, target: target)
            XCTAssertNotEqual(result.status, 0, "\(item): \(result.output)")
            XCTAssertTrue(result.output.contains("is not a \(AppInfo.name) build"), "\(item): \(result.output)")
            let info = try XCTUnwrap(NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist")))
            XCTAssertEqual(info["CFBundleIdentifier"] as? String, item.id, "\(item): the other app stays")
            XCTAssertFalse(result.calls.contains("pkill"), "\(item): stops before quitting anything: \(result.calls)")
        }
    }

    /// An installed copy elsewhere is replaced by the fresh build.
    func testUpdateReplacesAnInstalledCopy() throws {
        let folder = try makeFolder()
        let target = folder.appendingPathComponent("apps/\(try appName).app")
        try makeApp(at: target, bundleId: "test.old")
        let result = try update(in: folder, target: target)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("fresh").path), result.output)
    }

    /// A fresh build that fails its check never replaces the installed copy; the old one runs again.
    func testUpdateKeepsTheInstalledCopyWhenTheBuildFailsItsCheck() throws {
        let folder = try makeFolder()
        let target = folder.appendingPathComponent("apps/\(try appName).app")
        try makeApp(at: target, bundleId: "test.old")
        let result = try update(in: folder, target: target, codesignFails: true)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("signature check"), result.output)
        let info = try XCTUnwrap(NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist")))
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "test.old", "the installed copy stays: \(result.output)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("fresh").path), result.output)
        XCTAssertTrue(result.calls.contains("open \(target.path)"), "the old copy is started again: \(result.calls)")
        XCTAssertFalse(result.output.contains("==> updated"), result.output)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("tmp").path)
        XCTAssertEqual(leftovers, [], "no temporary copy left")
    }

    /// The fresh build replaces the copy and the old one leaves no copy behind.
    func testUpdateLeavesNoTemporaryCopy() throws {
        let folder = try makeFolder()
        let target = folder.appendingPathComponent("apps/\(try appName).app")
        try makeApp(at: target, bundleId: "test.old")
        let result = try update(in: folder, target: target)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.calls.contains("codesign --verify"), "the build is checked: \(result.calls)")
        XCTAssertTrue(result.calls.contains("open \(target.path)"), result.calls)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("tmp").path)
        XCTAssertEqual(leftovers, [], "no temporary copy left")
        let apps = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("apps").path)
        XCTAssertEqual(apps, ["\(try appName).app"], "no second copy beside it")
    }
}
