import Foundation
import XCTest

/// Packaging/Info.plist is the app's Info.plist; scripts/build-app.sh fills in what depends on the
/// build. A key left empty would ship empty (no version, no permission text), so every empty value
/// in the file must be filled by the script, and the keys the app reads must be there.
final class PackagingTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Packaging/Info.plist"))
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(object as? [String: Any])
    }

    func testTheKeysTheAppNeedsAreThere() throws {
        let plist = try infoPlist()
        let needed = ["CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString", "CFBundleVersion", "LSUIElement", "LSMinimumSystemVersion", "NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSAppleEventsUsageDescription", "SourceCommit", "SourcePath", "SourceRepository", "SourceBranch"]
        for key in needed {
            XCTAssertNotNil(plist[key], "Packaging/Info.plist has no \(key)")
        }
        // The executable takes the app's name, so the process and its crash reports have it.
        let script = try String(contentsOf: root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("set_plist CFBundleExecutable \"$APP_NAME\""), "build-app.sh names the executable")
        XCTAssertTrue(script.contains("cp \"$BINARY\" \"$APP_DIR/Contents/MacOS/$APP_NAME\""), "and copies it under that name")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true, "a menu bar app without a Dock icon")
    }

    func testTheBuildScriptFillsEveryEmptyValue() throws {
        let plist = try infoPlist()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        var empty: [String] = []
        for (key, value) in plist {
            if let text = value as? String, text.isEmpty {
                empty.append(key)
            }
        }
        XCTAssertFalse(empty.isEmpty)
        for key in empty.sorted() {
            XCTAssertTrue(script.contains("set_plist \(key) "), "scripts/build-app.sh does not fill \(key)")
        }
    }
}
