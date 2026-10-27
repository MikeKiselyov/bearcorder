import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI
import BugbearCore

/// Automation commands for scripts/e2e-features.sh: drive each feature the way a user would,
/// without the pickers and dialogs that need a mouse. Only active with the automation hook on.
@MainActor
enum FeatureAutomation {
    /// Handles `command` if it is a feature command. Returns the result text, or nil for unknown commands.
    static func run(_ parts: [String]) async -> String? {
        let app = AppState.shared
        let name = parts.first ?? ""
        let argument = parts.count > 1 ? parts[1] : ""
        switch name {
        case "ax":
            return "trusted=\(AXIsProcessTrusted())"

        case "screen":
            let frame = NSScreen.main?.frame ?? .zero
            return "width=\(Int(frame.width)) height=\(Int(frame.height)) front=\(app.lastExternalApp?.localizedName ?? "?")"

        case "move-front":
            // move-front:x,y (top-left, points)
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let x = Double(numbers[0]), let y = Double(numbers[1]) else { return "bad point" }
            return "moved=\(WindowResizer.move(app: app.lastExternalApp, to: CGPoint(x: x, y: y)))"

        case "web-area":
            // The visible page area of the front browser window: normalized on the display it is on
            // (top-left origin), then its global top-left frame in points, then that display's width.
            // The scroll test does not depend on toolbars, tab bars or which display holds the window.
            guard let running = app.lastExternalApp, let frame = webAreaFrame(of: running), let primary = NSScreen.screens.first else { return "no web area" }
            let center = CGPoint(x: frame.midX, y: primary.frame.maxY - frame.midY)
            guard let screen = NSScreen.screens.first(where: { item in item.frame.contains(center) }) else { return "no screen" }
            let screenTop = primary.frame.maxY - screen.frame.maxY
            let x = (frame.minX - screen.frame.minX) / screen.frame.width
            let y = (frame.minY - screenTop) / screen.frame.height
            let width = frame.width / screen.frame.width
            let height = frame.height / screen.frame.height
            return String(format: "%.4f,%.4f,%.4f,%.4f %d,%d,%d,%d %d", x, y, width, height, Int(frame.minX), Int(frame.minY), Int(frame.width), Int(frame.height), Int(screen.frame.width))

        case "browser-accessibility-off":
            // Undo what web-area asked of the browser, so it does not keep the page tree up to date.
            guard let pid = browserWithAccessibility else { return "nothing to undo" }
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanFalse)
            browserWithAccessibility = nil
            return "off"

        case "scroll-capture":
            // scroll-capture:x,y,w,h (normalized area on the screen under the pointer)
            guard let area = selection(argument) else { return "bad area" }
            do {
                guard let image = try await ScrollingCapture.shared.run(on: area.screen, area: area) else { return "cancelled" }
                let file = AppPaths.temporary.appendingPathComponent("e2e-scroll.png")
                ImageFiles.write(image, to: file, type: "public.png")
                return "width=\(image.width) height=\(image.height) file=\(file.path)"
            } catch {
                return "error \(error)"
            }

        case "scroll-probe":
            // scroll-probe:x,y,w,h:<points>
            guard let area = selection(argument) else { return "bad area" }
            let points = parts.count > 2 ? Int(parts[2]) ?? 300 : 300
            do {
                return try await ScrollingCapture.shared.probe(on: area.screen, area: area, points: points)
            } catch {
                return "error \(error)"
            }

        case "stitch-files":
            // stitch-files:<a.png>:<b.png> → best shift and the score at a few shifts
            guard parts.count > 2, let first = ImageFiles.load(URL(fileURLWithPath: argument)), let second = ImageFiles.load(URL(fileURLWithPath: parts[2])) else { return "no images" }
            let a = ScrollingCapture.rowSignatures(first)
            let b = ScrollingCapture.rowSignatures(second)
            let best = ScrollStitcher.bestShift(previous: a, next: b)
            var flatA = 0
            for row in a where row == nil { flatA += 1 }
            return "rows=\(a.count) flat=\(flatA) best=\(best.shift ?? -1)@err\(String(format: "%.1f", best.error)) next=\(String(format: "%.1f", best.runnerUp))/\(best.compared) diag=\(ScrollStitcher.diagnose(previous: a, next: b, shift: 488))"

        case "copy-text-file":
            // copy-text-file:<path>: what ⌥⇧O does after the area is picked, on a picture from a file.
            guard let image = ImageFiles.load(URL(fileURLWithPath: argument)) else { return "no image" }
            Toast.shared.hide()
            NSPasteboard.general.clearContents()
            await AppState.shared.copyText(from: image)
            let copied = NSPasteboard.general.string(forType: .string) ?? ""
            return "toast=\(Toast.shared.isShowing) copied=\(copied.replacingOccurrences(of: "\n", with: " | "))"

        case "ocr-file":
            // ocr-file:<path> → the recognized text, lines joined with " | "
            // Tall images are read in 1000 px pieces with 150 px overlap: Vision shrinks huge images.
            guard let image = ImageFiles.load(URL(fileURLWithPath: argument)) else { return "no image" }
            var texts: [String] = []
            var top = 0
            while top < image.height {
                let height = min(1000, image.height - top)
                if let piece = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: height)) {
                    let lines = (try? await TextRecognizer.recognize(piece)) ?? []
                    texts.append(TextRecognizer.text(of: lines).replacingOccurrences(of: "\n", with: " | "))
                }
                if top + height >= image.height { break }
                top += 850
            }
            return texts.joined(separator: " || ")

        case "clip-screens":
            // The screens of the newest capture: id=name(clicks) and which one is selected.
            guard let clip = app.store.captures.first else { return "no capture" }
            guard let screens = clip.screens else { return "single screen" }
            var parts: [String] = []
            for screen in screens {
                let exists = FileManager.default.fileExists(atPath: clip.folder.appendingPathComponent(screen.file).path)
                parts.append("\(screen.id)=\(screen.name)(clicks:\(screen.events.filter { event in event.kind == .click }.count) file:\(exists))")
            }
            return "selected=\(clip.selectedScreen ?? "?") " + parts.joined(separator: " ")

        case "select-screen":
            // select-screen:<id> on the newest capture; prints the picture size afterwards.
            guard let clip = app.store.captures.first else { return "no capture" }
            let started = Date()
            do {
                let updated = try await app.store.selectScreen(argument, of: clip, framesPerSecond: app.settings.framesPerSecond)
                var stagedFiles = 0
                for name in (try? FileManager.default.contentsOfDirectory(atPath: updated.folder.path)) ?? [] where name.hasPrefix("staged-") {
                    stagedFiles += 1
                }
                if updated.kind == .screenshot {
                    guard let image = ImageFiles.load(updated.mediaURL) else { return "no image" }
                    let marks = FileManager.default.fileExists(atPath: updated.projectURL.path)
                    return "selected=\(updated.selectedScreen ?? "?") size=\(image.width)x\(image.height) project=\(marks) staged=\(stagedFiles)"
                }
                guard let track = try await AVURLAsset(url: updated.mediaURL).loadTracks(withMediaType: .video).first else { return "no track" }
                let size = try await track.load(.naturalSize)
                return String(format: "selected=%@ size=%dx%d duration=%.2f took=%.2fs staged=%d", updated.selectedScreen ?? "?", Int(size.width), Int(size.height), updated.duration, Date().timeIntervalSince(started), stagedFiles)
            } catch {
                let details = error as NSError
                return "error \(details.domain) \(details.code) \(details.userInfo)"
            }

        case "space-measure":
            // Sizes of the clean-up categories in the real home folder (nothing is deleted).
            let space = SpaceModel.shared
            await space.measure(force: true)
            var parts: [String] = ["free=\(SpaceModel.format(space.volumeFree))", "cleanable=\(SpaceModel.format(space.cleanableBytes))"]
            for category in CleanupCategory.all {
                parts.append("\(category.id)=\(SpaceModel.format(space.sizes[category.id] ?? 0))")
            }
            return parts.joined(separator: " ")

        case "space-scan":
            // space-scan (home + Applications), space-scan:appdata (also other apps' data),
            // or space-scan:<subfolder of home>.
            let space = SpaceModel.shared
            if argument == "appdata" {
                space.includeAppData = true
                space.startScan()
            } else if argument.isEmpty {
                space.startScan()
            } else {
                space.startScan(subfolder: argument)
            }
            while space.isScanning {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard let tree = space.tree, case .done(let seconds) = space.scanState else { return "no result" }
            var lines: [String] = [String(format: "files=%d scanned=%@ notCounted=%@ seconds=%.1f", tree.root.fileCount, SpaceModel.format(tree.root.bytes), SpaceModel.format(space.notCounted), seconds)]
            for root in tree.root.children {
                var inner: [String] = []
                for child in root.children.prefix(10) {
                    inner.append("\(child.name)=\(SpaceModel.format(child.bytes))")
                }
                lines.append("\(root.name)=\(SpaceModel.format(root.bytes)): " + inner.joined(separator: ", "))
            }
            return lines.joined(separator: " || ")

        case "space-stop-test":
            // Start a scan, stop it, start again right away: one clean result, no stale updates.
            let space = SpaceModel.shared
            space.startScan(subfolder: "Library")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            space.cancelScan()
            let stoppedState = "\(space.scanState)"
            space.startScan(subfolder: "Library")
            while space.isScanning {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            // Give a stale walk time to come back and overwrite things, if it still could.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let tree = space.tree else { return "no result" }
            return "afterStop=\(stoppedState) final=\(space.scanState) files=\(tree.root.fileCount)"

        case "space-folder":
            // space-folder:Home > Library > Application Support: the biggest folders inside it.
            // " > " separates names, because a scanned subfolder root keeps its slashes.
            guard let node = SpaceModel.shared.tree?.node(at: argument.components(separatedBy: " > ")) else { return "not found" }
            var parts: [String] = []
            for child in node.children.prefix(12) {
                parts.append("\(child.name)=\(SpaceModel.format(child.bytes))")
            }
            return "\(argument)=\(SpaceModel.format(node.bytes)): " + parts.joined(separator: ", ")

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
            // menu bar), then lets Bugbear
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

        case "press":
            // press:<window>:<label>: presses the control with that label, like VoiceOver would.
            guard parts.count > 2 else { return "bad press" }
            let label = parts[2...].joined(separator: ":")
            await showSettingsPage(with: label, window: argument)
            for window in controlWindows(argument) {
                if await ControlTree.press(label: label, inWindowAt: topLeftFrame(window)) {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    return "pressed"
                }
            }
            return "not found"

        case "menu-items", "choose":
            // menu-items:<window>:<label>: the items of a picker or menu, " ;; " between.
            // choose:<window>:<label> => <item>: picks one, without opening the menu.
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
                    try? await Task.sleep(nanoseconds: 400_000_000)
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

        case "cleanup-pause":
            // cleanup-pause:on|off: the timed storage clean-up waits while tests change its limits.
            app.scheduledCleanUpPaused = argument == "on"
            return "paused=\(app.scheduledCleanUpPaused)"

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

        case "latest-capture":
            // The newest capture: "<id> <kind>".
            guard let latest = app.store.captures.first else { return "no capture" }
            return "\(latest.id.uuidString) \(latest.kind == .screenshot ? "screenshot" : "video")"

        case "permissions":
            // What this copy of Bugbear may use, so tests skip what would show a macOS prompt.
            let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let camera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            return "screen=\(ScreenBuffer.hasScreenRecordingAccess) accessibility=\(InputEventRecorder.hasAccessibilityAccess) microphone=\(microphone) camera=\(camera)"

        case "buffer-needs-permission":
            // buffer-needs-permission:on|off: the buffer state the guide shows "Relaunch" for (access
            // given but the buffer not started yet); off puts the real state back.
            if argument == "on" {
                if app.bufferState != .needsPermission {
                    stateBeforePermissionFake = app.bufferState
                }
                app.bufferState = .needsPermission
            } else if let saved = stateBeforePermissionFake {
                // Only while still faked: a real change in between (the buffer started) wins.
                if app.bufferState == .needsPermission {
                    app.bufferState = saved
                }
                stateBeforePermissionFake = nil
            }
            return "\(app.bufferState)"

        case "update-fake":
            // update-fake:available|failed|idle: the update badge as it shows for a new version or
            // a failed update, without asking GitHub.
            let updater = Updater.shared
            if argument == "available" {
                let changes = [UpdateInfo.Change(title: "Fake change for tests", shortSHA: "abc1234", pullRequest: 42), UpdateInfo.Change(title: "Another fake change", shortSHA: "def5678")]
                updater.state = .available(UpdateInfo(version: "9.9.9", newCommitCount: 2, changes: changes))
            } else if argument == "failed" {
                updater.state = .failed("Update failed: fake failure for tests")
            } else {
                updater.state = .idle
            }
            return "\(updater.state)"

        case "toolbox-open":
            // toolbox-open:<tool name as the sidebar shows it>: the toolbox on that tool.
            guard parts.count > 1, let tool = ToolKind(rawValue: parts[1...].joined(separator: ":")) else { return "no tool" }
            WindowManager.shared.openToolbox(tool: tool)
            NotificationCenter.default.post(name: .toolboxSelect, object: nil, userInfo: ["tool": tool.rawValue])
            try? await Task.sleep(nanoseconds: 800_000_000)
            return "tool=\(ToolboxState.shown?.rawValue ?? "none")"

        case "time-zones":
            // time-zones: the saved zones, "a,b,c"; time-zones:set:<a,b,c> saves these, nothing
            // after "set" saves none (tests put the person's list back).
            if parts.count > 1 && parts[1] == "set" {
                var zones: [String] = []
                if parts.count > 2 {
                    for zone in parts[2...].joined(separator: ":").split(separator: ",") {
                        zones.append(String(zone))
                    }
                }
                app.settings.timeZones = zones
            }
            return app.settings.timeZones.joined(separator: ",")

        case "toolbox-tool":
            return "tool=\(ToolboxState.shown?.rawValue ?? "none")"

        case "system-actions":
            // system-actions:start|stop|read: record what buttons would open instead of opening it.
            if argument == "start" {
                SystemActions.startRecording()
                return "recording"
            }
            if argument == "stop" {
                SystemActions.stopRecording()
                return "stopped"
            }
            if argument == "files" {
                // system-actions:files:<path>,<path>: what the file chooser picks.
                var urls: [URL] = []
                if parts.count > 2 {
                    for path in parts[2...].joined(separator: ":").split(separator: ",") {
                        urls.append(URL(fileURLWithPath: String(path)))
                    }
                }
                SystemActions.chosenFiles = urls
                return "files=\(urls.count)"
            }
            return SystemActions.recorded.joined(separator: " ;; ")

        case "visible-windows":
            // The app's visible windows: their id, or the class for windows without one.
            var names: [String] = []
            for window in NSApp.windows where window.isVisible {
                var name = window.identifier?.rawValue ?? ""
                if name.isEmpty || name.hasPrefix("_NS") || name.contains("SwiftUI") {
                    name = window.className
                }
                names.append(name)
            }
            return names.joined(separator: ";")

        case "window-visible":
            // Whether the window with this id (onboarding, settings...) is on screen.
            var visible = false
            for window in NSApp.windows where window.identifier?.rawValue == argument && window.isVisible {
                visible = true
            }
            return "visible=\(visible)"

        case "press-status-item":
            // What a click on the bear does, without going through the event system.
            app.statusItemButton()?.performClick(nil)
            try? await Task.sleep(nanoseconds: 500_000_000)
            return "open=\(app.isMenuPanelOpen)"

        case "close-panel":
            app.closeMenuPanel()
            try? await Task.sleep(nanoseconds: 300_000_000)
            return "open=\(app.isMenuPanelOpen)"

        case "space-top":
            // Full paths of the biggest files from the last scan.
            var lines: [String] = []
            for file in SpaceModel.shared.topFiles.prefix(Int(argument) ?? 5) {
                lines.append("\(SpaceModel.format(file.bytes)) \(file.path)")
            }
            return lines.joined(separator: " | ")

        case "dock-reopen":
            // What a click on the Dock icon does: reports the windows left, the Dock state and the menu.
            // Whether the icon is in the Dock is read by the test from macOS (lsappinfo): for a menu
            // bar app NSApp.activationPolicy() keeps answering .accessory after the switch.
            WindowManager.shared.reopenFromDock()
            try? await Task.sleep(nanoseconds: 600_000_000)
            return "windows=\(WindowManager.shared.openWindowCount) menu=\(app.isMenuPanelOpen)"

        case "open-onboarding":
            // Opens the welcome guide and reports its frame and the visible part of its screen.
            WindowManager.shared.close(id: "onboarding")
            WindowManager.shared.openOnboarding()
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }), let screen = window.screen else {
                return "no window"
            }
            let frame = window.frame
            let visible = screen.visibleFrame
            return "frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)) visible=\(Int(visible.minX)),\(Int(visible.minY)),\(Int(visible.width)),\(Int(visible.height))"

        case "open-feedback":
            // open-feedback:problem|idea[:keep]: opens the feedback window and reports its frame; it
            // is closed again unless "keep" asks to leave it open for the buttons' checks.
            let kind = FeedbackReport.Kind(rawValue: argument) ?? .problem
            let keep = parts.count > 2 && parts[2] == "keep"
            WindowManager.shared.close(id: "feedback")
            WindowManager.shared.openFeedback(kind: kind)
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "feedback" }), let screen = window.screen else {
                return "no window"
            }
            let frame = window.frame
            let visible = screen.visibleFrame
            let inside = visible.contains(frame)
            if !keep {
                WindowManager.shared.close(id: "feedback")
            }
            return "opened inside=\(inside) frame=\(Int(frame.width))x\(Int(frame.height))"

        case "feedback-url":
            // Builds the GitHub link for a problem or an idea without opening it. A log line with the
            // home folder and the user name is written first, so the check proves they are hidden.
            let kind = FeedbackReport.Kind(rawValue: argument) ?? .problem
            Log.info("Feedback check: \(Feedback.homePath)/Desktop by \(NSUserName())")
            try? await Task.sleep(nanoseconds: 300_000_000)
            let model = FeedbackModel(kind: kind)
            try? await Task.sleep(nanoseconds: 500_000_000)
            model.title = "Automation check"
            model.details = "Saved clip is black & silent + short"
            guard let url = model.report.issueURL() else { return "no url" }
            let text = url.absoluteString
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var template = ""
            var hasVersion = false
            var logs = ""
            var allValues = ""
            for item in components?.queryItems ?? [] {
                let value = item.value ?? ""
                allValues += value + "\n"
                if item.name == "template" {
                    template = value
                }
                if item.name == "environment" {
                    hasVersion = value.contains("\(AppInfo.name): \(Updater.shared.version)")
                }
                if item.name == "logs" {
                    logs = value
                }
            }
            let logLines = logs.split(separator: "\n").count
            let leaksHome = allValues.contains(Feedback.homePath)
            let leaksUser = allValues.range(of: "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: NSUserName()) + "(?![A-Za-z0-9])", options: [.regularExpression, .caseInsensitive]) != nil
            let planted = logs.contains("Feedback check: ~/Desktop by <user>")
            return "template=\(template) version=\(hasVersion) logs=\(logLines) planted=\(planted) length=\(text.count) home=\(leaksHome) user=\(leaksUser)"

        case "feedback-zip":
            // Makes the log zip in a scratch folder and lists what is inside.
            Log.info("Feedback zip check from \(Feedback.homePath)/Desktop by \(NSUserName())")
            try? await Task.sleep(nanoseconds: 300_000_000)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bugbear-feedback-check", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            let environment = FeedbackModel(kind: .problem).report.environmentText
            guard case .success(let archive) = Feedback.makeLogArchive(environmentText: environment, in: folder) else { return "no zip" }
            let unpacked = folder.appendingPathComponent("unpacked", isDirectory: true)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            task.arguments = ["-x", "-k", archive.path, unpacked.path]
            try? task.run()
            task.waitUntilExit()
            let inner = unpacked.appendingPathComponent("\(AppInfo.name) logs", isDirectory: true)
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: inner.path)) ?? []).sorted()
            var leaksHome = false
            var leaksUser = false
            var planted = false
            for name in names {
                let text = (try? String(contentsOf: inner.appendingPathComponent(name), encoding: .utf8)) ?? ""
                if text.contains(Feedback.homePath) {
                    leaksHome = true
                }
                if text.range(of: "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: NSUserName()) + "(?![A-Za-z0-9])", options: [.regularExpression, .caseInsensitive]) != nil {
                    leaksUser = true
                }
                if text.contains("Feedback zip check from ~/Desktop by <user>") {
                    planted = true
                }
            }
            try? FileManager.default.removeItem(at: folder)
            return "files=\(names.joined(separator: ",")) planted=\(planted) home=\(leaksHome) user=\(leaksUser)"

        case "feedback-crash":
            // The launch check with a fake crash of this Bugbear: "on" opens the report window with the
            // crash filled in, "off" (setting turned off) opens nothing; both move the check time on.
            let enabled = argument != "off"
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bugbear-crash-check", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            try? Data(DevChecks.fakeCrashReport(bundleId: bundleId).utf8).write(to: folder.appendingPathComponent("Bugbear-check.ips"))
            let defaults = UserDefaults(suiteName: "bugbear-crash-check") ?? .standard
            let before = Date().addingTimeInterval(-60)
            defaults.set(before, forKey: Feedback.lastCrashCheckKey)
            WindowManager.shared.close(id: "feedback")
            let offered = await Feedback.offerReportAfterCrash(folder: folder, defaults: defaults, enabled: enabled, windowDelay: 0)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let moved = ((defaults.object(forKey: Feedback.lastCrashCheckKey) as? Date) ?? before) > before
            DevChecks.forgetScratchDefaults(defaults, domain: "bugbear-crash-check")
            // macOS writes the emptied domain's file a moment later; then it goes.
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                try? FileManager.default.removeItem(at: DevChecks.preferencesFile("bugbear-crash-check"))
            }
            let open = WindowManager.shared.isOpen(id: "feedback")
            let model = WindowManager.shared.feedbackModel
            var url = ""
            if let report = model?.report, let link = report.issueURL() {
                url = link.absoluteString
            }
            let hasCrash = url.contains("crash=") && url.contains("EXC_BREAKPOINT")
            let canSend = model?.canSend ?? false
            let title = model?.title ?? ""
            WindowManager.shared.close(id: "feedback")
            try? FileManager.default.removeItem(at: folder)
            return "offered=\(offered) open=\(open) crash=\(hasCrash) canSend=\(canSend) moved=\(moved) title=\(title)"

        case "feedback-switch":
            // Asking for an idea while the problem window is open shows the idea form.
            WindowManager.shared.openFeedback(kind: .problem)
            try? await Task.sleep(nanoseconds: 300_000_000)
            WindowManager.shared.openFeedback(kind: .idea)
            try? await Task.sleep(nanoseconds: 300_000_000)
            let kind = WindowManager.shared.feedbackModel?.kind.rawValue ?? "none"
            WindowManager.shared.close(id: "feedback")
            return "kind=\(kind)"

        case "open-space":
            // open-space:<Clean up|Folders|Largest files>
            let section = SpaceView.Section(rawValue: argument) ?? .cleanUp
            WindowManager.shared.close(id: "space")
            WindowManager.shared.openSpace(section: section)
            return "opened \(section.rawValue)"

        case "space-fake-home":
            // space-fake-home:on|off: the Disk Space window measures, scans and cleans a made-up
            // home folder with a cache, a log and a big download, so its buttons can be pressed.
            let space = SpaceModel.shared
            let files = FileManager.default
            if let fakeHome = space.homeOverride {
                try? files.removeItem(at: fakeHome)
            }
            space.homeOverride = nil
            space.applicationsOverride = nil
            space.scanStartDelay = 0
            space.confirmingID = nil
            space.confirmingFile = nil
            space.message = nil
            if argument != "on" {
                await space.measure(force: true)
                return "off"
            }
            let fakeHome = AppPaths.temporary.appendingPathComponent("space-buttons-\(UUID().uuidString)", isDirectory: true)
            let samples = ["Library/Caches/com.example.app/blob.bin": 3_000_000, "Library/Logs/Example/run.log": 1_000_000, "Downloads/bugbear-test-big.bin": 60_000_000, "Applications/Example.app/Contents/Info.plist": 1_000]
            for (sample, bytes) in samples {
                let url = fakeHome.appendingPathComponent(sample)
                try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data(count: bytes).write(to: url)
            }
            space.homeOverride = fakeHome
            space.applicationsOverride = fakeHome.appendingPathComponent("Applications")
            // A tiny home scans in no time; this leaves "Stop" something to stop.
            space.scanStartDelay = 2
            await space.measure(force: true)
            return fakeHome.path

        case "space-state":
            // What the Disk Space window's buttons changed.
            let space = SpaceModel.shared
            var scan = "idle"
            switch space.scanState {
            case .idle:
                scan = "idle"
            case .preparing, .running:
                scan = "running"
            case .done:
                scan = "done"
            }
            let caches = SpaceModel.format(space.sizes["appCaches"] ?? 0)
            return "scan=\(scan) appData=\(space.includeAppData) appCaches=\(caches) files=\(space.topFiles.count) folder=\(space.folderPath.joined(separator: " > "))"

        case "space-clean-test":
            // Cleans "App caches" and "Logs" in a made-up home folder: caches go, kept folders stay.
            let space = SpaceModel.shared
            let fakeHome = AppPaths.temporary.appendingPathComponent("space-home-\(UUID().uuidString)", isDirectory: true)
            let files = FileManager.default
            let samples = ["Library/Caches/com.example.app/blob.bin", "Library/Caches/Homebrew/tool.tar.gz", "Library/Logs/Example/run.log", "Library/Logs/Bugbear/bugbear.log", "Library/Logs/DiagnosticReports/Example-2026.ips"]
            for sample in samples {
                let url = fakeHome.appendingPathComponent(sample)
                try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data(count: 2_000_000).write(to: url)
            }
            space.homeOverride = fakeHome
            await space.measure(force: true)
            let beforeCaches = space.sizes["appCaches"] ?? 0
            let beforeHomebrew = space.sizes["homebrew"] ?? 0
            for category in CleanupCategory.all where category.id == "appCaches" || category.id == "logs" {
                await space.clean(category)
            }
            let cacheGone = !files.fileExists(atPath: fakeHome.appendingPathComponent(samples[0]).path)
            let homebrewKept = files.fileExists(atPath: fakeHome.appendingPathComponent(samples[1]).path)
            let otherLogGone = !files.fileExists(atPath: fakeHome.appendingPathComponent(samples[2]).path)
            let ownLogKept = files.fileExists(atPath: fakeHome.appendingPathComponent(samples[3]).path)
            let folderKept = files.fileExists(atPath: fakeHome.appendingPathComponent("Library/Caches").path)
            let crashReportKept = files.fileExists(atPath: fakeHome.appendingPathComponent(samples[4]).path)
            let result = "before appCaches=\(SpaceModel.format(beforeCaches)) homebrew=\(SpaceModel.format(beforeHomebrew)) cacheGone=\(cacheGone) homebrewKept=\(homebrewKept) otherLogGone=\(otherLogGone) ownLogKept=\(ownLogKept) cachesFolderKept=\(folderKept) crashReportsKept=\(crashReportKept)"
            space.message = nil
            space.homeOverride = nil
            try? files.removeItem(at: fakeHome)
            await space.measure(force: true)
            return result

        case "front-title":
            // The title of the front app's focused window, so scripts act only on their own window.
            guard let running = app.lastExternalApp else { return "title=" }
            let element = AXUIElementCreateApplication(running.processIdentifier)
            var focused: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focused) == .success, let window = focused, CFGetTypeID(window) == AXUIElementGetTypeID() else { return "title=" }
            var title: AnyObject?
            AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
            return "title=\(title as? String ?? "")"

        case "app-windows":
            // app-windows:<name>: the app's windows from Accessibility: title, top-left, size, minimized.
            guard let running = NSWorkspace.shared.runningApplications.first(where: { item in item.localizedName == argument }) else { return "not running" }
            let element = AXUIElementCreateApplication(running.processIdentifier)
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return "no windows" }
            var lines: [String] = []
            for window in windows {
                var title: AnyObject?
                var minimized: AnyObject?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                let box = frame(of: window) ?? .zero
                lines.append("\(title as? String ?? "?")@\(ControlTree.whole(box.minX)),\(ControlTree.whole(box.minY)),\(ControlTree.whole(box.width))x\(ControlTree.whole(box.height)) min=\(minimized as? Bool ?? false)")
            }
            return "\(windows.count): " + lines.joined(separator: " | ")

        case "activate-app":
            // activate-app:<name>: clicks the title bar of the app's frontmost window, the way a person
            // would. `open -a` no longer brings an app forward when another app has the focus.
            guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return "no windows" }
            for info in list {
                guard let owner = info[kCGWindowOwnerName as String] as? String, owner == argument else { continue }
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat], let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], width > 200 else { continue }
                let point = CGPoint(x: x + width / 2, y: y + 12)
                let source = CGEventSource(stateID: .hidSystemState)
                CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 120_000_000)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 60_000_000)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 500_000_000)
                return "front=\(app.lastExternalApp?.localizedName ?? "?")"
            }
            return "no window of \(argument)"

        case "editor-state":
            // The open screenshot editor: what its buttons change.
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("screenshot:") && item.isVisible }) else { return "no editor" }
            guard let canvas = FeatureAutomation.findCanvas(in: window.contentView) else { return "no canvas" }
            let document = canvas.document
            let zoom = String(format: "%.2f", document.zoom)
            return "tool=\(document.tool.rawValue) color=\(document.color.name) size=\(document.sizeValue) marks=\(document.annotations.count) undo=\(document.canUndo) redo=\(document.canRedo) zoom=\(zoom) crop=\(document.crop != nil) badge=\(document.showBadge) corner=\(document.badgeCorner.rawValue) format=\(document.exportFormat.rawValue) width=\(document.base.width) filled=\(document.isFilled)"

        case "editor-crop":
            // editor-crop:x,y,w,h as parts of the picture (0-1): crops the open screenshot.
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("screenshot:") && item.isVisible }),
                  let canvas = FeatureAutomation.findCanvas(in: window.contentView) else { return "no editor" }
            let numbers = argument.split(separator: ",")
            guard numbers.count == 4, let x = Double(numbers[0]), let y = Double(numbers[1]), let width = Double(numbers[2]), let height = Double(numbers[3]) else { return "bad crop" }
            let document = canvas.document
            let pictureWidth = Double(document.base.width)
            let pictureHeight = Double(document.base.height)
            document.setCrop(CGRect(x: x * pictureWidth, y: y * pictureHeight, width: width * pictureWidth, height: height * pictureHeight))
            return "crop=\(document.crop != nil)"

        case "pasteboard-types":
            var names: [String] = []
            for type in NSPasteboard.general.types ?? [] {
                names.append(type.rawValue)
            }
            return names.joined(separator: ",")

        case "close-color-panel":
            NSColorPanel.shared.close()
            return "closed"

        case "open-capture":
            // open-capture:<id>: the capture's editor, as History opens it.
            guard let capture = CaptureStore.shared.captures.first(where: { item in item.id.uuidString == argument }) else { return "no capture" }
            WindowManager.shared.openEditor(for: capture)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return "opened"

        case "video-state":
            // The open video editor: what its buttons change.
            guard let model = VideoEditorModel.newest else { return "no editor" }
            let timeline = model.project.timeline
            let project = model.project
            let playhead = String(format: "%.1f", model.playhead)
            let trim = String(format: "%.1f-%.1f", timeline.trim.start, timeline.trim.end)
            return "tool=\(model.tool) playhead=\(playhead) playing=\(model.isPlaying) trim=\(trim) cuts=\(timeline.cuts.count) speeds=\(timeline.speeds.count) freezes=\(timeline.freezes.count) overlays=\(project.overlays.count) clicks=\(project.showClicks) keys=\(project.showKeys) steps=\(project.isShowingSteps) badge=\(project.showBadge) format=\(project.format.rawValue) undo=\(model.canUndo) scale=\(project.overlays.last?.effectiveScale ?? 0) clear=\(project.overlays.last?.clearBackground ?? false) lastLength=\(String(format: "%.1f", project.overlays.last?.span.duration ?? 0)) duration=\(String(format: "%.1f", model.duration)) lastBox=\(FeatureAutomation.boxText(project.overlays.last)) lastKind=\(project.overlays.last?.kind.rawValue ?? "none") lastText=\((project.overlays.last?.text ?? "").replacingOccurrences(of: " ", with: "_")) typing=\(model.editingTextID != nil) lastStart=\(String(format: "%.1f", project.overlays.last?.span.start ?? 0)) lastColor=\(String(format: "%06X", project.overlays.last?.color.hex ?? 0))"

        case "video-range":
            // video-range:<start>,<end> seconds: what dragging on the ruler selects.
            guard let model = VideoEditorModel.newest else { return "no editor" }
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let start = Double(numbers[0]), let end = Double(numbers[1]) else { return "bad range" }
            model.range = TimeSpan(start: start, end: end)
            model.seek(toSource: start)
            return "range=\(start)-\(end)"

        case "video-stage":
            // The video frame of the open editor in screen points (top-left), brought to the front,
            // for drawing on it with post-drag.
            guard let model = VideoEditorModel.newest else { return "no editor" }
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("video:") && item.isVisible }) else { return "no window" }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(nanoseconds: 400_000_000)
            let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let video = model.stageVideoRect
            let left = window.frame.minX + video.minX
            let top = mainHeight - window.frame.maxY + video.minY
            return "x=\(Int(left)) y=\(Int(top)) w=\(Int(video.width)) h=\(Int(video.height))"

        case "video-frame-diff":
            // How many pixels inside the last mark's box differ between the preview frame at the
            // playhead (with the marks) and the clip's own frame: 0 means the mark does not show.
            guard let model = VideoEditorModel.newest, let output = model.output, let mark = model.project.overlays.last else { return "no editor, preview or mark" }
            let outputTime = CMTime(seconds: output.timeMap.outputTime(forSource: model.playhead), preferredTimescale: 600)
            let sourceTime = CMTime(seconds: model.playhead, preferredTimescale: 600)
            let edited = AVAssetImageGenerator(asset: output.composition)
            edited.videoComposition = output.videoComposition
            let plain = AVAssetImageGenerator(asset: model.asset)
            for generator in [edited, plain] {
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                generator.maximumSize = CGSize(width: 640, height: 640)
            }
            guard let withMarks = try? await edited.image(at: outputTime).image, let without = try? await plain.image(at: sourceTime).image else { return "no frames" }
            let width = min(withMarks.width, without.width)
            let height = min(withMarks.height, without.height)
            guard let first = ScreenshotComparison.rgba(withMarks, width: width, height: height), let second = ScreenshotComparison.rgba(without, width: width, height: height) else { return "no pixels" }
            var box = mark.rect
            if mark.kind == .text {
                box = VideoOverlay.textBox(mark)
            }
            var changed = 0
            let minX = max(0, Int(box.minX * Double(width)) - 4)
            let maxX = min(width - 1, Int(box.maxX * Double(width)) + 4)
            let minY = max(0, Int(box.minY * Double(height)) - 4)
            let maxY = min(height - 1, Int(box.maxY * Double(height)) + 4)
            if minX <= maxX && minY <= maxY {
                for y in minY...maxY {
                    for x in minX...maxX {
                        let index = (y * width + x) * 4
                        let difference = abs(Int(first[index]) - Int(second[index])) + abs(Int(first[index + 1]) - Int(second[index + 1])) + abs(Int(first[index + 2]) - Int(second[index + 2]))
                        if difference > 60 {
                            changed += 1
                        }
                    }
                }
            }
            return "changed=\(changed) playhead=\(String(format: "%.1f", model.playhead)) span=\(String(format: "%.1f-%.1f", mark.span.start, mark.span.end))"

        case "live-state":
            // The window for drawing on the screen during a recording.
            return app.overlay.stateForChecks

        case "screen-color":
            // screen-color:x,y,w,h[:RRGGBB] (top-left screen points): pixels of the mark color (coral
            // unless given) on the screen there now, Bugbear's own windows included: whether a mark
            // really shows.
            var wanted: UInt32 = 0xFF6B4A
            if parts.count > 2, let given = UInt32(parts[2], radix: 16) {
                wanted = given
            }
            let wantedRed = Int((wanted >> 16) & 0xFF)
            let wantedGreen = Int((wanted >> 8) & 0xFF)
            let wantedBlue = Int(wanted & 0xFF)
            let numbers = argument.split(separator: ",")
            guard numbers.count == 4, let x = Double(numbers[0]), let y = Double(numbers[1]), let width = Double(numbers[2]), let height = Double(numbers[3]) else { return "bad rect" }
            let area = CGRect(x: x, y: y, width: width, height: height)
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return "no screen access" }
            guard let display = content.displays.first(where: { item in item.frame.contains(CGPoint(x: area.midX, y: area.midY)) }) else { return "no display there" }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: area.minX - display.frame.minX, y: area.minY - display.frame.minY, width: area.width, height: area.height)
            configuration.width = Int(area.width)
            configuration.height = Int(area.height)
            configuration.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return "no picture" }
            guard let pixels = ScreenshotComparison.rgba(image, width: image.width, height: image.height) else { return "no pixels" }
            var matching = 0
            var index = 0
            while index + 3 < pixels.count {
                let red = Int(pixels[index])
                let green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2])
                if abs(red - wantedRed) < 50 && abs(green - wantedGreen) < 50 && abs(blue - wantedBlue) < 50 {
                    matching += 1
                }
                index += 4
            }
            return "coral=\(matching) of \(image.width * image.height)"


        case "video-seek":
            // video-seek:<seconds|end>: moves the playhead, with no range selected.
            guard let model = VideoEditorModel.newest else { return "no editor" }
            model.range = nil
            var target = Double(argument) ?? 0
            if argument == "end" {
                target = model.project.timeline.trim.end
            }
            model.seek(toSource: target)
            return "playhead=\(String(format: "%.1f", model.playhead))"

        case "video-add-overlay":
            // video-add-overlay:<text|arrow|rectangle|blur>: a mark in the middle, selected.
            guard let model = VideoEditorModel.newest, let kind = VideoOverlay.Kind(rawValue: argument) else { return "no editor or kind" }
            model.addOverlay(kind: kind, start: CGPoint(x: 0.4, y: 0.4), end: CGPoint(x: 0.6, y: 0.6))
            // Text gets words at once, as if typed on the video and finished.
            if kind == .text, let id = model.editingTextID {
                model.setText("Bug here", of: id)
                model.finishTextEditing()
            }
            return "overlays=\(model.project.overlays.count)"

        case "editor-paste-key":
            // editor-paste-key:<canvas|elsewhere>: a picture on the clipboard and a real ⌘V in the
            // open screenshot editor, with the focus on the canvas or somewhere else in the window.
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("screenshot:") && item.isVisible }) else { return "no editor" }
            guard let canvas = FeatureAutomation.findCanvas(in: window.contentView) else { return "no canvas" }
            let document = canvas.document
            guard let shot = ImageFiles.load(document.capture.mediaURL), let png = ImageFiles.pngData(shot) else { return "no picture" }
            window.makeKeyAndOrderFront(nil)
            // A real click on the title bar brings Bugbear to the front, as a person's click would.
            let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let titlePoint = CGPoint(x: window.frame.midX, y: mainHeight - window.frame.maxY + 8)
            let press = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: titlePoint, mouseButton: .left)
            let release = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: titlePoint, mouseButton: .left)
            press?.post(tap: .cghidEventTap)
            release?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if argument == "canvas" {
                window.makeFirstResponder(canvas)
            } else {
                window.makeFirstResponder(nil)
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            let before = document.annotations.count
            try? await Task.sleep(nanoseconds: 300_000_000)
            // A real key goes to the app in front: never type into someone's chat or document.
            guard FeatureAutomation.frontAppIsBugbear() else {
                pasteboard.clearContents()
                return "not in front: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")"
            }
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 800_000_000)
            let added = document.annotations.count - before
            let isPicture = document.annotations.last?.tool == .image
            if added > 0 {
                document.undo()
            }
            return "added=\(added) picture=\(isPicture) key=\(window.isKeyWindow) active=\(NSApp.isActive)"

        case "editor-checks":
            // In the open screenshot editor: the size buttons follow the tool, the fill buttons change
            // the text being typed right away, and Delete removes the selected mark from anywhere.
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("screenshot:") && item.isVisible }) else { return "no editor" }
            guard let canvas = FeatureAutomation.findCanvas(in: window.contentView) else { return "no canvas" }
            let document = canvas.document
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            var results: [String] = []
            // A new editor draws at line size 7.
            results.append("defaultLine=\(document.stroke == .thick && Int(document.stroke.width) == 7)")

            document.tool = .text
            let textSize = document.sizeIsText && document.sizeValue == Int(document.textPoints)
            document.tool = .rectangle
            let lineSize = !document.sizeIsText && document.sizeValue == Int(document.stroke.width)
            // With a mark selected the control shows and changes that mark, not the setting for new ones.
            let savedStroke = document.stroke
            document.stroke = .heavy
            let thick = Annotation(tool: .rectangle, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 90, y: 90), color: .coral, lineWidth: document.lineWidth)
            document.add(thick)
            document.stroke = .thin
            document.tool = .select
            document.selectedId = thick.id
            let showsSelected = document.sizeValue == Int(StrokeSize.heavy.width)
            document.changeSize(by: 1)
            let grewSelected = (document.annotations.first(where: { item in item.id == thick.id })?.lineWidth ?? 0) > thick.lineWidth
            document.delete(thick.id)
            document.stroke = savedStroke
            results.append("sizeFollowsTool=\(textSize && lineSize)")
            results.append("sizeFollowsSelection=\(showsSelected && grewSelected)")

            let savedClear = document.clearTextBackground
            document.tool = .text
            document.clearTextBackground = false
            canvas.startTypingForChecks(at: CGPoint(x: 80, y: 80))
            try? await Task.sleep(nanoseconds: 300_000_000)
            let typedID = document.editingTextId
            let labelAtStart = document.annotations.first(where: { item in item.id == typedID })?.hasClearBackground == false
            document.setFilled(false)
            try? await Task.sleep(nanoseconds: 400_000_000)
            let clearAfterNoFill = document.annotations.first(where: { item in item.id == typedID })?.hasClearBackground == true
            // The field shows only the caret, so the text is never drawn twice.
            let fieldIsClear = canvas.typingFieldDrawsText == false
            results.append("typingNoFillAtOnce=\(labelAtStart && clearAfterNoFill)")
            results.append("textDrawnOnce=\(fieldIsClear)")
            window.makeFirstResponder(nil)
            document.clearTextBackground = savedClear

            // Arrow with text: the note opens for typing as soon as the arrow is drawn; left empty,
            // a plain arrow stays.
            let toolBefore = document.tool
            document.tool = .callout
            canvas.drawForChecks(from: CGPoint(x: 140, y: 140), to: CGPoint(x: 260, y: 200))
            try? await Task.sleep(nanoseconds: 300_000_000)
            let noteID = document.editingTextId
            let typingAtOnce = noteID != nil && document.annotations.first(where: { item in item.id == noteID })?.tool == .callout
            canvas.finishTypingForChecks("Wrong total")
            let keptNote = document.annotations.first(where: { item in item.id == noteID })
            let noteSaved = keptNote?.tool == .callout && keptNote?.text == "Wrong total"
            canvas.drawForChecks(from: CGPoint(x: 140, y: 260), to: CGPoint(x: 260, y: 320))
            try? await Task.sleep(nanoseconds: 300_000_000)
            let emptyID = document.editingTextId
            canvas.finishTypingForChecks("")
            let leftEmpty = document.annotations.first(where: { item in item.id == emptyID })
            let becameArrow = emptyID != nil && leftEmpty?.tool == .arrow
            results.append("calloutTyping=\(typingAtOnce && noteSaved)")
            results.append("calloutEmptyIsArrow=\(becameArrow)")
            if let id = noteID {
                document.delete(id)
            }
            if let id = emptyID {
                document.delete(id)
            }
            document.tool = toolBefore

            // ⌘V with a picture on the clipboard places it on the screenshot, selected.
            if let shot = ImageFiles.load(document.capture.mediaURL), let png = ImageFiles.pngData(shot) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(png, forType: .png)
                let pasted = canvas.pasteImage()
                let placed = document.annotations.last
                let fileSaved = placed?.imagePath.map { path in FileManager.default.fileExists(atPath: path) } ?? false
                results.append("pasteImage=\(pasted && placed?.tool == .image && fileSaved && document.selectedId == placed?.id)")
                if let id = placed?.id, placed?.tool == .image {
                    document.delete(id)
                }
            }

            // Delete in the editor window with the focus away from the canvas: the window's key handling,
            // not delivery from the keyboard (the key is posted into Bugbear's own event queue).
            let box = Annotation(tool: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 60, y: 60), color: .coral, lineWidth: 4)
            document.add(box)
            document.tool = .select
            document.selectedId = box.id
            window.makeFirstResponder(nil)
            // Let the typing field from the step above give up the focus first; while a field types,
            // Delete belongs to it.
            try? await Task.sleep(nanoseconds: 400_000_000)
            // The key is sent to Bugbear itself, never to whatever app is in front (the browser the
            // features test opened can take the focus at any moment).
            // It goes into Bugbear's own event queue for the editor window, so it takes the same way as
            // a real key press (the window's key monitor included).
            window.makeKeyAndOrderFront(nil)
            for type in [NSEvent.EventType.keyDown, NSEvent.EventType.keyUp] {
                if let key = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51) {
                    NSApp.postEvent(key, atStart: false)
                }
            }
            var deleted = false
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !document.annotations.contains(where: { item in item.id == box.id }) {
                    deleted = true
                    break
                }
            }
            results.append("deleteInEditorWindow=\(deleted)")
            return results.joined(separator: " ")

        case "tooltip-probe":
            // tooltip-probe:<window id prefix|menubar>,<x>,<y>: points at x,y (from the window's
            // top-left), waits, and reports how many Bugbear tooltips are on screen.
            let parts = argument.split(separator: ",")
            guard parts.count == 3, let offsetX = Double(parts[1]), let offsetY = Double(parts[2]) else { return "bad argument" }
            // "menubar" is the panel under the bear; it is checked without making the app active.
            let isMenuPanel = parts[0] == "menubar"
            var found: NSWindow?
            for item in NSApp.windows where item.isVisible {
                if isMenuPanel && item.className.contains("MenuBarExtra") {
                    found = item
                }
                if !isMenuPanel && (item.identifier?.rawValue ?? "").hasPrefix(String(parts[0])) {
                    found = item
                }
            }
            guard let window = found else { return "no window" }
            if isMenuPanel {
                // The way it is used: another app in front, Bugbear not active.
                NSApp.deactivate()
                try? await Task.sleep(nanoseconds: 300_000_000)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            HoverTip.shared.hide()
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let point = CGPoint(x: window.frame.minX + offsetX, y: primaryHeight - window.frame.maxY + offsetY)
            let source = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: point.x - 30, y: point.y), mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 300_000_000)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            var tooltips = 0
            for item in NSApp.windows where item.isVisible && item is HoverTipPanel {
                tooltips += 1
            }
            return "key=\(window.isKeyWindow) active=\(NSApp.isActive) tooltips=\(tooltips)"

        case "move-pointer":
            // move-pointer:x,y (top-left screen points), e.g. onto the second display.
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let x = Double(numbers[0]), let y = Double(numbers[1]) else { return "bad point" }
            let source = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 200_000_000)
            return "pointer \(Int(x)),\(Int(y))"

        case "screens":
            // Every display: AppKit frame, scale, and which one holds the pointer.
            var lines: [String] = []
            let mouse = NSEvent.mouseLocation
            for screen in NSScreen.screens {
                let frame = screen.frame
                let pointer = frame.contains(mouse) ? " pointer" : ""
                lines.append("\(AppState.displayID(of: screen)):\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))@\(screen.backingScaleFactor)\(pointer)")
            }
            return lines.joined(separator: ";")

        case "post-click":
            // post-click:x,y (top-left screen points): a real left click.
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let x = Double(numbers[0]), let y = Double(numbers[1]) else { return "bad point" }
            let point = CGPoint(x: x, y: y)
            let source = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 120_000_000)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 60_000_000)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            return "clicked \(Int(x)),\(Int(y))"

        case "post-drag":
            // post-drag:x1,y1:x2,y2 (top-left screen points): press, move in steps, release.
            let from = argument.split(separator: ",")
            let to = (parts.count > 2 ? parts[2] : "").split(separator: ",")
            guard from.count == 2, to.count == 2, let x1 = Double(from[0]), let y1 = Double(from[1]), let x2 = Double(to[0]), let y2 = Double(to[1]) else { return "bad points" }
            let source = CGEventSource(stateID: .hidSystemState)
            let start = CGPoint(x: x1, y: y1)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 100_000_000)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
            for step in 1...10 {
                let progress = Double(step) / 10
                let point = CGPoint(x: x1 + (x2 - x1) * progress, y: y1 + (y2 - y1) * progress)
                try? await Task.sleep(nanoseconds: 30_000_000)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: x2, y: y2), mouseButton: .left)?.post(tap: .cghidEventTap)
            return "dragged"

        case "record-area-picker":
            // Opens the real area picker; the script then clicks and presses Return.
            Task { await app.startRecording(target: .area) }
            return "opening"
        case "picker-chips":
            var texts: [String] = []
            for chip in app.regionSelector.chipCenters {
                texts.append("\(chip.title)@\(Int(chip.point.x)),\(Int(chip.point.y))")
            }
            return texts.joined(separator: ";")
        case "recording-region":
            guard let region = app.recordingRegion else { return "none recording=\(app.recording != nil)" }
            return "region=\(Int(region.global.width))x\(Int(region.global.height)) recording=\(app.recording != nil) outline=\(app.recordingOutline.windowCount)"

        case "frame-of-latest":
            // frame-of-latest:<seconds>:<png path> from the newest video
            guard let clip = app.store.captures.first(where: { item in item.kind == .video }), parts.count > 2 else { return "no video" }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.mediaURL))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let seconds = Double(argument) ?? 1
            guard let frame = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image else { return "no frame" }
            ImageFiles.write(frame, to: URL(fileURLWithPath: parts[2]), type: "public.png")
            return "frame=\(frame.width)x\(frame.height)"

        case "pick-color-test":
            // Opens the system color loupe; the script clicks somewhere to pick.
            guard let color = await ColorPick.pick() else { return "cancelled" }
            return "hex=\(ColorConverter.formats(color).hex)"

        case "resize-front":
            // resize-front:1280x720
            let numbers = argument.split(separator: "x")
            guard numbers.count == 2, let width = Double(numbers[0]), let height = Double(numbers[1]) else { return "bad size" }
            let result = WindowResizer.resize(app: app.lastExternalApp, to: CGSize(width: width, height: height))
            switch result {
            case .success(let size):
                return "app=\(app.lastExternalApp?.localizedName ?? "?") size=\(Int(size.width))x\(Int(size.height))"
            case .failure(let failure):
                return "error \(failure)"
            }

        case "ruler-start":
            app.startRuler()
            return "active=\(ScreenRuler.shared.isActive)"
        case "ruler-stop":
            ScreenRuler.shared.stop()
            return "active=\(ScreenRuler.shared.isActive)"
        case "ruler-state":
            return "active=\(ScreenRuler.shared.isActive)"

        case "screen-tools":
            // What is open on the screen: drawing, ruler, color loupe, recording.
            return "drawing=\(app.overlay.isDrawing) ruler=\(ScreenRuler.shared.isActive) picking=\(ColorPick.isPicking) recording=\(app.recording != nil) paused=\(app.recording?.isPaused ?? false) target=\(app.recordingTarget) liveTool=\(app.overlay.tool.rawValue) liveColor=\(app.overlay.color.rawValue) fade=\(app.overlay.autoFade)"

        case "overlay-test":
            // overlay-test:<pixels per point>; a 1400×800 px test design.
            let image = NSImage(size: CGSize(width: 1400, height: 800), flipped: false) { rect in
                NSColor(hex: 0x4C9BFF).setFill()
                rect.fill()
                NSColor.white.setFill()
                CGRect(x: 100, y: 100, width: 600, height: 300).fill()
                return true
            }
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return "no image" }
            let design = NSImage(size: CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            design.addRepresentation(bitmap)
            DesignOverlay.shared.show(design)
            DesignOverlay.shared.scale = Double(argument) ?? 2
            DesignOverlay.shared.opacity = 0.4
            return "open=\(DesignOverlay.shared.isOpen) \(DesignOverlay.shared.debugFrame)"
        case "overlay-click-through":
            DesignOverlay.shared.clickThrough = argument == "true"
            return DesignOverlay.shared.debugFrame
        case "overlay-state":
            return DesignOverlay.shared.debugFrame
        case "overlay-close":
            DesignOverlay.shared.close()
            return "open=\(DesignOverlay.shared.isOpen)"

        case "fields-count":
            return "fields=\(app.settings.reportFields.count)"

        case "report-settings-save", "report-settings-restore":
            // report-settings-save:<file> keeps the person's fields and field choices in a file,
            // report-settings-restore:<file> puts them back exactly, whatever the values hold.
            let path = parts.count > 1 ? parts[1...].joined(separator: ":") : ""
            guard !path.isEmpty else { return "no file" }
            let url = URL(fileURLWithPath: path)
            if name == "report-settings-save" {
                let saved = SavedReportSettings(fields: app.settings.reportFields, hidden: app.settings.hiddenEnvironmentFields, renamed: app.settings.renamedEnvironmentFields)
                guard let data = try? JSONEncoder().encode(saved), (try? data.write(to: url)) != nil else { return "not saved" }
                return "saved fields=\(saved.fields.count)"
            }
            guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(SavedReportSettings.self, from: data) else { return "nothing saved" }
            app.settings.reportFields = saved.fields
            app.settings.hiddenEnvironmentFields = saved.hidden
            app.settings.renamedEnvironmentFields = saved.renamed
            return "restored fields=\(saved.fields.count)"

        case "fields-read":
            // The person's own fields as "fields:" takes them, to put them back after a test.
            var pairs: [String] = []
            for field in app.settings.reportFields {
                pairs.append("\(field.name)=\(field.value)")
            }
            return pairs.joined(separator: ",")

        case "fields":
            // fields:Stand=stage-3,Build=1.42  (empty clears)
            var fields: [EnvironmentSnapshot.Field] = []
            for pair in argument.split(separator: ",") {
                let pieces = pair.split(separator: "=", maxSplits: 1)
                if pieces.count == 2 {
                    fields.append(EnvironmentSnapshot.Field(name: String(pieces[0]), value: String(pieces[1])))
                }
            }
            app.settings.reportFields = fields
            return "fields=\(fields.count)"

        case "report":
            // report:markdown|jira, for the newest capture; the text goes to the clipboard.
            guard let latest = app.store.captures.first else { return "no capture" }
            var format = BugReport.Format.markdown
            if argument == "jira" {
                format = .jira
            }
            BugReportBuilder.copy(for: latest, timeMap: nil, format: format)
            return "copied format=\(format.rawValue) default=\(app.settings.bugReportFormat)"

        case "extras-latest":
            guard let latest = app.store.captures.first else { return "no capture" }
            var texts: [String] = []
            for field in latest.environment.extras ?? [] {
                texts.append("\(field.name)=\(field.value)")
            }
            return "extras=\(texts.joined(separator: ","))"

        case "guide-latest":
            // guide-latest:<count>:<folder>
            let count = Int(argument) ?? 2
            let folder = parts.count > 2 ? parts[2] : AppPaths.temporary.path
            var shots: [Capture] = []
            for capture in app.store.captures where capture.kind == .screenshot && shots.count < count {
                shots.append(capture)
            }
            if shots.count < count { return "only \(shots.count) screenshots" }
            WindowManager.shared.openStepGuide(captures: shots)
            let model = StepGuideModel(captures: shots)
            model.steps[0].caption = "Open the page"
            var blocks: [(image: CGImage, caption: String)] = []
            for step in model.steps {
                blocks.append((image: step.image, caption: step.caption))
            }
            let png = URL(fileURLWithPath: folder).appendingPathComponent("guide.png")
            let pdf = URL(fileURLWithPath: folder).appendingPathComponent("guide.pdf")
            guard let image = StepGuideRenderer.longImage(title: "E2E guide", steps: blocks) else { return "no image" }
            ImageFiles.write(image, to: png, type: "public.png")
            let wrote = StepGuideRenderer.writePDF(title: "E2E guide", steps: blocks, to: pdf)
            let pages = CGPDFDocument(pdf as CFURL)?.numberOfPages ?? 0
            return "steps=\(model.steps.count) png=\(image.width)x\(image.height) pdf=\(wrote) pages=\(pages)"

        case "compare-latest" where argument == "video":
            // compare-latest:video: the two newest clips side by side.
            var clips: [Capture] = []
            for capture in app.store.captures where capture.kind == .video && clips.count < 2 {
                clips.append(capture)
            }
            if clips.count < 2 { return "need 2 clips" }
            WindowManager.shared.openCompare(clips[1], clips[0])
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return "opened"

        case "compare-latest":
            var shots: [Capture] = []
            for capture in app.store.captures where capture.kind == .screenshot && shots.count < 2 {
                shots.append(capture)
            }
            if shots.count < 2 { return "need 2 screenshots" }
            WindowManager.shared.openCompare(shots[0], shots[1])
            guard let output = ScreenshotComparison.make(before: shots[1], after: shots[0]) else { return "no comparison" }
            return "regions=\(output.result.regions.count) changed=\(String(format: "%.3f", output.result.changedShare))"

        case "hotkey-set":
            // hotkey-set:<action>:<keyCode>:<cmd,shift,option,control>
            guard let action = HotKeyAction(rawValue: argument), parts.count > 3, let keyCode = UInt32(parts[2]) else { return "bad hotkey" }
            let shortcut = Shortcut(keyCode: keyCode, modifiers: carbonModifiers(parts[3]), key: "?")
            if let owner = HotKeySettings.shared.owner(of: shortcut, except: action) {
                return "conflict with \(owner.rawValue)"
            }
            HotKeySettings.shared.set(shortcut, for: action)
            return "set \(action.rawValue)=\(HotKeySettings.shared.text(for: action))"
        case "hotkey-reset":
            HotKeySettings.shared.resetAll()
            return "customized=\(HotKeySettings.shared.isCustomized)"
        case "post-move":
            // post-move:x,y (top-left screen points): moves the pointer there, no click.
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let x = Double(numbers[0]), let y = Double(numbers[1]) else { return "bad point" }
            CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 200_000_000)
            return "moved"

        case "screen-center":
            // screen-center:<index>: the middle of that display in top-left screen points.
            let index = Int(argument) ?? 0
            let screens = NSScreen.screens
            guard index >= 0 && index < screens.count else { return "no screen \(index)" }
            let mainHeight = screens[0].frame.maxY
            let frame = screens[index].frame
            return "x=\(Int(frame.midX)) y=\(Int(mainHeight - frame.midY)) count=\(screens.count)"

        case "post-text":
            // post-text:<words>: real typing of the words, one character at a time.
            if !FeatureAutomation.frontAppTakesTestKeys() {
                return "not in front: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")"
            }
            let words = parts.count > 1 ? parts[1...].joined(separator: ":") : ""
            for character in words {
                let units = Array(String(character).utf16)
                let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
                down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
                up?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            return "typed \(words.count)"

        case "post-key":
            // post-key:<keyCode>:<modifiers>: a real key press through the HID event tap.
            guard let keyCode = CGKeyCode(argument), parts.count > 2 else { return "bad key" }
            // Real keys go to the app in front. Only Bugbear and the test browser may get them, so
            // a test never types into someone's chat or document. Bugbear's own shortcuts are the
            // exception: macOS hands them to Bugbear before any app sees them.
            if !FeatureAutomation.isOwnShortcut(keyCode: keyCode, flags: parts[2]) && !FeatureAutomation.frontAppTakesTestKeys() {
                return "not in front: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")"
            }
            let flags = cgFlags(parts[2])
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            down?.flags = flags
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            up?.flags = flags
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            return "posted"

        case "record-area":
            // record-area:x,y,w,h
            guard let area = selection(argument) else { return "bad area" }
            await app.startRecording(target: .area, presetRegion: area)
            return "recording=\(app.recording != nil) outline=\(app.recordingOutline.windowCount) region=\(Int(area.global.width))x\(Int(area.global.height))"

        case "cleanup-dryrun":
            // cleanup-dryrun:<days>:<GB>: what the limits would delete, without deleting.
            let days = Int(argument) ?? 0
            let gigabytes = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
            let sizes = await app.store.measureSizes()
            var items: [StoragePolicy.Item] = []
            var total: Int64 = 0
            for capture in app.store.captures {
                let bytes = sizes[capture.id] ?? 0
                total += bytes
                items.append(StoragePolicy.Item(id: capture.id, createdAt: capture.createdAt, bytes: bytes))
            }
            let doomed = StoragePolicy.itemsToDelete(items, now: Date(), maxAgeDays: days, maxBytes: Int64(gigabytes) * 1_000_000_000, protected: [])
            return "captures=\(items.count) total=\(total) wouldDelete=\(doomed.count)"

        case "video-size-test":
            guard let clip = app.store.captures.first(where: { item in item.kind == .video }) else { return "no video" }
            let model = VideoEditorModel(capture: clip)
            model.addOverlay(kind: .arrow, start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.5, y: 0.5))
            var steps: [String] = []
            steps.append("\(Int((model.selectedOverlay?.effectiveScale ?? 0) * 100))")
            model.changeSelectedOverlaySize(by: 1)
            model.changeSelectedOverlaySize(by: 1)
            steps.append("\(Int((model.selectedOverlay?.effectiveScale ?? 0) * 100))")
            for _ in 0..<12 {
                model.changeSelectedOverlaySize(by: 1)
            }
            steps.append("\(Int((model.selectedOverlay?.effectiveScale ?? 0) * 100))")
            model.addOverlay(kind: .text, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.1, y: 0.1))
            let newMarkScale = Int((model.selectedOverlay?.effectiveScale ?? 0) * 100)
            model.deleteSelection()
            model.tearDown()
            return "arrow % \(steps.joined(separator: "→")) newMark=\(newMarkScale)"

        case "editor-size-test":
            return editorSizeTest()

        default:
            return nil
        }
    }

    /// Normalized "x,y,w,h" on the screen under the pointer.
    private static func selection(_ text: String) -> RegionSelector.Selection? {
        var numbers: [CGFloat] = []
        for piece in text.split(separator: ",") {
            guard let value = Double(piece) else { return nil }
            numbers.append(CGFloat(value))
        }
        guard numbers.count == 4 else { return nil }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { item in item.frame.contains(mouse) }) ?? NSScreen.main else { return nil }
        let normalized = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        let frame = screen.frame
        let global = CGRect(x: frame.minX + normalized.minX * frame.width, y: frame.maxY - normalized.maxY * frame.height, width: normalized.width * frame.width, height: normalized.height * frame.height)
        return RegionSelector.Selection(screen: screen, normalized: normalized, global: global)
    }

    /// Visible frame of the first AXWebArea in the app's focused window, in top-left screen points. The web
    /// area itself spans the whole page, so it is cut to the scroll area around it.
    /// The browser web-area asked for its accessibility tree, so the tests can switch it off again.
    private static var browserWithAccessibility: pid_t?

    private static func webAreaFrame(of running: NSRunningApplication) -> CGRect? {
        let application = AXUIElementCreateApplication(running.processIdentifier)
        // Chromium browsers build the page's accessibility tree only on request (or while another
        // assistive app runs): ask for it. Other apps ignore the attribute.
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        browserWithAccessibility = running.processIdentifier
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success, let window = focused, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var queue: [(element: AXUIElement, parent: AXUIElement?)] = [(element: window as! AXUIElement, parent: nil)]
        var visited = 0
        while !queue.isEmpty && visited < 400 {
            let item = queue.removeFirst()
            visited += 1
            var role: AnyObject?
            AXUIElementCopyAttributeValue(item.element, kAXRoleAttribute as CFString, &role)
            if let roleName = role as? String, roleName == "AXWebArea" {
                guard let page = frame(of: item.element) else { return nil }
                guard let parent = item.parent, let visible = frame(of: parent) else { return page }
                return page.intersection(visible)
            }
            var children: AnyObject?
            if AXUIElementCopyAttributeValue(item.element, kAXChildrenAttribute as CFString, &children) == .success, let list = children as? [AXUIElement] {
                for child in list {
                    queue.append((element: child, parent: item.element))
                }
            }
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionFound = positionValue, let sizeFound = sizeValue else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionFound as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeFound as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func carbonModifiers(_ text: String) -> UInt32 {
        var flags: UInt32 = 0
        if text.contains("cmd") { flags |= 256 }       // cmdKey
        if text.contains("shift") { flags |= 512 }     // shiftKey
        if text.contains("option") { flags |= 2048 }   // optionKey
        if text.contains("control") { flags |= 4096 }  // controlKey
        return flags
    }

    /// The buffer state before `buffer-needs-permission:on`, put back by `:off`.
    private static var stateBeforePermissionFake: AppState.BufferState?

    /// The person's report settings while a test changes them.
    private struct SavedReportSettings: Codable {
        var fields: [EnvironmentSnapshot.Field]
        var hidden: [String]
        var renamed: [String: String]
    }

    /// Settings shows one page at a time: before a control of it is used, the page that has it
    /// is shown. The current page is kept when it has the control.
    private static func showSettingsPage(with label: String, window name: String) async {
        guard name == "settings", let window = controlWindows(name).first else { return }
        var wanted = label
        for suffix in ["#increment", "#decrement", "#last"] where wanted.hasSuffix(suffix) {
            wanted = String(wanted.dropLast(suffix.count))
        }
        if ControlTree.frame(label: wanted, inWindowAt: topLeftFrame(window), scrollIntoView: true) != nil { return }
        let shown = SettingsNavigation.shared.page
        for page in SettingsPage.allCases where page != shown {
            SettingsNavigation.shared.page = page
            try? await Task.sleep(nanoseconds: 300_000_000)
            if ControlTree.frame(label: wanted, inWindowAt: topLeftFrame(window), scrollIntoView: true) != nil { return }
        }
        SettingsNavigation.shared.page = shown
    }

    /// The windows a control command looks in: "menubar" for the menu bar panel, otherwise
    /// windows whose id starts with the name (editor-…, settings, onboarding).
    private static func controlWindows(_ name: String) -> [NSWindow] {
        var windows: [NSWindow] = []
        for window in NSApp.windows where window.isVisible {
            if name == "menubar" {
                if window.className.contains("MenuBarExtra") {
                    windows.append(window)
                }
            } else if name == "popover" {
                if window.className.contains("Popover") {
                    windows.append(window)
                }
            } else if let id = window.identifier?.rawValue, id.hasPrefix(name) {
                windows.append(window)
            }
        }
        return windows
    }

    static func frontAppIsBugbear() -> Bool {
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// Bugbear itself or a browser (the e2e tests drive a test page in one).
    static func frontAppTakesTestKeys() -> Bool {
        if frontAppIsBugbear() {
            return true
        }
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return EnvironmentCollector.browserScripts[bundleId] != nil
    }

    /// A window's frame the way the Accessibility API gives it: top-left of the main screen.
    private static func topLeftFrame(_ window: NSWindow) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = window.frame
        return CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Whether the key with these modifiers ("option,shift") is one of Bugbear's shortcuts now.
    static func isOwnShortcut(keyCode: CGKeyCode, flags: String) -> Bool {
        var modifiers: UInt32 = 0
        if flags.contains("cmd") { modifiers |= UInt32(cmdKey) }
        if flags.contains("shift") { modifiers |= UInt32(shiftKey) }
        if flags.contains("option") { modifiers |= UInt32(optionKey) }
        if flags.contains("control") { modifiers |= UInt32(controlKey) }
        for action in HotKeyAction.allCases {
            guard let shortcut = HotKeySettings.shared.shortcut(for: action) else { continue }
            if shortcut.keyCode == UInt32(keyCode) && shortcut.modifiers == modifiers {
                return true
            }
        }
        return false
    }

    private static func cgFlags(_ text: String) -> CGEventFlags {
        var flags: CGEventFlags = []
        if text.contains("cmd") { flags.insert(.maskCommand) }
        if text.contains("shift") { flags.insert(.maskShift) }
        if text.contains("option") { flags.insert(.maskAlternate) }
        if text.contains("control") { flags.insert(.maskControl) }
        return flags
    }

    /// + and - on a test screenshot and video, the way the editors do it.
    private static func editorSizeTest() -> String {
        guard let shot = CaptureStore.shared.captures.first(where: { item in item.kind == .screenshot }), let document = ScreenshotDocument(capture: shot) else { return "no screenshot" }
        var results: [String] = []
        let arrow = Annotation(tool: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 200, y: 200), color: .yellow, lineWidth: document.lineWidth)
        document.annotations.append(arrow)
        document.selectedId = arrow.id
        let widthBefore = document.selected?.lineWidth ?? 0
        document.changeSize(by: 1)
        let widthAfter = document.selected?.lineWidth ?? 0
        results.append("arrowWidth=\(Int(widthBefore))->\(Int(widthAfter)) color=\(document.selected?.color.rawValue ?? "?")")
        var text = Annotation(tool: .text, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50), color: .coral, lineWidth: document.lineWidth)
        text.fontSize = document.fontSize
        text.text = "E2E"
        document.annotations.append(text)
        document.selectedId = text.id
        let fontBefore = document.selected?.fontSize ?? 0
        document.changeSize(by: 1)
        document.changeSize(by: 1)
        let fontAfter = document.selected?.fontSize ?? 0
        results.append("textFont=\(Int(fontBefore))->\(Int(fontAfter))")
        // Leave the test screenshot as it was.
        document.undo()
        document.undo()
        document.annotations.removeAll { item in item.id == arrow.id || item.id == text.id }
        document.saveProject()
        return results.joined(separator: " ")
    }
}

extension FeatureAutomation {
    /// The drawing canvas inside an editor window.
    /// "minX,minY,maxX,maxY" of a video mark in 0…1 frame coordinates, two decimals.
    static func boxText(_ overlay: VideoOverlay?) -> String {
        guard let mark = overlay else { return "none" }
        let box = mark.rect
        return String(format: "%.2f,%.2f,%.2f,%.2f", box.minX, box.minY, box.maxX, box.maxY)
    }

    static func findCanvas(in view: NSView?) -> CanvasView? {
        guard let current = view else { return nil }
        if let canvas = current as? CanvasView {
            return canvas
        }
        for child in current.subviews {
            if let found = findCanvas(in: child) {
                return found
            }
        }
        return nil
    }
}
