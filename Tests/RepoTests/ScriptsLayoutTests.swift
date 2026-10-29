import Foundation
import XCTest

/// The scripts sit in folders (docs/development.md, "Project layout"). Copies that are already
/// installed run some of them by path, so those never move, and every path the repository names
/// has to point at a file that is there.
final class ScriptsLayoutTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    /// The install command downloads install.sh, Update now runs update.sh, an older update.sh calls
    /// build-app.sh after the pull, and the uninstall command downloads uninstall.sh.
    func testThePathsInstalledCopiesUseStayInPlace() throws {
        for path in ["scripts/install.sh", "scripts/update.sh", "scripts/uninstall.sh", "scripts/build-app.sh"] {
            let file = root.appendingPathComponent(path).path
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: file), "\(path) must stay where it is and be executable")
        }
        let update = try String(contentsOf: root.appendingPathComponent("scripts/update.sh"), encoding: .utf8)
        XCTAssertTrue(update.contains("scripts/build-app.sh"), "update.sh builds with scripts/build-app.sh")
    }

    /// Scripts people run are executable; the ones in a lib/ folder are only sourced.
    func testRunnableScriptsAreExecutable() throws {
        let scripts = try files(in: "scripts").filter { $0.hasSuffix(".sh") }
        XCTAssertFalse(scripts.isEmpty)
        for path in scripts {
            if path.contains("/lib/") {
                continue
            }
            let file = root.appendingPathComponent(path).path
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: file), "\(path) is not executable")
        }
    }

    /// A moved or renamed script leaves no stale path behind in the docs, the scripts, CI or code comments.
    func testEveryScriptPathNamedInTheRepositoryExists() throws {
        let pattern = try NSRegularExpression(pattern: "scripts/[A-Za-z0-9_./-]*[A-Za-z0-9_]")
        var checked = 0
        var missing: [String] = []
        for path in try trackedTextFiles() {
            // Release notes of past versions name the paths of their time.
            if path.hasSuffix("WhatsNewCatalog.swift") {
                continue
            }
            guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
                continue
            }
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let found = Range(match.range, in: text) else {
                    continue
                }
                let named = String(text[found])
                checked += 1
                if !FileManager.default.fileExists(atPath: root.appendingPathComponent(named).path) {
                    missing.append("\(path): \(named)")
                }
            }
        }
        XCTAssertGreaterThan(checked, 50, "the search found the script paths")
        XCTAssertEqual(missing, [], "paths to scripts that are not there")
    }

    private func files(in folder: String) throws -> [String] {
        let base = root.appendingPathComponent(folder)
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            return []
        }
        var found: [String] = []
        for case let relative as String in walker {
            found.append("\(folder)/\(relative)")
        }
        return found
    }

    private func trackedTextFiles() throws -> [String] {
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
            let path = String(line)
            let textEndings = [".md", ".sh", ".py", ".yml", ".swift", ".strings", ".plist", ".example", "Makefile", ".shellcheckrc", ".txt"]
            for ending in textEndings where path.hasSuffix(ending) {
                paths.append(path)
                break
            }
        }
        return paths
    }
}
