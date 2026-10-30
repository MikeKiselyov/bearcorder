// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AppKit
import BugbearCore

/// Local automation for end-to-end tests (scripts/test/e2e.sh). Off by default; enable with
///   defaults write <bundle id> automationEnabled -bool true
/// Commands arrive as a distributed notification "Bugbear.automation" with userInfo["command"];
/// results are written to the log as "AUTOMATION <command> → <result>".
/// A command may end with " #id=<token>" (scripts/dev/bugbear-run.sh): the token is cut off before the
/// command runs, and the result is also written to automation/results/<token> in the support folder.
@MainActor
enum Automation {
    static var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "automationEnabled")
    }

    /// The token of the command being run, so `report` knows which result file to write.
    @TaskLocal private static var resultToken: String?

    /// Where results of commands with a token go. Emptied when the app starts.
    static var resultsFolder: URL {
        return AppPaths.support
            .appendingPathComponent("automation", isDirectory: true)
            .appendingPathComponent("results", isDirectory: true)
    }

    /// Splits " #id=<token>" off the end of a command. Only the end counts, so a "#" inside the
    /// command (a color like #FF8800) stays where it is.
    static func splitToken(_ raw: String) -> (command: String, token: String?) {
        guard let range = raw.range(of: " #id=[A-Za-z0-9-]+$", options: .regularExpression) else {
            return (raw, nil)
        }
        let token = String(raw[range].dropFirst(" #id=".count))
        return (String(raw[..<range.lowerBound]), token)
    }

    /// Writes the result next to the log line: to a temporary name first, then renamed, so a reader
    /// never sees half of it.
    private static func writeResult(_ result: String, token: String) {
        let folder = resultsFolder
        AppPaths.ensureFolder(folder)
        let temporary = folder.appendingPathComponent(token + ".tmp")
        let final = folder.appendingPathComponent(token)
        do {
            try result.write(to: temporary, atomically: false, encoding: .utf8)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: temporary, to: final)
        } catch {
            Log.error("automation: could not write result \(token): \(error)")
        }
    }

    static func install() {
        guard isEnabled else { return }
        Log.info("automation enabled")
        try? FileManager.default.removeItem(at: resultsFolder)
        AppPaths.ensureFolder(resultsFolder)
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("Bugbear.automation"), object: nil, queue: .main) { notification in
            let raw = notification.userInfo?["command"] as? String ?? (notification.object as? String ?? "")
            let (command, token) = splitToken(raw)
            MainActor.assumeIsolated {
                Task { await $resultToken.withValue(token) { await run(command) } }
            }
        }
    }

    private static func report(_ command: String, _ result: String) {
        Log.info("AUTOMATION \(command) → \(result)")
        if let token = resultToken {
            writeResult(result, token: token)
        }
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
        case "buffer-lose":
            // buffer-lose:<n> stops the buffer as a closed lid does; the next n starts find no display.
            app.failingBufferStartsForTests = Int(parts.count > 1 ? parts[1] : "0") ?? 0
            app.bufferStopped(BufferError.noDisplay)
            report(command, "\(app.bufferState) waiting=\(app.bufferRecovery.isWaiting)")
        case "screens-woke":
            app.recoverBufferNow(reason: "screens woke")
            report(command, "waiting=\(app.bufferRecovery.isWaiting)")
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
            // Marks drawn on the screen stay after Esc until closed; a test leaves none behind.
            if app.recording == nil && app.overlay.isVisible {
                app.hideOverlay()
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
#endif
