import AVFoundation
import AppKit
import BugbearCore

/// Local automation for end-to-end tests (scripts/e2e.sh). Off by default; enable with
///   defaults write <bundle id> automationEnabled -bool true
/// Commands arrive as a distributed notification "Bugbear.automation" with userInfo["command"];
/// results are written to the log as "AUTOMATION <command> → <result>".
@MainActor
enum Automation {
    static var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "automationEnabled")
    }

    static func install() {
        guard isEnabled else { return }
        Log.info("automation enabled")
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("Bugbear.automation"), object: nil, queue: .main) { notification in
            let command = notification.userInfo?["command"] as? String ?? (notification.object as? String ?? "")
            MainActor.assumeIsolated {
                Task { await run(command) }
            }
        }
    }

    private static func report(_ command: String, _ result: String) {
        Log.info("AUTOMATION \(command) → \(result)")
    }

    static func run(_ command: String) async {
        let app = AppState.shared
        let parts = command.split(separator: ":").map(String.init)
        let name = parts.first ?? ""
        switch name {
        case "status":
            app.refreshStatus(force: true)
            var state = "\(app.bufferState)"
            state += " covered=\(Int(app.coveredSeconds)) recording=\(app.recording != nil) paused=\(app.recording?.isPaused ?? false) captures=\(app.store.captures.count) displays=\(app.buffers.count)"
            report(command, state)
        case "setting":
            // setting:<name>:<true|false>, changed in the running app like the Settings window does.
            let value = parts.count > 2 && parts[2] == "true"
            let settingName = parts.count > 1 ? parts[1] : ""
            switch settingName {
            case "recordSystemAudio": app.settings.recordSystemAudio = value
            case "recordMicrophone": app.settings.recordMicrophone = value
            case "captureAllDisplays": app.settings.captureAllDisplays = value
            case "showsCursor": app.settings.showsCursor = value
            case "readBrowserURL": app.settings.readBrowserURL = value
            default:
                report(command, "unknown setting")
                return
            }
            report(command, "\(settingName)=\(value)")
        case "buffer-start":
            await app.startBuffer()
            report(command, "\(app.bufferState)")
        case "save":
            let seconds = Double(parts.count > 1 ? parts[1] : "10") ?? 10
            let before = app.store.captures.first?.id
            await app.saveFromBuffer(seconds: seconds)
            report(command, describeLatest(before: before))
        case "record-start":
            await app.startRecording(target: .screens)
            report(command, (app.recording != nil ? "recording" : "not recording") + " outline=\(app.recordingOutline.windowCount) screens=\(NSScreen.screens.count)")
        case "record-pause":
            app.recording?.pause()
            report(command, "paused=\(app.recording?.isPaused ?? false)")
        case "record-resume":
            app.recording?.resume()
            report(command, "paused=\(app.recording?.isPaused ?? false)")
        case "record-stop":
            let elapsed = app.recording?.elapsed() ?? 0
            let before = app.store.captures.first?.id
            await app.stopRecording()
            report(command, "elapsed=\(String(format: "%.2f", elapsed)) " + describeLatest(before: before))
        case "crash-watch":
            // crash-watch:<folder> watches a test folder and accepts crashes from any app.
            let folder = URL(fileURLWithPath: parts.count > 1 ? parts[1] : "", isDirectory: true)
            app.crashWatcher.acceptsAnyApp = true
            app.crashWatcher.start(folder: folder)
            report(command, "watching \(folder.path)")
        case "update-run":
            Updater.shared.update()
            report(command, "\(Updater.shared.state)")
        case "update-state":
            report(command, "\(Updater.shared.state)")
        case "whats-new":
            WhatsNewTracker.openLatest()
            report(command, "opened")
        case "update-check":
            await Updater.shared.check(userInitiated: true)
            report(command, "\(Updater.shared.state)")
        case "mark":
            app.markMoment()
            report(command, "marked")
        case "draw-toggle":
            app.toggleDrawing()
            report(command, "visible=\(app.overlay.isVisible) drawing=\(app.overlay.isDrawing)")
        case "draw-hide":
            app.hideOverlay()
            report(command, "visible=\(app.overlay.isVisible)")
        case "screenshot-full":
            let before = app.store.captures.first?.id
            await app.takeScreenshot(.fullScreen)
            report(command, describeLatest(before: before))
        case "screenshot-all":
            let before = app.store.captures.first?.id
            await app.takeScreenshot(.allDisplays)
            report(command, describeLatest(before: before))
        case "export-latest":
            await exportLatestVideo(command)
        case "close-windows":
            for window in NSApp.windows where window.isVisible && window.title != "" {
                window.close()
            }
            report(command, "ok")
        default:
            if let result = await FeatureAutomation.run(parts) {
                report(command, result)
            } else {
                report(command, "unknown command")
            }
        }
    }

    private static func describeLatest(before: UUID?) -> String {
        guard let latest = CaptureStore.shared.captures.first, latest.id != before else {
            return "no new capture"
        }
        return "capture=\(latest.id) kind=\(latest.kind.rawValue) duration=\(String(format: "%.2f", latest.duration)) file=\(latest.mediaURL.path)"
    }

    /// Runs the editor pipeline on the newest clip with a few edits, like a user would.
    private static func exportLatestVideo(_ command: String) async {
        guard let capture = CaptureStore.shared.captures.first(where: { item in item.kind == .video }) else {
            report(command, "no video capture")
            return
        }
        var project = VideoProject(duration: capture.duration)
        let duration = capture.duration
        project.timeline.trim = TimeSpan(start: min(0.5, duration / 4), end: duration)
        project.timeline.speeds = [SpeedEdit(span: TimeSpan(start: duration / 2, end: duration / 2 + 1), factor: 0.5)]
        project.overlays = [VideoOverlay(kind: .text, span: TimeSpan(start: 0, end: duration), start: CGPoint(x: 0.05, y: 0.05), end: CGPoint(x: 0.05, y: 0.05), text: "E2E", color: .coral)]
        project.showBadge = true
        do {
            let output = try await VideoCompositor.build(asset: AVURLAsset(url: capture.mediaURL), project: project, events: capture.events, environment: capture.environment)
            let url = AppPaths.temporary.appendingPathComponent("e2e-export.mp4")
            try await VideoCompositor.exportMP4(output, quality: .p720, to: url, progress: nil)
            let exported = try await AVURLAsset(url: url).load(.duration).seconds
            report(command, "expected=\(String(format: "%.2f", output.duration)) exported=\(String(format: "%.2f", exported)) events=\(capture.events.count) file=\(url.path)")
        } catch {
            report(command, "error \(error)")
        }
    }
}
