import AppKit
import ScreenCaptureKit
import Observation
import AppCore
import QuartzCore

extension AppState {
    // MARK: Buffer

    /// The settings one display's buffer runs with: native resolution and the recording frame rate
    /// for a display a recorded area touches, the buffer's own for the rest.
    func bufferConfiguration(for display: CGDirectDisplayID) -> BufferConfiguration {
        var configuration = BufferConfiguration(
            retentionSeconds: settings.bufferSeconds,
            framesPerSecond: settings.framesPerSecond,
            maxHeight: settings.maxHeight,
            showsCursor: settings.showsCursor,
            systemAudio: settings.recordSystemAudio,
            microphone: settings.recordMicrophone
        )
        if nativeDisplaysForArea.contains(display) {
            configuration.maxHeight = 0
            configuration.framesPerSecond = max(settings.recordingFramesPerSecond, settings.framesPerSecond)
        }
        return configuration
    }

    /// The displays an area (global AppKit points) touches.
    func displaysTouched(by area: CGRect) -> Set<CGDirectDisplayID> {
        let screens = NSScreen.screens
        var frames: [CGRect] = []
        for screen in screens {
            frames.append(screen.frame)
        }
        var touched: Set<CGDirectDisplayID> = []
        for index in AreaDisplays.touched(area: area, frames: frames) {
            touched.insert(AppState.displayID(of: screens[index]))
        }
        return touched
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value ?? CGMainDisplayID()
    }

    /// Main display first, then the others when "all displays" is on.
    func displaysToCapture() -> [CGDirectDisplayID] {
        var ids: [CGDirectDisplayID] = [CGMainDisplayID()]
        if settings.captureAllDisplays || allDisplaysForArea {
            for screen in NSScreen.screens {
                let id = AppState.displayID(of: screen)
                if !ids.contains(id) {
                    ids.append(id)
                }
            }
        }
        if let extra = extraDisplayForRecording, !ids.contains(extra) {
            ids.append(extra)
        }
        return ids
    }

    private var allowedWindowNumbers: [Int] {
        var numbers: [Int] = []
        if let number = overlay.windowNumber { numbers.append(number) }
        if let number = camera.windowNumber { numbers.append(number) }
        return numbers
    }

    func updateAllowedWindows() {
        Task {
            await refreshBufferFilters()
        }
    }

    private func buffersExcludeOwnApp() -> Bool {
        if buffers.isEmpty { return true }
        for buffer in buffers where !buffer.excludesOwnApp {
            return false
        }
        return true
    }

    /// Re-applies "leave our windows out, except the overlay and camera" to every running buffer.
    func refreshBufferFilters() async {
        let numbers = allowedWindowNumbers
        for buffer in buffers {
            await buffer.allowOwnWindows(numbers)
        }
    }

    /// Starts (or restarts) the buffer. Starts run one after another: a start from the menu or a
    /// recording that comes while the buffer is coming back by itself waits for that one first,
    /// so no display is ever captured twice.
    func startBuffer() async {
        let previous = bufferStart
        let start = Task {
            await previous?.value
            await startBufferNow()
        }
        bufferStart = start
        await start.value
    }

    private func startBufferNow() async {
        if !ScreenBuffer.hasScreenRecordingAccess {
            bufferState = .needsPermission
            return
        }
        bufferState = .starting
        for buffer in buffers {
            await buffer.stop()
        }
        buffers = []
        do {
            if failingBufferStartsForTests > 0 {
                failingBufferStartsForTests -= 1
                throw BufferError.noDisplay
            }
            for (index, displayID) in displaysToCapture().enumerated() {
                let buffer = ScreenBuffer(displayID: displayID)
                var displayConfiguration = bufferConfiguration(for: displayID)
                // Audio lives on the primary buffer only.
                if index > 0 {
                    displayConfiguration.systemAudio = false
                    displayConfiguration.microphone = false
                }
                buffer.onStop = { [weak self] error in
                    self?.bufferStopped(error)
                }
                try await buffer.start(displayConfiguration, allowedWindowNumbers: allowedWindowNumbers)
                buffers.append(buffer)
            }
            micSink = buffers.first
            if settings.recordMicrophone {
                let started = await microphone.start()
                if !started {
                    statusMessage = L("app.buffer.microphoneDenied")
                }
            } else {
                microphone.stop()
            }
            inputRecorder.start(clicks: settings.recordClicks, keys: settings.recordKeys && InputEventRecorder.hasAccessibilityAccess, typedText: settings.recordTypedText, pages: settings.readBrowserURL, retentionSeconds: settings.bufferSeconds)
            bufferState = .running
            if bufferRecovery.isWaiting {
                Log.info("buffer is back after \(bufferRecovery.attempts) tries")
            }
            endBufferRecovery()
            updateCrashWatcher()
            // New buffers start without quiet zones; a restart during a recording needs them again.
            updateQuietZones()
            // Right after launch the app is not listed for exclusion yet; check again until it is.
            Task {
                for _ in 0..<30 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await refreshBufferFilters()
                    if buffersExcludeOwnApp() { break }
                }
            }
        } catch {
            Log.error("startBuffer failed: \(error.localizedDescription)")
            // The displays started before the one that failed would keep capturing unseen.
            for buffer in buffers {
                await buffer.stop()
            }
            buffers = []
            micSink = nil
            bufferState = .failed(error.localizedDescription)
            var noDisplay = false
            if case BufferError.noDisplay = error {
                noDisplay = true
                bufferRecovery.bufferLost()
            }
            if bufferRecovery.isWaiting {
                if bufferRecovery.keepsTrying(afterNoDisplay: noDisplay) {
                    scheduleBufferRecovery()
                } else {
                    Log.info("buffer: not starting again by itself after \(bufferRecovery.attempts) tries")
                    endBufferRecovery()
                }
            }
        }
        refreshStatus()
    }

    /// Adds the displays a recording needs that the running buffer does not capture yet, and leaves
    /// the running ones as they are (with what they hold). False when the buffer is not running or a
    /// display could not start; the caller then restarts the whole buffer.
    func addMissingBuffers() async -> Bool {
        let previous = bufferStart
        let adding = Task { () -> Bool in
            await previous?.value
            return await addMissingBuffersNow()
        }
        bufferStart = Task {
            _ = await adding.value
        }
        return await adding.value
    }

    private func addMissingBuffersNow() async -> Bool {
        if bufferState != .running || buffers.isEmpty { return false }
        for displayID in displaysToCapture() where !buffers.contains(where: { buffer in buffer.displayID == displayID }) {
            let buffer = ScreenBuffer(displayID: displayID)
            var configuration = bufferConfiguration(for: displayID)
            // Audio lives on the primary buffer, which already runs.
            configuration.systemAudio = false
            configuration.microphone = false
            buffer.onStop = { [weak self] error in
                self?.bufferStopped(error)
            }
            do {
                try await buffer.start(configuration, allowedWindowNumbers: allowedWindowNumbers)
            } catch {
                Log.error("adding display \(displayID) to the buffer failed: \(error.localizedDescription)")
                await buffer.stop()
                return false
            }
            buffers.append(buffer)
            Log.info("recording: display \(displayID) added to the buffer")
        }
        updateQuietZones()
        return true
    }

    /// Restarts one display's buffer at native resolution when its stream did not take the change.
    /// Runs on the start chain, so a recording that ends meanwhile restarts the buffer after it, not
    /// beside it.
    func restartBufferForArea(_ displayID: CGDirectDisplayID) async {
        let previous = bufferStart
        let restart = Task {
            await previous?.value
            await restartBufferForAreaNow(displayID)
        }
        bufferStart = restart
        await restart.value
    }

    private func restartBufferForAreaNow(_ displayID: CGDirectDisplayID) async {
        // The recording ended meanwhile: its own restart puts the buffer back to the settings.
        if (recording == nil && !isStartingRecording) || bufferState != .running { return }
        guard let buffer = buffers.first(where: { buffer in buffer.displayID == displayID }) else { return }
        var configuration = bufferConfiguration(for: displayID)
        if buffer !== primaryBuffer {
            configuration.systemAudio = false
            configuration.microphone = false
        }
        Log.info("buffer[\(displayID)] restarting at native resolution")
        do {
            try await buffer.start(configuration, allowedWindowNumbers: allowedWindowNumbers)
        } catch {
            Log.error("buffer[\(displayID)] restart at native resolution failed: \(error.localizedDescription)")
            bufferStopped(error)
        }
        updateQuietZones()
    }

    func bufferStopped(_ error: Error?) {
        if bufferState != .running { return }
        if AppState.isStoppedByUser(error) {
            Task { await bufferStoppedByUser() }
            return
        }
        bufferState = .failed(error?.localizedDescription ?? L("app.buffer.captureStopped"))
        // Display changes stop the stream (a closed lid, an unplugged monitor); it comes back by itself.
        bufferRecovery.bufferLost()
        scheduleBufferRecovery()
    }

    /// The next try to bring a stopped buffer back, after a pause that grows with every try.
    private func scheduleBufferRecovery() {
        bufferRecoveryTask?.cancel()
        guard let delay = bufferRecovery.nextDelay() else { return }
        bufferRecoveryTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            await recoverBuffer(reason: "try \(bufferRecovery.attempts) after \(Int(delay)) s")
        }
    }

    /// A display appeared or the Mac woke up: a buffer waiting to come back tries at once.
    func recoverBufferNow(reason: String) {
        if !bufferRecovery.isWaiting { return }
        bufferRecoveryTask?.cancel()
        bufferRecoveryTask = Task {
            await recoverBuffer(reason: reason)
        }
    }

    private func recoverBuffer(reason: String) async {
        if !bufferRecovery.isWaiting { return }
        // Another start is on its way; its failure schedules the next try.
        if bufferState == .starting { return }
        // A recording brings the buffer back when it ends, after its clip is saved; a save reads
        // the buffers that still run.
        if recording != nil || isStartingRecording || isSaving {
            scheduleBufferRecovery()
            return
        }
        Log.info("buffer: starting again (\(reason))")
        await startBuffer()
    }

    private func endBufferRecovery() {
        bufferRecovery.ended()
        bufferRecoveryTask?.cancel()
        bufferRecoveryTask = nil
    }

    /// "Stop" in the macOS screen recording menu (the purple icon in the menu bar) ends the stream.
    static func isStoppedByUser(_ error: Error?) -> Bool {
        guard let nsError = error as NSError? else { return false }
        return nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userStopped.rawValue
    }

    /// The person stopped the capture from the macOS menu. A recording in progress is saved as usual;
    /// otherwise what the buffer holds becomes a clip, the buffer stays off, and a message offers the
    /// editor.
    private func bufferStoppedByUser() async {
        Log.info("buffer stopped from the macOS screen recording menu")
        if recording != nil {
            await stopRecording()
            await pauseBuffer()
            return
        }
        bufferState = .paused
        var saved: Capture?
        if !isSaving, let available = primaryBuffer?.availability(), available.end - available.start >= 1 {
            isSaving = true
            do {
                saved = try await saveClip(from: buffers, ranges: [(start: available.start, end: available.end)], app: lastExternalApp)
            } catch {
                Log.error("saving the buffer after a stop failed: \(error.localizedDescription)")
            }
            isSaving = false
        }
        await pauseBuffer()
        refreshStatus()
        guard let capture = saved else {
            Toast.shared.show(L("app.buffer.stoppedToast"), symbol: "pause.circle", seconds: 3)
            return
        }
        if Automation.isEnabled { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("app.buffer.stoppedAlert.title")
        alert.informativeText = L("app.buffer.stoppedAlert.message", AppInfo.name, TimeFormat.clock(capture.duration))
        alert.addButton(withTitle: L("app.buffer.stoppedAlert.openInEditor"))
        alert.addButton(withTitle: L("app.buffer.stoppedAlert.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            WindowManager.shared.openEditor(for: capture)
        }
    }

    func pauseBuffer() async {
        // A start on its way would otherwise turn the buffer on again after the pause.
        await bufferStart?.value
        if recording != nil {
            await stopRecording()
        }
        for buffer in buffers {
            await buffer.stop()
        }
        buffers = []
        micSink = nil
        microphone.stop()
        inputRecorder.stop()
        crashWatcher.stop()
        bufferState = .paused
        coveredSeconds = 0
        endBufferRecovery()
    }

    /// "Show what I type in steps" and "Read the browser tab URL" apply at once, also to the
    /// clicks and keys recorded so far.
    func applyStepPrivacy() {
        inputRecorder.setPrivacy(typedText: settings.recordTypedText, pages: settings.readBrowserURL)
    }
}
