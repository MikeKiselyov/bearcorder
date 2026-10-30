import AppCore
import Foundation
import XCTest

/// The app's name lives in AppInfo.name; the scripts and the installer must show the same one, with
/// the repository, bundle id and source folder that follow from it.
final class AppNameTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func read(_ file: String) throws -> String {
        return try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
    }

    func testNameIsSet() {
        XCTAssertFalse(AppInfo.name.isEmpty)
        XCTAssertEqual(AppInfo.slug, AppInfo.name.lowercased().replacingOccurrences(of: " ", with: "-"))
        XCTAssertEqual(AppInfo.repository, "MikeKiselyov/\(AppInfo.slug)")
        XCTAssertEqual(AppInfo.defaultBundleId, "io.github.\(AppInfo.slug).app")
        XCTAssertEqual(AppInfo.sourceFolder, ".\(AppInfo.slug)")
    }

    func testScriptsReadTheSameName() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "source scripts/lib/app-name.sh && printf '%s|%s|%s' \"$APP_NAME\" \"$APP_SLUG\" \"$DEFAULT_BUNDLE_ID\""]
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let printed = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(printed, "\(AppInfo.name)|\(AppInfo.slug)|\(AppInfo.defaultBundleId)")
    }

    /// install.sh runs before the source is downloaded, so it keeps its own copies.
    func testInstallerShowsTheSameName() throws {
        let installer = try read("scripts/install.sh")
        XCTAssertTrue(installer.contains("\nAPP_NAME=\"\(AppInfo.name)\"\n"), "scripts/install.sh keeps its own copy of the name: make it AppInfo.name")
        XCTAssertTrue(installer.contains("\nREPO_URL=\"${APP_REPO:-https://github.com/\(AppInfo.repository).git}\"\n"), "scripts/install.sh downloads AppInfo.repository")
        XCTAssertTrue(installer.contains("\nSOURCE_DIR=\"${APP_SOURCE_DIR:-$HOME/\(AppInfo.sourceFolder)}\"\n"), "scripts/install.sh keeps the source in AppInfo.sourceFolder")
        XCTAssertTrue(installer.contains("raw.githubusercontent.com/\(AppInfo.repository)/main/scripts/install.sh"), "the install command in its header")
    }

    /// uninstall.sh runs without the source too.
    func testUninstallerShowsTheSameNames() throws {
        let uninstaller = try read("scripts/uninstall.sh")
        XCTAssertTrue(uninstaller.contains("\nAPP_NAME=\"\(AppInfo.name)\"\n"), "scripts/uninstall.sh keeps its own copy of the name: make it AppInfo.name")
        XCTAssertTrue(uninstaller.contains("\nDEFAULT_BUNDLE_ID=\"\(AppInfo.defaultBundleId)\"\n"), "scripts/uninstall.sh finds the installer's copies by AppInfo.defaultBundleId")
        XCTAssertTrue(uninstaller.contains("\nSOURCE_DIR=\"${APP_SOURCE_DIR:-$HOME/\(AppInfo.sourceFolder)}\"\n"), "scripts/uninstall.sh removes the installer's source folder")
        XCTAssertTrue(uninstaller.contains("\nFEEDBACK_URL=\"https://github.com/\(AppInfo.repository)/issues/new?template=uninstall_feedback.yml\"\n"), "scripts/uninstall.sh opens AppInfo.repository")
    }

    /// Debug runs of .build/debug/App keep their settings under an id of their own, and the
    /// uninstaller removes them.
    func testDebugRunsHaveTheAppsDebugId() throws {
        let debugId = "io.github.\(AppInfo.slug).debug"
        let plist = try XCTUnwrap(NSDictionary(contentsOf: root.appendingPathComponent("Packaging/Debug-Info.plist")))
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, debugId)
        let package = try read("Package.swift")
        XCTAssertTrue(package.contains("\"__info_plist\", \"-Xlinker\", Context.packageDirectory + \"/Packaging/Debug-Info.plist\"], .when(configuration: .debug))"), "Package.swift links it into debug builds only")
        let uninstaller = try read("scripts/uninstall.sh")
        XCTAssertTrue(uninstaller.contains("rm -f \"$HOME/Library/Preferences/\(debugId).plist\""), "scripts/uninstall.sh removes the debug runs' settings")
    }

    func testDocsShowTheSameName() throws {
        let readme = try read("README.md")
        XCTAssertTrue(readme.contains("<h1 align=\"center\">\(AppInfo.name)</h1>"), "README.md shows another name: run scripts/dev/rename-app.sh")
        XCTAssertTrue(readme.contains("raw.githubusercontent.com/\(AppInfo.repository)/main/scripts/install.sh"), "README.md installs from another repository: run scripts/dev/rename-app.sh")
        let uninstall = try read("docs/uninstall.md")
        XCTAssertTrue(uninstall.contains("/Applications/\(AppInfo.name).app"), "docs/uninstall.md shows another name: run scripts/dev/rename-app.sh")
    }
}
