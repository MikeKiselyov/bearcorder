import BugbearCore
import Foundation
import XCTest

/// The app's name lives in AppInfo.name; the scripts and the installer must show the same one.
final class AppNameTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    func testNameIsSet() {
        XCTAssertFalse(AppInfo.name.isEmpty)
        XCTAssertFalse(AppInfo.storageName.isEmpty)
    }

    func testScriptsReadTheSameName() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "source scripts/lib/app-name.sh && printf '%s' \"$APP_NAME\""]
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let name = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(name, AppInfo.name)
    }

    func testInstallerShowsTheSameName() throws {
        let installer = try String(contentsOf: root.appendingPathComponent("scripts/install.sh"), encoding: .utf8)
        XCTAssertTrue(installer.contains("\nAPP_NAME=\"\(AppInfo.name)\"\n"), "scripts/install.sh keeps its own copy of the name: make it AppInfo.name")
    }

    func testUninstallerShowsTheSameNames() throws {
        let uninstaller = try String(contentsOf: root.appendingPathComponent("scripts/uninstall.sh"), encoding: .utf8)
        XCTAssertTrue(uninstaller.contains("\nAPP_NAME=\"\(AppInfo.name)\"\n"), "scripts/uninstall.sh keeps its own copy of the name: make it AppInfo.name")
        XCTAssertTrue(uninstaller.contains("\nSTORAGE_NAME=\"\(AppInfo.storageName)\"\n"), "scripts/uninstall.sh keeps its own copy of the folders' name: make it AppInfo.storageName")
    }

    func testDocsShowTheSameName() throws {
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.contains("<h1 align=\"center\">\(AppInfo.name)</h1>"), "README.md shows another name: run scripts/dev/rename-app.sh")
        let uninstall = try String(contentsOf: root.appendingPathComponent("docs/uninstall.md"), encoding: .utf8)
        XCTAssertTrue(uninstall.contains("/Applications/\(AppInfo.name).app"), "docs/uninstall.md shows another name: run scripts/dev/rename-app.sh")
    }

    /// Runs scripts/dev/rename-app.sh on a copy of the files it changes and returns that copy.
    private func renamedCopy(to newName: String) throws -> URL {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("rename-\(UUID().uuidString)")
        for file in renamedFiles {
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

    private let renamedFiles = ["README.md", "docs/uninstall.md", "docs/development.md", "Sources/BugbearCore/Support/AppInfo.swift", "scripts/install.sh", "scripts/uninstall.sh"]

    private func read(_ file: String, in folder: URL) throws -> String {
        return try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
    }

    /// The rename script changes the name people see and keeps the folders with their captures.
    func testRenameScriptKeepsStorageFolders() throws {
        let copy = try renamedCopy(to: "Bug Hunter")
        defer { try? FileManager.default.removeItem(at: copy) }

        let appInfo = try read("Sources/BugbearCore/Support/AppInfo.swift", in: copy)
        XCTAssertTrue(appInfo.contains("static let name = \"Bug Hunter\""))
        XCTAssertTrue(appInfo.contains("static let storageName = \"\(AppInfo.storageName)\""))
        let installer = try read("scripts/install.sh", in: copy)
        XCTAssertTrue(installer.contains("\nAPP_NAME=\"Bug Hunter\"\n"))
        let uninstaller = try read("scripts/uninstall.sh", in: copy)
        XCTAssertTrue(uninstaller.contains("\nAPP_NAME=\"Bug Hunter\"\n"))
        XCTAssertTrue(uninstaller.contains("\nSTORAGE_NAME=\"\(AppInfo.storageName)\"\n"), "the uninstaller still finds the folders")
        let readme = try read("README.md", in: copy)
        XCTAssertTrue(readme.contains("<h1 align=\"center\">Bug Hunter</h1>"))
        let uninstall = try read("docs/uninstall.md", in: copy)
        XCTAssertTrue(uninstall.contains("/Applications/Bug Hunter.app"))
        XCTAssertTrue(uninstall.contains("## Where Bug Hunter keeps things"))
        XCTAssertTrue(uninstall.contains("Application Support/\(AppInfo.storageName)/Captures/"), "captures stay where they are")
        XCTAssertTrue(uninstall.contains("Logs/\(AppInfo.storageName)/"), "logs stay where they are")
        let development = try read("docs/development.md", in: copy)
        XCTAssertTrue(development.contains("uninstall.md#where-bug-hunter-keeps-things"), "the link follows the renamed heading")
        XCTAssertTrue(development.contains(".build/debug/Bugbear --self-test"), "the executable keeps its name")
    }

    /// A new name with the old one in it is not renamed twice.
    func testRenameScriptRenamesOnce() throws {
        let copy = try renamedCopy(to: "\(AppInfo.name) Pro")
        defer { try? FileManager.default.removeItem(at: copy) }
        let uninstall = try read("docs/uninstall.md", in: copy)
        XCTAssertTrue(uninstall.contains("/Applications/\(AppInfo.name) Pro.app"))
        XCTAssertFalse(uninstall.contains("Pro Pro"))
        let readme = try read("README.md", in: copy)
        XCTAssertFalse(readme.contains("Pro Pro"))
    }
}
