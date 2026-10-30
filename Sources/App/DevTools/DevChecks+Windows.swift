// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AVKit
import AppKit
import AppCore
import SwiftUI

@MainActor
extension DevChecks {
    static func checkControlTreeCoordinates() {
        check(ControlTree.whole(12.7) == "12", "control tree: a coordinate is a whole number")
        check(ControlTree.whole(-3.5) == "-3", "control tree: a negative coordinate")
        check(ControlTree.whole(.nan) == "?", "control tree: a NaN coordinate shows as ?")
        check(ControlTree.whole(.infinity) == "?", "control tree: an infinite coordinate shows as ?")
        check(ControlTree.whole(1e300) == "?", "control tree: a coordinate too big for Int shows as ?")
    }

    static func checkRegionPickerButtons() {
        final class Finished {
            var calls = 0
            var rect: CGRect?
        }
        let finished = Finished()
        let view = RegionSelectionView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        view.selection = CGRect(x: 300, y: 200, width: 400, height: 300)
        view.onFinish = { rect in
            finished.calls += 1
            finished.rect = rect
        }
        let window = NSWindow(contentRect: CGRect(x: -3000, y: -3000, width: 1200, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view

        var buttons: [String: DrawnButton] = [:]
        var labels: [String] = []
        for child in view.accessibilityChildren() ?? [] {
            guard let button = child as? DrawnButton else { continue }
            let label = button.accessibilityLabel() ?? ""
            labels.append(label)
            buttons[label] = button
        }
        let expected = ["Size 720p", "Size 1080p", "Size 1440×900", "Size 16:9", "Size 4:3", "Size 1:1", "Size Phone", "Size Full screen", "Cancel", "Record"]
        check(labels == expected, "the area picker names its buttons and size chips", labels.joined(separator: ", "))

        // Cancel is drawn 12 pt under the selection, left of its middle (flipped view, top-left origin).
        if let cancel = buttons["Cancel"] {
            let frame = cancel.accessibilityFrame()
            let expectedFrame = CGRect(x: -3000 + 500 - 114, y: -3000 + 800 - (500 + 12) - 32, width: 110, height: 32)
            check(frame == expectedFrame, "the picker's Cancel sits where it is drawn", "\(frame) vs \(expectedFrame)")
        }

        // VoiceOver keeps its place: asking again gives the same elements.
        let askedAgain = view.accessibilityChildren() ?? []
        var sameElements = askedAgain.count == labels.count
        for child in askedAgain {
            if let button = child as? DrawnButton, buttons[button.accessibilityLabel() ?? ""] !== button {
                sameElements = false
            }
        }
        check(sameElements, "the area picker keeps its accessibility elements between questions")
        let cancelBefore = buttons["Cancel"]?.accessibilityFrame() ?? .zero
        if let cancel = buttons["Cancel"] {
            let found = view.accessibilityHitTest(CGPoint(x: cancelBefore.midX, y: cancelBefore.midY)) as? DrawnButton
            check(found === cancel, "VoiceOver's pointer finds the picker's Cancel", "\(String(describing: found?.accessibilityLabel()))")
        }

        _ = buttons["Size Full screen"]?.accessibilityPerformPress()
        check(view.selection == view.bounds && finished.calls == 0, "pressing a size chip resizes the area", "\(view.selection)")
        // The selection grew, so Cancel moved down to the bottom edge; the same element says so.
        let cancelAfter = buttons["Cancel"]?.accessibilityFrame() ?? .zero
        let expectedAfter = CGRect(x: -3000 + 600 - 114, y: -3000 + 800 - (800 - 44) - 32, width: 110, height: 32)
        check(cancelAfter == expectedAfter, "the picker's Cancel frame follows the selection", "\(cancelAfter) vs \(expectedAfter)")
        _ = buttons["Record"]?.accessibilityPerformPress()
        check(finished.calls == 1 && finished.rect == view.bounds, "pressing Record records the area", "\(finished.calls) \(String(describing: finished.rect))")
        _ = buttons["Cancel"]?.accessibilityPerformPress()
        check(finished.calls == 2 && finished.rect == nil, "pressing Cancel cancels", "\(finished.calls) \(String(describing: finished.rect))")

        // The scrolling screenshot picker has no sizes and says Capture.
        view.showsSizes = false
        view.confirmTitle = "Capture  ↩"
        var scrollingLabels: [String] = []
        for child in view.accessibilityChildren() ?? [] {
            if let button = child as? DrawnButton {
                scrollingLabels.append(button.accessibilityLabel() ?? "")
            }
        }
        check(scrollingLabels == ["Cancel", "Capture"], "the scrolling screenshot picker shows Cancel and Capture", scrollingLabels.joined(separator: ", "))
    }

    /// While tests record, buttons that hand something to macOS only say what they would open.
    static func checkSystemActionsRecord() {
        SystemActions.startRecording()
        SystemActions.open(URL(fileURLWithPath: "/tmp/captures"))
        SystemActions.askPermission("Accessibility") {
            check(false, "a recorded permission prompt is not shown")
        }
        let loginWorked = (try? SystemActions.setOpenAtLogin(true)) != nil
        let chosen = SystemActions.chooseFolder(startingAt: URL(fileURLWithPath: "/tmp"))
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-trash-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: kept.path, contents: Data([1]))
        defer { try? FileManager.default.removeItem(at: kept) }
        let trashWorked = (try? SystemActions.trash(kept)) != nil
        let recorded = SystemActions.recorded
        SystemActions.stopRecording()
        check(recorded == ["open /tmp/captures", "ask Accessibility", "login true", "choose folder /tmp", "trash \(kept.path)"] && loginWorked && chosen == nil, "buttons that open macOS things are recorded in tests, not opened", recorded.joined(separator: " | "))
        check(trashWorked && FileManager.default.fileExists(atPath: kept.path), "a file moved to the Trash in tests stays where it is")
        checkAllowShowsOneWindow()
    }

    /// The grip that moves the recording area sits above the frame, clear of the top handle, and
    /// just inside when the area reaches the top of the screen.
    static func checkAreaGrip() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let size = AreaHandleView.gripSize
        let area = CGRect(x: 400, y: 300, width: 640, height: 360)
        let above = CGRect(origin: RecordingOutline.gripOrigin(area: area, screens: [screen]), size: size)
        let topHandle = CGRect(x: area.midX - AreaHandleView.side / 2, y: area.maxY - AreaHandleView.side / 2, width: AreaHandleView.side, height: AreaHandleView.side)
        check(above.minY > area.maxY && !above.intersects(topHandle) && abs(above.midX - area.midX) < 1, "the grip sits centered above the recording frame, clear of the top handle", "\(above)")
        let atTop = CGRect(x: 400, y: 600, width: 640, height: 382)
        let inside = CGRect(origin: RecordingOutline.gripOrigin(area: atTop, screens: [screen]), size: size)
        check(screen.contains(inside) && inside.maxY < atTop.maxY - AreaHandleView.side / 2, "with no room above, the grip sits inside the frame and stays on the screen", "\(inside)")

        // The picker (flipped, top-left) has the same grip, clear of the size bar at the top.
        let picked = CGRect(x: 400, y: 300, width: 640, height: 360)
        let pickerGrip = RegionSelectionView.gripRect(area: picked, screens: [screen], avoiding: nil, handleSize: 12)
        // A press within reach of the top handle resizes, so the grip stays out of that reach.
        let topReach = CGRect(x: picked.midX - 12, y: picked.minY - 12, width: 24, height: 24)
        check(pickerGrip.maxY < picked.minY && !pickerGrip.intersects(topReach) && abs(pickerGrip.midX - picked.midX) < 1, "the picker's grip sits centered above the area, out of the top handle's reach", "\(pickerGrip)")
        let bar = CGRect(x: 300, y: 42, width: 900, height: 40)
        let underBar = RegionSelectionView.gripRect(area: CGRect(x: 400, y: 100, width: 640, height: 360), screens: [screen], avoiding: bar, handleSize: 12)
        check(!underBar.intersects(bar) && underBar.minY > 100 + 12, "with the size bar in the way, the picker's grip goes inside the area, out of the top handle's reach", "\(underBar)")
        let screenTop = RegionSelectionView.gripRect(area: CGRect(x: 0, y: 0, width: 640, height: 360), screens: [screen], avoiding: nil, handleSize: 12)
        check(screenTop.minY > 12, "at the top of the screen the picker's grip goes inside the area", "\(screenTop)")
        let picker = RegionSelectionView(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        picker.selection = CGRect(x: 400, y: 300, width: 640, height: 0)
        let flat = picker.hasGrip
        picker.selection = picked
        check(!flat && picker.hasGrip, "the picker has a grip only for an area that is there, not a flat one being drawn")
        let scrolling = RegionSelectionView(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        scrolling.showsSizes = false
        check(scrolling.model.barRect == nil, "a picker without the size bar has no bar for the grip to avoid")
        checkAreaAcrossScreens()
    }

    /// The picker's screens share one area: it can lie across two of them.
    private static func checkAreaAcrossScreens() {
        // Desktop points (y down from the top of the first screen): a laptop and a taller monitor to
        // its right whose top is 200 pt higher.
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let monitor = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let model = RegionPickerModel(selection: CGRect(x: 1300, y: 300, width: 640, height: 360), screens: [laptop, monitor])
        let left = RegionSelectionView.screen(of: model, frame: laptop, pixelScale: 2, confirmTitle: "Record", showsSizes: true)
        let right = RegionSelectionView.screen(of: model, frame: monitor, pixelScale: 1, confirmTitle: "Record", showsSizes: false)
        // The grip keeps clear of the size bar that is drawn: the laptop's, not one the monitor never shows.
        check(model.barRect.map { bar in laptop.contains(bar) } == true, "the grip keeps clear of the size bar on the picker's first screen only", "\(String(describing: model.barRect))")
        check(model.clipScale(of: model.selection) == 2 && model.clipScale(of: CGRect(x: 2000, y: 100, width: 100, height: 100)) == 1, "an area's density is the sharpest screen it is on")
        check(model.labelScreen == laptop, "the size label is on the screen with the area's top-left corner")
        check(left.selection == CGRect(x: 1300, y: 300, width: 640, height: 360) && right.selection == CGRect(x: -212, y: 500, width: 640, height: 360), "each screen of the picker shows the same area in its own place", "\(left.selection) / \(right.selection)")
        right.selection = CGRect(x: 100, y: 100, width: 640, height: 360)
        check(model.selection == CGRect(x: 1612, y: -100, width: 640, height: 360) && left.selection.minX == 1612, "an area moved on one screen moves on the others")
        check(model.mainScreen == monitor, "the monitor holds most of an area on it")
        // Above the monitor's part of the desktop that the laptop does not reach, the grip has room.
        check(model.gripRect.maxY < model.selection.minY, "the grip stays above an area near the top of the taller screen", "\(model.gripRect)")
        model.selection = CGRect(x: 1300, y: 300, width: 640, height: 360)
        let buttons = model.buttonRects
        check(monitor.contains(buttons.cancel) && monitor.contains(buttons.record), "Cancel and Record go on the screen under the area's bottom middle", "\(buttons)")
        // The monitor ends at 880 and the laptop at 982: below the monitor's bottom there is no screen.
        check(model.touchesAScreen(CGRect(x: 1400, y: 900, width: 50, height: 50)) && !model.touchesAScreen(CGRect(x: 2000, y: 900, width: 50, height: 50)), "the corner under the monitor, beside the laptop that reaches lower, is no screen")
        check(model.reach == CGRect(x: 0, y: -200, width: 3432, height: 1182), "the area can go anywhere on both screens")
        // Global points: the frame's top (1160) is above the laptop's (982) but the monitor goes on to 1280.
        let grip = RecordingOutline.gripOrigin(area: CGRect(x: 1600, y: 800, width: 640, height: 360), screens: [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1280)])
        check(grip.y > 1160, "while recording the grip goes above the frame where the taller screen has room", "\(grip)")
    }

    /// Allow… asks macOS (its window has Open System Settings) or opens System Settings, never both.
    private static func checkAllowShowsOneWindow() {
        let suite = "\(AppInfo.name).selftest.permissions.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            check(false, "a settings store for the Allow check")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        SystemActions.startRecording()
        SystemActions.askOnceThenOpenSettings("Screen Recording", pane: "Privacy_ScreenCapture", defaults: defaults) {
            check(false, "a recorded permission prompt is not shown")
        }
        let first = SystemActions.recorded
        SystemActions.askOnceThenOpenSettings("Screen Recording", pane: "Privacy_ScreenCapture", defaults: defaults) {
            check(false, "a recorded permission prompt is not shown")
        }
        let second = Array(SystemActions.recorded.dropFirst(first.count))
        let afterGuide = UserDefaults(suiteName: suite + ".guide")
        defer { afterGuide?.removePersistentDomain(forName: suite + ".guide") }
        let countBefore = SystemActions.recorded.count
        if let fresh = afterGuide {
            SystemActions.askOnceThenOpenSettings("Screen Recording", pane: "Privacy_ScreenCapture", askedBefore: true, defaults: fresh) {
                check(false, "a recorded permission prompt is not shown")
            }
        }
        let asked = Array(SystemActions.recorded.dropFirst(countBefore))
        SystemActions.stopRecording()
        check(asked == ["open x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"], "Allow after something else asked already opens System Settings at once", asked.joined(separator: " | "))
        check(first == ["ask Screen Recording"], "the first Allow only asks macOS, without opening System Settings too", first.joined(separator: " | "))
        check(second == ["open x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"], "a later Allow opens System Settings, without asking macOS again", second.joined(separator: " | "))
    }

    /// A card's "More actions" menu offers the log and crash report only when they were saved.
    static func checkHistoryCardMenu() {
        let capture = Capture(id: UUID(), kind: .video, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 10, events: [])
        defer { try? FileManager.default.removeItem(at: capture.folder) }
        let plain = HistoryCardAction.available(for: capture)
        check(plain == [.open, .reveal, .copyMarkdown, .copyJira, .copyEnvironment, .delete], "a capture card menu without a log or crash report", "\(plain)")
        try? FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: capture.systemLogURL.path, contents: Data("log".utf8))
        FileManager.default.createFile(atPath: capture.crashReportURL.path, contents: Data("crash".utf8))
        let crash = HistoryCardAction.available(for: capture)
        check(crash == HistoryCardAction.allCases && crash.last == .delete, "a crash clip card menu opens its log and crash report, Delete stays last", "\(crash)")
    }

    /// A clip's system log is written seconds after its editor opens; the editor still has to show
    /// the "System log" button once it is there.
    static func checkLateSystemLog() {
        let capture = Capture(id: UUID(), kind: .video, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 10, events: [])
        defer { try? FileManager.default.removeItem(at: capture.folder) }
        let store = CaptureStore.shared
        final class Changed {
            var value = false
        }
        let changed = Changed()
        let before = withObservationTracking {
            store.hasSystemLog(capture)
        } onChange: {
            changed.value = true
        }
        try? FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: capture.systemLogURL.path, contents: Data("log".utf8))
        store.systemLogSaved(for: capture.id)
        check(!before && changed.value && store.hasSystemLog(capture), "an open editor learns about a system log saved after it opened", "before=\(before) changed=\(changed.value)")
    }

    /// A capture.json that cannot be read is skipped and logged; the other captures still load.
    static func checkCaptureStoreSkipsBrokenCapture(folder: URL) {
        // A new name every run: lines from older runs may already be in the log.
        let root = folder.appendingPathComponent("broken-capture-store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let good = Capture(id: UUID(), kind: .screenshot, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 0, events: [])
        let goodFolder = root.appendingPathComponent(good.id.uuidString, isDirectory: true)
        let brokenFolder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let leftoverFolder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            for url in [goodFolder, brokenFolder, leftoverFolder] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(good).write(to: goodFolder.appendingPathComponent("capture.json"))
            try Data("{ not json".utf8).write(to: brokenFolder.appendingPathComponent("capture.json"))
        } catch {
            check(false, "a store with a broken capture can be set up", "\(error)")
            return
        }
        // Only this check's lines count (other threads may log errors meanwhile), and they stay out of
        // the real log file: their temporary paths can hold the user name.
        var lines: [String] = []
        let rootPath = root.path
        Log.errorObserver = { line in
            if !line.contains(rootPath) { return false }
            lines.append(line)
            return true
        }
        let store = CaptureStore(folder: root)
        Log.errorObserver = nil
        Log.waitForWrites()
        let brokenPath = brokenFolder.appendingPathComponent("capture.json").path
        let logFile = (try? String(contentsOf: Log.fileURL, encoding: .utf8)) ?? ""
        check(!logFile.contains(rootPath), "the check's made-up error stays out of the real log file")
        var logged: [String] = []
        for line in lines where line.contains(brokenPath) && line.contains("could not read") {
            logged.append(line)
        }
        check(store.captures.count == 1 && store.captures.first?.id == good.id, "the store loads the valid capture and skips the broken one", "\(store.captures.count) loaded")
        check(logged.count == 1, "a broken capture.json is logged with its path", "\(lines)")
        check(lines.count == 1, "a folder without capture.json is skipped without a log line", "\(lines)")
    }

    /// A long tooltip wraps and its panel is tall enough for every line.
    static func checkTooltipSize(folder: URL) {
        let text = "No fill: text without a label behind it, shapes as outlines only. Pick Text, Rectangle or Ellipse to use it"
        let layout = HoverTip.layout(for: text)
        let view = HoverTipView(text: text, textWidth: layout.textWidth)
        let needed = NSHostingView(rootView: Text(text).font(.system(size: HoverTip.fontSize)).frame(width: layout.textWidth, alignment: .leading).fixedSize(horizontal: false, vertical: true)).fittingSize
        check(layout.size.width <= HoverTip.maxTextWidth + 40, "a long tooltip wraps instead of growing wide", "\(layout.size)")
        check(needed.height + HoverTip.verticalPadding * 2 <= layout.size.height + 1, "a long tooltip has room for every line", "needs \(needed.height), panel \(layout.size.height)")
        render(view, size: layout.size, to: folder.appendingPathComponent("tooltip-long.png"))
    }

    /// Instructions say the keys in words, not only as symbols.
    static func checkShortcutWords() {
        let shortcut = Shortcut.optionShift(18, "1")
        check(shortcut.spoken == "Option + Shift + 1", "shortcut in words", shortcut.spoken)
    }
}
#endif
