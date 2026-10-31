import AppCore
import Foundation
import XCTest

/// The name lives in AppInfo.name, so renaming the app is scripts/dev/rename-app.sh and nothing else:
/// no code or script file says the name (or its slug) itself. Text for people (docs, README, issue
/// forms, .env.example, What's New) says it, and rename-app.sh rewrites it; the installer and
/// uninstaller keep their own copies, which AppNameTests compares with AppInfo.
final class AppNameInOnePlaceTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    /// Code files that may say the name.
    private let allowed = [
        "Sources/AppCore/Support/AppInfo.swift",
        // They run without the source: their copies are checked by AppNameTests and rewritten by rename-app.sh.
        "scripts/install.sh",
        "scripts/uninstall.sh",
        // The bundle id of debug runs, linked into the binary; rewritten by rename-app.sh.
        "Packaging/Debug-Info.plist",
        // Release notes say what the app was called at the time.
        "Sources/AppCore/Support/WhatsNewCatalog.swift",
    ]

    func testCodeAndScriptsTakeTheNameFromAppInfo() throws {
        let codeEndings = [".swift", ".sh", ".py", ".plist", "Makefile"]
        var checked = 0
        var found: [String] = []
        for path in try trackedFiles() {
            if allowed.contains(path) {
                continue
            }
            var isCode = false
            for ending in codeEndings where path.hasSuffix(ending) {
                isCode = true
            }
            // The CI workflow is code; the issue forms are text for people.
            if path.hasPrefix(".github/workflows/") {
                isCode = true
            }
            if !isCode {
                continue
            }
            guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
                continue
            }
            checked += 1
            let lowered = text.lowercased()
            if lowered.contains(AppInfo.name.lowercased()) || lowered.contains(AppInfo.slug) {
                found.append(path)
            }
        }
        XCTAssertGreaterThan(checked, 100, "the search found the code")
        XCTAssertEqual(found, [], "code that says \(AppInfo.name) itself: use AppInfo.name (Swift) or APP_NAME (scripts/lib/app-name.sh)")
    }

    /// Text for people that scripts/dev/rename-app.sh rewrites.
    private func isRewrittenByRenameScript(_ path: String) -> Bool {
        if ["README.md", "CONTRIBUTING.md", ".env.example", "scripts/install.sh", "scripts/uninstall.sh", "Sources/AppCore/Support/AppInfo.swift", "Packaging/Debug-Info.plist"].contains(path) {
            return true
        }
        let parts = path.split(separator: "/")
        if parts.count == 2 && parts[0] == "docs" {
            for ending in [".md", ".html", ".yml", ".txt", ".xml"] where path.hasSuffix(ending) {
                return true
            }
        }
        if path.hasPrefix(".github/ISSUE_TEMPLATE/") && path.hasSuffix(".yml") && parts.count == 3 {
            return true
        }
        return false
    }

    /// Every file that says the name is one rename-app.sh rewrites, an allowed code file, or a picture
    /// (made again with scripts/dev/readme-media.sh). Anything else (a .strings table, a test, a
    /// .txt list) would keep the old name after a rename.
    func testEveryFileWithTheNameIsRenamedByTheScript() throws {
        let script = try String(contentsOf: root.appendingPathComponent("scripts/dev/rename-app.sh"), encoding: .utf8)
        for named in ["\"README.md\"", "\"CONTRIBUTING.md\"", "\".env.example\"", "(root / \"docs\").glob(\"*.md\")", "(root / \".github/ISSUE_TEMPLATE\").glob(\"*.yml\")", "for site_pattern in [\"*.html\", \"*.yml\", \"*.txt\", \"*.xml\"]:", "[\"install.sh\", \"uninstall.sh\"]", "root / \"Packaging/Debug-Info.plist\""] {
            XCTAssertTrue(script.contains(named), "rename-app.sh no longer rewrites \(named)")
        }
        let pictureEndings = [".png", ".jpg", ".gif"]
        var found: [String] = []
        for path in try trackedFiles() {
            if allowed.contains(path) || isRewrittenByRenameScript(path) {
                continue
            }
            var isPicture = false
            for ending in pictureEndings where path.hasSuffix(ending) {
                isPicture = true
            }
            if isPicture {
                continue
            }
            guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(path).path) else {
                continue
            }
            let lowered = String(decoding: data, as: UTF8.self).lowercased()
            if lowered.contains(AppInfo.name.lowercased()) || lowered.contains(AppInfo.slug) {
                found.append(path)
            }
        }
        XCTAssertEqual(found, [], "files that say \(AppInfo.name) but rename-app.sh does not rewrite: insert AppInfo.name (%@ in .strings) or add the file to the script")
    }

    private func trackedFiles() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "ls-files"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let listing = String(decoding: data, as: UTF8.self)
        var paths: [String] = []
        for line in listing.split(separator: "\n") {
            paths.append(String(line))
        }
        return paths
    }
}
