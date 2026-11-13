import Foundation
import XCTest

/// macOS writes the menu bar item's `isInserted` binding back on every update of the app's scene.
/// A plain binding passes a write of the same value on, and on a Mac with Swift before 6.2 that
/// starts the next scene update: the app spins. The binding has to drop such writes.
final class MenuBarItemBindingTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testTheSceneUsesTheBindingThatDropsEqualWrites() throws {
        let scene = try source("Sources/App/App/main.swift")
        XCTAssertTrue(scene.contains("MenuBarExtra(isInserted: state.menuBarItemInserted)"), "main.swift: MenuBarExtra takes state.menuBarItemInserted")
        XCTAssertFalse(scene.contains("isInserted: Binding("), "main.swift: no plain Binding for isInserted")
    }

    func testTheBindingIsForChangesOnly() throws {
        let state = try source("Sources/App/App/AppState+MenuBarItem.swift")
        XCTAssertTrue(state.contains("Binding.changesOnly(get: { self.showsMenuBarItem }"), "menuBarItemInserted is made with Binding.changesOnly")
    }

    /// Without the watchdog running, the scripts' check for stalls passes on nothing.
    func testTheWatchdogStartsAtLaunch() throws {
        let state = try source("Sources/App/App/AppState.swift")
        XCTAssertTrue(state.contains("MainThreadWatchdog.start()"), "AppState.launch starts the main thread watchdog")
    }
}
