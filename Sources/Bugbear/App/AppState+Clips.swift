import AppKit
import ScreenCaptureKit
import Observation
import BugbearCore
import QuartzCore

extension AppState {
    // MARK: Saving clips

    /// ⌥⇧M: remembers "the bug is here". The next save reaches back to include it.
    func markMoment() {
        if bufferState != .running {
            showError(L("app.buffer.notRecording"))
            return
        }
        inputRecorder.mark()
        Log.info("marker added")
        Toast.shared.show(L("app.clip.momentMarked"), symbol: "flag.fill")
    }

    /// Clip start: `seconds` back from `end`, or earlier to include an unused marker with 5 s before it.
    private func clipStart(end: Double, seconds: Double) -> Double {
        let start = end - seconds
        guard let marker = inputRecorder.takeOldestNewMarker() else { return start }
        let wanted = marker - 5
        if wanted >= start {
            return start
        }
        var earliest = start
        if let available = primaryBuffer?.availability() {
            earliest = available.start
        }
        Log.info("save reaches back to a marker \(String(format: "%.1f", end - marker))s ago")
        return max(wanted, earliest)
    }

    func saveFromBuffer(seconds: Double) async {
        if bufferState != .running {
            showError(L("app.buffer.notRecording"))
            return
        }
        if isSaving { return }
        isSaving = true
        closeMenuPanel()
        defer { isSaving = false }
        let end = CACurrentMediaTime()
        let app = lastExternalApp
        Log.info("save from buffer: last \(seconds)s, displays=\(buffers.count)")
        let start = clipStart(end: end, seconds: seconds)
        do {
            let capture = try await saveClip(from: buffers, ranges: [(start: start, end: end)], app: app)
            WindowManager.shared.openEditor(for: capture)
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Saves a clip from the buffers and adds it to Recent. With several displays each one is saved on
    /// its own, which needs no re-encoding; the editor switches between them or puts them side by side.
    /// It opens on the display under the pointer, where the person was looking.
    func saveClip(from source: [ScreenBuffer], ranges: [(start: Double, end: Double)], app: NSRunningApplication?, framesPerSecond: Int? = nil) async throws -> Capture {
        let rate = framesPerSecond ?? settings.framesPerSecond
        guard let main = source.first else { throw BufferError.noDisplay }
        let environment = await EnvironmentCollector.snapshot(for: app, readURL: settings.readBrowserURL)
        if source.count == 1 {
            let clip = try await ClipComposer.export(buffers: source, ranges: ranges, area: nil, framesPerSecond: rate)
            Log.info("clip exported: \(clip.duration)s → \(clip.url.lastPathComponent)")
            let capture = try store.add(kind: .video, mediaFile: clip.url, environment: environment, events: inputRecorder.events(for: clip), duration: clip.duration)
            attachSystemLog(to: capture, clip: clip, app: app)
            return capture
        }

        let ordered = source.sorted { first, second in first.displayFrame.minX < second.displayFrame.minX }
        var clips: [ClipExport] = []
        var variants: [ScreenVariant] = []
        for buffer in ordered {
            let clip = try await ClipComposer.export(buffers: [buffer], ranges: ranges, area: nil, framesPerSecond: rate, audioFrom: main)
            clips.append(clip)
            variants.append(ScreenVariant(id: "display-\(buffer.displayID)", name: AppState.screenName(buffer.displayID), file: "screen-\(buffer.displayID).mp4", events: inputRecorder.events(for: clip), isMain: buffer === main))
        }
        // Clicks for the side-by-side picture, which is built only if someone picks it.
        let sideBySide = ClipExport(url: clips[0].url, pieces: clips[0].pieces, duration: clips[0].duration, layout: ClipComposer.sideBySideLayout(source))
        variants.append(ScreenVariant(id: ScreenVariant.allID, name: L("app.display.sideBySide"), file: "screen-all.mp4", events: inputRecorder.events(for: sideBySide), isMain: false))

        var chosen = 0
        let mouse = NSEvent.mouseLocation
        for (index, buffer) in ordered.enumerated() where buffer.displayFrame.contains(mouse) {
            chosen = index
        }
        Log.info("clip exported per display: \(clips.count) clips, opening \(variants[chosen].name)")
        var capture = try store.add(kind: .video, mediaFile: clips[chosen].url, environment: environment, events: variants[chosen].events, duration: clips[chosen].duration)
        for (index, clip) in clips.enumerated() {
            let target = capture.folder.appendingPathComponent(variants[index].file)
            if index == chosen {
                // The same file under a second name: original.mp4 is always the selected picture.
                try FileManager.default.linkItem(at: capture.mediaURL, to: target)
            } else {
                try FileManager.default.moveItem(at: clip.url, to: target)
            }
        }
        capture.screens = variants
        capture.selectedScreen = variants[chosen].id
        try store.replace(capture)
        attachSystemLog(to: capture, clip: clips[chosen], app: app)
        return capture
    }

    /// The name macOS shows for a display, e.g. "Built-in Retina Display" or "LG ULTRAFINE".
    static func screenName(_ wanted: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens where AppState.displayID(of: screen) == wanted {
            // "Built-in Retina Display" is long for a switch; the built-in one is simply "Built-in".
            if screen.localizedName.hasPrefix("Built-in") {
                return L("app.display.builtIn")
            }
            return screen.localizedName
        }
        return L("app.display.numbered", Int(wanted))
    }

    // MARK: Storage


    /// Settings → Storage limits, applied shortly after launch and then once a day.
    func startStorageCleanUp() {
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await scheduledCleanUp()
        }
        cleanUpTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in
                await AppState.shared.scheduledCleanUp()
            }
        }
    }

    private func scheduledCleanUp() async {
        if scheduledCleanUpPaused {
            Log.info("timed clean up skipped: paused by a test")
            return
        }
        await cleanUpStorage()
    }

    @discardableResult
    func cleanUpStorage() async -> Int {
        return await store.cleanUp(maxAgeDays: settings.keepCapturesDays, maxGB: settings.maxCapturesGB, crashClipDays: settings.keepCrashClipsDays)
    }

    // MARK: Crashes

    /// Runs the crash watcher while the buffer runs and the setting is on.
    func updateCrashWatcher() {
        crashWatcher.onCrash = { report, file in
            Task { await AppState.shared.saveCrashClip(report, reportFile: file) }
        }
        if bufferState == .running && settings.saveOnCrash {
            crashWatcher.start()
        } else {
            crashWatcher.stop()
        }
    }

    /// The minute before a crash (plus 2 s after), saved to Recent without opening the editor.
    func saveCrashClip(_ report: CrashReport, reportFile: URL) async {
        if bufferState != .running { return }
        var waited = 0
        while isSaving && waited < 20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 1
        }
        if isSaving { return }
        isSaving = true
        defer { isSaving = false }
        let now = CACurrentMediaTime()
        let secondsAgo = max(0, Date().timeIntervalSince(report.date))
        let crashTime = now - secondsAgo
        let end = min(now, crashTime + 2)
        var start = crashTime - 60
        if let available = primaryBuffer?.availability() {
            start = max(start, available.start)
        }
        if end - start < 1 {
            Log.info("crash clip skipped: \(report.appName) crashed before the buffer started")
            return
        }
        let app = lastExternalApp
        Log.info("save crash clip: \(report.appName), \(String(format: "%.1f", secondsAgo))s ago")
        do {
            let capture = try await saveClip(from: buffers, ranges: [(start: start, end: end)], app: app)
            try? FileManager.default.copyItem(at: reportFile, to: capture.crashReportURL)
            Log.info("crash clip saved: \(capture.duration)s → \(capture.id)")
            Toast.shared.show(L("app.clip.crashSaved", report.appName), symbol: "exclamationmark.triangle.fill", seconds: 5)
        } catch {
            Log.error("crash clip failed: \(error.localizedDescription)")
        }
    }

    /// Saves the app's system log for the clip's time span in the background (takes a few seconds).
    private func attachSystemLog(to capture: Capture, clip: ClipExport, app: NSRunningApplication?) {
        guard settings.attachSystemLogs, let source = SystemLogCollector.source(for: app), let span = clip.wallClockSpan else { return }
        let file = capture.systemLogURL
        Task {
            let lines = await SystemLogCollector.collect(source, from: span.start, to: span.end, into: file)
            Log.info("system log for \(source.name): \(lines) lines")
            store.systemLogSaved(for: capture.id)
        }
    }

    func finishClip(_ clip: ClipExport, app: NSRunningApplication?) async {
        let environment = await EnvironmentCollector.snapshot(for: app, readURL: settings.readBrowserURL)
        let events = inputRecorder.events(for: clip)
        do {
            let capture = try store.add(kind: .video, mediaFile: clip.url, environment: environment, events: events, duration: clip.duration)
            attachSystemLog(to: capture, clip: clip, app: app)
            WindowManager.shared.openEditor(for: capture)
        } catch {
            showError(error.localizedDescription)
        }
    }
}
