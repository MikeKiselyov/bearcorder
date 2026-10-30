// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI
import AppCore

@MainActor
extension FeatureAutomation {
    static func runControls(_ name: String, _ argument: String, _ parts: [String], _ app: AppState) async -> String? {
        switch name {
        case "status-item":
            // Where the bear is (top-left screen points) and whether the panel is open.
            guard let button = app.statusItemButton(), let window = button.window, let primary = NSScreen.screens.first else { return "no status item open=\(app.isMenuPanelOpen)" }
            let frame = window.frame
            let x = Int(frame.midX)
            let y = Int(primary.frame.maxY - frame.midY)
            return "at=\(x),\(y) open=\(app.isMenuPanelOpen)"

        case "windows-debug":
            // Every window of the app: class, visible, key, frame, plus the activation policy.
            var parts: [String] = ["policy=\(NSApp.activationPolicy().rawValue) active=\(NSApp.isActive)"]
            for window in NSApp.windows {
                let frame = window.frame
                parts.append("\(window.className) visible=\(window.isVisible) key=\(window.isKeyWindow) level=\(window.level.rawValue) \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
            }
            return parts.joined(separator: " | ")

        case "status-item-probe":
            // Where the bear's window is, whether macOS says it is visible, and the menu bar
            // areas beside the notch.
            guard let button = app.statusItemButton(), let window = button.window else { return "no status item" }
            let frame = window.frame
            let visible = window.occlusionState.contains(.visible)
            var areas = ""
            if let screen = window.screen ?? NSScreen.main {
                let right = screen.auxiliaryTopRightArea ?? .zero
                let left = screen.auxiliaryTopLeftArea ?? .zero
                areas = "screen=\(Int(screen.frame.width)) left=\(Int(left.minX))-\(Int(left.maxX)) right=\(Int(right.minX))-\(Int(right.maxX))"
            }
            return "frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height)) occlusionVisible=\(visible) onScreen=\(window.isOnActiveSpace) \(areas)"

        case "menubar-hide-and-recover":
            // Puts the bear where macOS puts a new item, leftmost (behind the notch on a full
            // menu bar), then lets the app
            // bring it back. "notch=false" when this Mac has no notch to hide it behind.
            let hasNotch = (NSScreen.main?.auxiliaryTopRightArea ?? .zero).width > 0
            await app.reinsertMenuBarItem(at: nil)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let hiddenBefore = app.menuBarItemIsHidden() ?? false
            await app.keepMenuBarItemVisible(reason: "test")
            let hiddenAfter = app.menuBarItemIsHidden() ?? true
            let position = UserDefaults.standard.double(forKey: MenuBarPlacement.positionKey)
            return "notch=\(hasNotch) hiddenBefore=\(hiddenBefore) hiddenAfter=\(hiddenAfter) position=\(Int(position))"

        case "controls":
            // controls:<window id prefix|menubar>: every button, switch and menu in the window, as
            // the accessibility tree shows them: "role|label" items joined by " ;; ".
            var lines: [String] = []
            for window in controlWindows(argument) {
                for control in await ControlTree.controls(inWindowAt: topLeftFrame(window)) {
                    lines.append("\(control.role)|\(control.label)")
                }
            }
            // One line: the answer file is read line by line.
            return lines.joined(separator: " ;; ")

        case "control-value":
            // control-value:<window>:<label>: what the control shows, without opening it.
            guard parts.count > 2 else { return "bad control" }
            let label = parts[2...].joined(separator: ":")
            await showSettingsPage(with: label, window: argument)
            for window in controlWindows(argument) {
                if let shown = ControlTree.value(label: label, inWindowAt: topLeftFrame(window)) {
                    // One line: the answer file is read line by line.
                    return "value=\(shown.replacingOccurrences(of: "\n", with: "\\n"))"
                }
            }
            return "not found"

        case "settings-page":
            // settings-page:<page name>: shows that page of Settings, as its sidebar button does.
            guard let page = SettingsPage(rawValue: parts.count > 1 ? parts[1...].joined(separator: ":") : "") else { return "no page" }
            SettingsNavigation.shared.page = page
            try? await Task.sleep(nanoseconds: 400_000_000)
            return "page=\(page.rawValue)"

        case "tall-window":
            // tall-window:<window id>: makes the window tall enough that a long form has every row
            // built, so accessibility sees controls below the fold.
            guard let window = controlWindows(argument).first else { return "no window" }
            var frame = window.frame
            frame.size.height = 4000
            frame.origin.y = (NSScreen.screens.first?.frame.maxY ?? 1000) - 4000
            window.setFrame(frame, display: true)
            try? await Task.sleep(nanoseconds: 500_000_000)
            return "height=\(Int(window.frame.height))"

        case "control-roles":
            var lines: [String] = []
            for window in controlWindows(argument) {
                lines.append(await ControlTree.roleCounts(inWindowAt: topLeftFrame(window)))
            }
            return lines.joined(separator: "\n")

        case "press", "press-now":
            // press:<window>:<label>: presses the control with that label, like VoiceOver would, and
            // answers after a moment for the window to redraw. press-now answers right after the
            // press: the script waits for what the press does (a setting, the clipboard) itself.
            guard parts.count > 2 else { return "bad press" }
            let label = parts[2...].joined(separator: ":")
            // Space's buttons that remove files are pressed only on a made-up home, never the real one.
            if isSpaceRemovalLabel(label) && SpaceModel.shared.homeOverride == nil {
                return "refused: no made-up home"
            }
            await showSettingsPage(with: label, window: argument)
            for window in controlWindows(argument) {
                if await ControlTree.press(label: label, inWindowAt: topLeftFrame(window)) {
                    if name == "press" {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    return "pressed"
                }
            }
            return "not found"

        case "menu-items", "choose", "choose-now":
            // menu-items:<window>:<label>: the items of a picker or menu, " ;; " between.
            // choose:<window>:<label> => <item>: picks one, without opening the menu. choose-now
            // answers right after picking, like press-now.
            guard parts.count > 2 else { return "bad \(name)" }
            let rest = parts[2...].joined(separator: ":")
            var label = rest
            var item = ""
            if let separator = rest.range(of: " => ") {
                label = String(rest[..<separator.lowerBound])
                item = String(rest[separator.upperBound...])
            }
            await showSettingsPage(with: label, window: argument)
            for window in controlWindows(argument) {
                guard ControlTree.frame(label: label, inWindowAt: topLeftFrame(window), scrollIntoView: true) != nil else { continue }
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let frame = ControlTree.frame(label: label, inWindowAt: topLeftFrame(window), scrollIntoView: false) else { continue }
                guard let button = PopUpMenus.button(at: CGPoint(x: frame.midX, y: frame.midY), in: window) else { return "not a menu" }
                if name == "menu-items" {
                    return PopUpMenus.items(of: button).joined(separator: " ;; ")
                }
                if PopUpMenus.choose(item, in: button) {
                    if name == "choose" {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    return "chosen"
                }
                return "no item"
            }
            return "not found"

        case "setting-read":
            // setting-read:<key>: the value the running app uses, the default when never changed
            // (defaults on disk do not show those). Booleans read 1 or 0, lists "a,b".
            let key = parts.count > 1 ? parts[1] : ""
            guard let value = UserDefaults.standard.object(forKey: key) else { return "" }
            if let list = value as? [String] {
                return list.joined(separator: ",")
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            if let names = value as? [String: String] {
                var pairs: [String] = []
                for key in names.keys.sorted() {
                    pairs.append("\(key)=\(names[key] ?? "")")
                }
                return pairs.joined(separator: ";")
            }
            return "\(value)"

        case "setting-write":
            // setting-write:<key>=<value>: changes a setting in the running app, as its control
            // does; writing defaults from outside would not reach the app until it restarts.
            let rest = parts.count > 1 ? parts[1...].joined(separator: ":") : ""
            guard let equals = rest.firstIndex(of: "=") else { return "bad setting-write" }
            let key = String(rest[..<equals])
            let text = String(rest[rest.index(after: equals)...])
            let settings = app.settings
            switch key {
            case "outputFolderPath": settings.outputFolderPath = text
            case "keepCapturesDays": settings.keepCapturesDays = Int(text) ?? settings.keepCapturesDays
            case "maxCapturesGB": settings.maxCapturesGB = Int(text) ?? settings.maxCapturesGB
            case "keepCrashClipsDays": settings.keepCrashClipsDays = Int(text) ?? settings.keepCrashClipsDays
            case "bufferMinutes": settings.bufferMinutes = Int(text) ?? settings.bufferMinutes
            case "framesPerSecond": settings.framesPerSecond = Int(text) ?? settings.framesPerSecond
            case "recordingFramesPerSecond": settings.recordingFramesPerSecond = Int(text) ?? settings.recordingFramesPerSecond
            case "maxHeight": settings.maxHeight = Int(text) ?? settings.maxHeight
            case "bugReportFormat": settings.bugReportFormat = text
            case "oldProjectDays": settings.oldProjectDays = Int(text) ?? settings.oldProjectDays
            case "projectRoots":
                // A list: "Projects,Code"; empty searches nowhere.
                var roots: [String] = []
                for root in text.split(separator: ",") {
                    roots.append(String(root))
                }
                settings.projectRoots = roots
            case "hiddenEnvironmentFields":
                // A list: "Locale,Time"; empty shows every field.
                var hidden: [String] = []
                for name in text.split(separator: ",") {
                    hidden.append(String(name))
                }
                settings.hiddenEnvironmentFields = hidden
            case "renamedEnvironmentFields":
                // Pairs: "Device=Model;App=Program"; empty keeps the usual names.
                var renamed: [String: String] = [:]
                for pair in text.split(separator: ";") {
                    let pieces = pair.split(separator: "=", maxSplits: 1)
                    if pieces.count == 2 {
                        renamed[String(pieces[0])] = String(pieces[1])
                    }
                }
                settings.renamedEnvironmentFields = renamed
            default: return "unknown setting \(key)"
            }
            return "\(key)=\(text)"

        case "set-value", "set-value-typing":
            // set-value:<window>:<label>=<text>: types into a text field or a text area, "\\n" for a
            // line break. set-value-typing leaves the cursor in the field, as if still typing.
            guard parts.count > 2 else { return "bad set-value" }
            let rest = parts[2...].joined(separator: ":")
            guard let equals = rest.firstIndex(of: "=") else { return "bad set-value" }
            let label = String(rest[..<equals])
            let text = String(rest[rest.index(after: equals)...]).replacingOccurrences(of: "\\n", with: "\n")
            await showSettingsPage(with: label, window: argument)
            for window in controlWindows(argument) {
                // By its name first, which also finds a field scrolled out of sight; else the field
                // under the middle of the control with that label.
                var found = TextInput.view(labeled: label, in: window)
                if found == nil {
                    guard let frame = ControlTree.frame(label: label, inWindowAt: topLeftFrame(window), scrollIntoView: true) else { continue }
                    found = TextInput.view(at: CGPoint(x: frame.midX, y: frame.midY), in: window)
                }
                guard let view = found else { return "not a text field" }
                if TextInput.type(text, into: view, endEditing: name != "set-value-typing") {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    return "set"
                }
                return "not a text field"
            }
            return "not found"

        case "control-frame":
            // control-frame:<window>:<label>: where the control is, in top-left screen points.
            guard parts.count > 2 else { return "bad control-frame" }
            let label = parts[2...].joined(separator: ":")
            await showSettingsPage(with: label, window: argument)
            for window in controlWindows(argument) {
                if let frame = ControlTree.frame(label: label, inWindowAt: topLeftFrame(window), scrollIntoView: false) {
                    return "frame=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)) window=\(topLeftFrame(window))"
                }
            }
            return "not found"

        default:
            return nil
        }
    }
}
#endif
