import AppCore
import Foundation
import XCTest

/// scripts/dev/rename-app.sh, run on a copy of the files it changes: one run is the whole rename.
final class RenameAppTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    /// What the script rewrites, as paths in the repository.
    private func renamedFiles() throws -> [String] {
        var files = ["Sources/AppCore/Support/AppInfo.swift", "scripts/install.sh", "scripts/uninstall.sh", "README.md", "CONTRIBUTING.md", ".env.example", "Packaging/Debug-Info.plist"]
        for folder in ["docs", ".github/ISSUE_TEMPLATE"] {
            let names = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)
            for name in names.sorted() where name.hasSuffix(".md") || name.hasSuffix(".yml") {
                files.append("\(folder)/\(name)")
            }
        }
        // The Pages site next to the docs.
        let docsNames = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("docs").path)
        for name in docsNames.sorted() where name.hasSuffix(".html") || name.hasSuffix(".txt") || name.hasSuffix(".xml") {
            files.append("docs/\(name)")
        }
        return files
    }

    /// Runs scripts/dev/rename-app.sh on a copy of the files it changes and returns that copy.
    private func renamedCopy(to newName: String) throws -> URL {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("rename-\(UUID().uuidString)")
        for file in try renamedFiles() {
            let target = copy.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: root.appendingPathComponent(file), to: target)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/dev/rename-app.sh").path, newName, copy.path]
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return copy
    }

    private func read(_ file: String, in folder: URL) throws -> String {
        return try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
    }

    /// The name, the folders on disk, the repository, the bundle id and the source folder all follow.
    func testRenameScriptRenamesEverywhere() throws {
        let copy = try renamedCopy(to: "Bug Hunter")
        defer { try? FileManager.default.removeItem(at: copy) }

        let appInfo = try read("Sources/AppCore/Support/AppInfo.swift", in: copy)
        XCTAssertTrue(appInfo.contains("static let name = \"Bug Hunter\""))
        let installer = try read("scripts/install.sh", in: copy)
        XCTAssertTrue(installer.contains("\nAPP_NAME=\"Bug Hunter\"\n"))
        XCTAssertTrue(installer.contains("\nREPO_URL=\"${APP_REPO:-https://github.com/MikeKiselyov/bug-hunter.git}\"\n"), installer)
        XCTAssertTrue(installer.contains("\nSOURCE_DIR=\"${APP_SOURCE_DIR:-$HOME/.bug-hunter}\"\n"), installer)
        let uninstaller = try read("scripts/uninstall.sh", in: copy)
        XCTAssertTrue(uninstaller.contains("\nAPP_NAME=\"Bug Hunter\"\n"))
        XCTAssertTrue(uninstaller.contains("\nDEFAULT_BUNDLE_ID=\"io.github.bug-hunter.app\"\n"))
        XCTAssertTrue(uninstaller.contains("https://github.com/MikeKiselyov/bug-hunter/issues/new"))
        let readme = try read("README.md", in: copy)
        XCTAssertTrue(readme.contains("<h1 align=\"center\">Bug Hunter</h1>"))
        XCTAssertTrue(readme.contains("raw.githubusercontent.com/MikeKiselyov/bug-hunter/main/scripts/install.sh"))
        let uninstall = try read("docs/uninstall.md", in: copy)
        XCTAssertTrue(uninstall.contains("/Applications/Bug Hunter.app"))
        XCTAssertTrue(uninstall.contains("## Where Bug Hunter keeps things"))
        XCTAssertTrue(uninstall.contains("Application Support/Bug Hunter/Captures/"), "the folders follow the name")
        let development = try read("docs/development.md", in: copy)
        XCTAssertTrue(development.contains("uninstall.md#where-bug-hunter-keeps-things"), "the link follows the renamed heading")
        XCTAssertTrue(development.contains("`.build/debug/App`"), "the product built from the source keeps its neutral name")
        let debugInfo = try read("Packaging/Debug-Info.plist", in: copy)
        XCTAssertTrue(debugInfo.contains("<string>io.github.bug-hunter.debug</string>"), debugInfo)
        XCTAssertTrue(uninstaller.contains("Preferences/io.github.bug-hunter.debug.plist"), "the uninstaller follows")
        let landing = try read("docs/index.html", in: copy)
        XCTAssertTrue(landing.contains("<title>Bug Hunter - "), "the landing page follows")
        XCTAssertTrue(landing.contains("mikekiselyov.github.io/bug-hunter/"), "the site address follows")
        let example = try read(".env.example", in: copy)
        XCTAssertTrue(example.contains("APP_BUNDLE_ID=io.github.bug-hunter.app"))

        // Nothing of the old name is left in what the script rewrites.
        for file in try renamedFiles() {
            let text = try read(file, in: copy)
            XCTAssertFalse(text.contains(AppInfo.name), "\(file) still says \(AppInfo.name)")
            XCTAssertFalse(text.lowercased().contains(AppInfo.slug), "\(file) still says \(AppInfo.slug)")
        }
    }

    /// A new name with the old one in it is not renamed twice.
    func testRenameScriptRenamesOnce() throws {
        let copy = try renamedCopy(to: "\(AppInfo.name) Pro")
        defer { try? FileManager.default.removeItem(at: copy) }
        let uninstall = try read("docs/uninstall.md", in: copy)
        XCTAssertTrue(uninstall.contains("/Applications/\(AppInfo.name) Pro.app"))
        XCTAssertFalse(uninstall.contains("Pro Pro"))
        XCTAssertFalse(uninstall.contains("pro-pro"))
        let readme = try read("README.md", in: copy)
        XCTAssertFalse(readme.contains("Pro Pro"))
        XCTAssertTrue(readme.contains("MikeKiselyov/\(AppInfo.slug)-pro/"), "the repository follows once")
        XCTAssertFalse(readme.contains("pro-pro"))
    }
}
