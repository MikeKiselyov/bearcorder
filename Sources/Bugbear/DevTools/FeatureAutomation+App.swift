// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI
import BugbearCore

@MainActor
extension FeatureAutomation {
    static func runApp(_ name: String, _ argument: String, _ parts: [String], _ app: AppState) async -> String? {
        switch name {
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
            // The app's visible windows (panels too): their id, or the class for windows without one.
            var names: [String] = []
            for window in NSApp.windows where window.isVisible {
                var name = window.identifier?.rawValue ?? ""
                if name.isEmpty || name.hasPrefix("_NS") || name.contains("SwiftUI") {
                    name = window.className
                }
                names.append(name)
            }
            return names.joined(separator: ";")

        case "windows-at":
            // windows-at:x,y (top-left screen points): the app's visible windows over that point, front
            // first, with their level: what a click there would hit.
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let x = Double(numbers[0]), let y = Double(numbers[1]), let primary = NSScreen.screens.first else { return "bad point" }
            let point = CGPoint(x: x, y: primary.frame.maxY - y)
            var hits: [String] = []
            for number in NSWindow.windowNumbers(options: []) ?? [] {
                guard let window = NSApp.window(withWindowNumber: number.intValue), window.isVisible, window.frame.contains(point) else { continue }
                var name = window.identifier?.rawValue ?? ""
                if name.isEmpty || name.hasPrefix("_NS") || name.contains("SwiftUI") {
                    name = window.className
                }
                var hit = "\(name)@\(window.level.rawValue)\(window.ignoresMouseEvents ? "(click-through)" : "")"
                // The view a click there goes to, and the views it sits in.
                if let content = window.contentView, let superview = content.superview {
                    let local = superview.convert(window.convertPoint(fromScreen: point), from: nil)
                    var view = content.hitTest(local)
                    var chain: [String] = []
                    while let current = view, chain.count < 4 {
                        chain.append(String(describing: type(of: current)).components(separatedBy: "<").first ?? "")
                        view = current.superview
                    }
                    hit += " view=" + chain.joined(separator: "<")
                }
                hits.append(hit)
            }
            return hits.isEmpty ? "none" : hits.joined(separator: ";")

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

        case "press-menu":
            // press-menu:<tab>:<label>: closes the panel, opens it from the status item, presses the
            // tab and then the control, and returns what `press:menubar:<label>` returns. One command
            // for what press_menu in e2e-helpers.sh did with four. A tab that cannot be pressed ends
            // it there, so the label is never pressed on whatever tab happens to show.
            guard parts.count > 2 else { return "bad press-menu" }
            app.closeMenuPanel()
            try? await Task.sleep(nanoseconds: 300_000_000)
            app.statusItemButton()?.performClick(nil)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let tab = parts[1]
            let tabResult = await runControls("press", "menubar", ["press", "menubar", tab], app)
            if tabResult != "pressed" {
                return "tab not found: \(tab)"
            }
            let label = parts[2...].joined(separator: ":")
            return await runControls("press", "menubar", ["press", "menubar", label], app)

        case "close-panel":
            app.closeMenuPanel()
            try? await Task.sleep(nanoseconds: 300_000_000)
            return "open=\(app.isMenuPanelOpen)"

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

        default:
            return nil
        }
    }
}
#endif
