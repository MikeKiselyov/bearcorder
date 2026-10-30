import AppCore
import XCTest

/// "Quit & Reopen" in System Settings only quits; the app has to open itself again.
final class QuitRequestTests: XCTestCase {
    func testQuitFromThePrivacyPaneReopens() {
        // What macOS 26 sends after Screen Recording is switched on.
        XCTAssertTrue(QuitRequest.comesFromSystemSettings(senderBundleID: "com.apple.settings.PrivacySecurity.extension"))
    }

    func testQuitFromSystemSettingsReopens() {
        XCTAssertTrue(QuitRequest.comesFromSystemSettings(senderBundleID: "com.apple.systempreferences"))
    }

    func testOtherQuitsDoNot() {
        XCTAssertFalse(QuitRequest.comesFromSystemSettings(senderBundleID: nil), "the app's own Quit")
        XCTAssertFalse(QuitRequest.comesFromSystemSettings(senderBundleID: "com.apple.loginwindow"), "logging out")
        XCTAssertFalse(QuitRequest.comesFromSystemSettings(senderBundleID: "com.apple.dock"), "Quit from the Dock")
        XCTAssertFalse(QuitRequest.comesFromSystemSettings(senderBundleID: "com.apple.settingsfake"), "only the settings panes")
    }
}
