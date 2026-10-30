import AppKit
import ScreenCaptureKit
import Observation
import BugbearCore
import QuartzCore

extension AppState {
    // MARK: Recording from now

    func toggleRecording() async {
        if recording != nil {
            await stopRecording()
        } else {
            await startRecording(target: recordingTarget)
        }
    }

    /// `presetRegion` skips the area picker (automation).
    func startRecording(target: RecordingTarget, presetRegion: RegionSelector.Selection? = nil) async {
        if recording != nil || isStartingRecording { return }
        isStartingRecording = true
        defer { isStartingRecording = false }
        closeMenuPanel()
        recordingRegion = presetRegion
        if target == .area && presetRegion == nil {
            let screen = NSScreen.screens.first { screen in screen.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            guard let chosen = screen else { return }
            let bugbearWasInFront = NSApp.isActive
            let selection = await regionSelector.pick(on: chosen, initial: nil, acrossScreens: true)
            guard let picked = selection else { return }
            // The picker took the focus to read Return; give it back, so the keys go to the app being
            // recorded right away. Started from one of Bugbear's own windows, the focus stays there.
            if !bugbearWasInFront {
                handFocusBack()
            }
            recordingRegion = picked
        }
        var restart = bufferState != .running
        // Displays the running buffer does not capture yet are added; the running ones keep going.
        var addDisplays = false
        // Which display to keep: the one under the pointer when only one is wanted. An area can be
        // moved to any display or across them while recording, so every display is kept for it.
        recordingDisplay = nil
        if recordingRegion != nil {
            if NSScreen.screens.count > 1 && !settings.captureAllDisplays {
                allDisplaysForArea = true
                addDisplays = true
                Log.info("area recording: every display in the buffer")
            }
        } else if !settings.captureAllDisplays, let screen = NSScreen.screens.first(where: { screen in screen.frame.contains(NSEvent.mouseLocation) }) {
            recordingDisplay = AppState.displayID(of: screen)
        }
        if let display = recordingDisplay, !buffers.contains(where: { buffer in buffer.displayID == display }) {
            extraDisplayForRecording = display
            restart = true
            Log.info("recording: adding display \(display) to the buffer")
        }
        // Only the displays the area touches go to native resolution and the recording frame rate.
        if let region = recordingRegion {
            nativeDisplaysForArea = displaysTouched(by: region.global)
            Log.info("area recording: native resolution on \(nativeDisplaysForArea.sorted())")
        }
        if !restart && addDisplays {
            let added = await addMissingBuffers()
            if !added {
                restart = true
            }
        }
        if restart {
            await startBuffer()
        } else if !nativeDisplaysForArea.isEmpty {
            await upgradeBuffers(nativeDisplaysForArea)
        }
        if bufferState != .running {
            await restoreBufferResolution(force: true)
            showError(L("app.recording.screenUnavailable"))
            return
        }
        await refreshBufferFilters()
        // An area's displays got the recording frame rate with native resolution; the others keep
        // the buffer's.
        if settings.recordingFramesPerSecond > settings.framesPerSecond && recordingRegion == nil {
            for buffer in buffers {
                await buffer.setFrameRate(settings.recordingFramesPerSecond)
            }
            boostedFrameRate = true
        }
        let session = RecordingSession()
        for buffer in buffers {
            buffer.pin(from: session.startTime)
        }
        recording = session
        var overlayFrame = primaryBuffer?.displayFrame ?? NSScreen.main?.frame ?? .zero
        var recordedDisplays: Set<CGDirectDisplayID> = []
        for buffer in buffers {
            if recordingDisplay == nil || buffer.displayID == recordingDisplay {
                recordedDisplays.insert(buffer.displayID)
            }
            if buffer.displayID == recordingDisplay {
                overlayFrame = buffer.displayFrame
            }
        }
        if let region = recordingRegion {
            overlayFrame = region.screen.frame
        }
        overlay.show(on: overlayFrame)
        hud.show(app: self)
        hud.onMove = { [weak self] in
            self?.updateQuietZones()
        }
        recordingOutline.onAreaChange = { [weak self] global in
            self?.recordingAreaChanged(global)
        }
        recordingOutline.show(region: recordingRegion, recordedDisplays: recordedDisplays)
        updateQuietZones()
    }

    /// While recording, our recording bar and outline are on screen and macOS keeps redrawing the
    /// menu bar and the bar itself, so the capture would encode 20-30 frames a second of a still
    /// screen. Changes only there are then taken a few times a second (`FramePacing`). Without a
    /// recording every frame is taken, as before.
    func updateQuietZones() {
        var busy: [CGRect] = []
        if let frame = hud.frame {
            busy.append(frame)
        }
        let enabled = recording != nil
        for buffer in buffers {
            // The pointer on or right next to the bar is about to press its buttons, not working on
            // the recorded screen.
            buffer.setQuietZones(busyWindows: busy, ownWindows: busy, enabled: enabled)
        }
    }

    /// The area was resized or moved on screen while recording, maybe onto another display; the
    /// video gets the area as it is at the end.
    private func recordingAreaChanged(_ global: CGRect) {
        guard recordingRegion != nil, let region = RegionSelector.Selection(global: global) else { return }
        recordingRegion = region
        areaMoved(to: global)
    }

    /// A display the moved area now touches goes to native resolution from this moment (its earlier
    /// frames stay at the buffer's resolution, the clip scales them up). Displays the area left keep
    /// native resolution until the recording ends.
    func areaMoved(to area: CGRect) {
        let newlyTouched = AreaDisplays.toUpgrade(touched: displaysTouched(by: area), native: nativeDisplaysForArea, recording: recording != nil)
        if newlyTouched.isEmpty { return }
        nativeDisplaysForArea.formUnion(newlyTouched)
        Log.info("area recording: area moved onto \(newlyTouched.sorted()), native resolution there")
        Task {
            await upgradeBuffers(newlyTouched)
        }
    }

    /// Native resolution and the recording frame rate on the running buffers of these displays. A stream
    /// that does not take the change is restarted, on the buffer's start chain.
    private func upgradeBuffers(_ displays: Set<CGDirectDisplayID>) async {
        let rate = max(settings.recordingFramesPerSecond, settings.framesPerSecond)
        for buffer in buffers where displays.contains(buffer.displayID) {
            let applied = await buffer.upgradeToNative(framesPerSecond: rate)
            if !applied {
                await restartBufferForArea(buffer.displayID)
            }
        }
    }

    func stopRecording() async {
        guard let session = recording else { return }
        if session.isPaused {
            session.resume()
        }
        let end = CACurrentMediaTime()
        let ranges = session.keptRanges(until: end)
        let region = recordingRegion
        recording = nil
        recordingRegion = nil
        hud.hide()
        overlay.hide()
        recordingOutline.hide()
        updateQuietZones()
        let app = lastExternalApp
        isSaving = true
        defer {
            isSaving = false
            for buffer in buffers {
                buffer.pin(from: nil)
            }
        }
        var exportBuffers = buffers
        if let display = recordingDisplay {
            exportBuffers = buffers.filter { buffer in buffer.displayID == display }
        }
        if let area = region?.global {
            exportBuffers = buffers.filter { buffer in buffer.displayFrame.intersects(area) }
        }
        recordingDisplay = nil
        do {
            if region == nil {
                let capture = try await saveClip(from: exportBuffers, ranges: ranges, app: app, framesPerSecond: settings.recordingFramesPerSecond)
                WindowManager.shared.openEditor(for: capture)
            } else {
                // The sound is on the main display's buffer, which the area may not touch.
                let clip = try await ClipComposer.export(buffers: exportBuffers, ranges: ranges, area: region?.global, framesPerSecond: settings.recordingFramesPerSecond, audioFrom: primaryBuffer)
                await finishClip(clip, app: app)
            }
        } catch {
            showError(error.localizedDescription)
        }
        for buffer in buffers {
            buffer.pin(from: nil)
        }
        await restoreBufferResolution()
    }

    func discardRecording() {
        recording = nil
        recordingRegion = nil
        recordingDisplay = nil
        hud.hide()
        overlay.hide()
        recordingOutline.hide()
        updateQuietZones()
        for buffer in buffers {
            buffer.pin(from: nil)
        }
        Task { await restoreBufferResolution() }
    }

    /// Back to the displays, resolution and frame rate from Settings after a recording changed them,
    /// and back on if the buffer died during the recording (a display was unplugged). `force` is for
    /// a recording that failed to start.
    private func restoreBufferResolution(force: Bool = false) async {
        // A new recording started meanwhile: the buffer's settings are its own now.
        if !force && (recording != nil || isStartingRecording) { return }
        var bufferFailed = false
        if case .failed = bufferState {
            bufferFailed = true
        }
        // Displays an area recording took to native resolution go back by a restart; the frame rate alone
        // changes on the running stream.
        let changedResolution = !nativeDisplaysForArea.isEmpty && settings.maxHeight > 0
        let needsRestart = changedResolution || allDisplaysForArea || extraDisplayForRecording != nil || bufferFailed || screensChangedWhileRecording
        let wasBoosted = boostedFrameRate || !nativeDisplaysForArea.isEmpty
        nativeDisplaysForArea = []
        allDisplaysForArea = false
        extraDisplayForRecording = nil
        boostedFrameRate = false
        screensChangedWhileRecording = false
        if needsRestart {
            if bufferState == .running || bufferFailed {
                await startBuffer()
                Log.info("recording done: buffer back to \(settings.qualityLabel)")
            }
            return
        }
        if wasBoosted {
            for buffer in buffers {
                await buffer.setFrameRate(settings.framesPerSecond)
            }
        }
    }

    // MARK: Drawing on screen and camera

    func toggleDrawing() {
        // Drawing goes on the display the pointer is on. During a recording the window was placed
        // once on the recorded display, and with two displays a drag on the other one reached the
        // apps under it: nothing was drawn.
        let screen = NSScreen.screens.first { screen in screen.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.frame ?? .zero
        if !overlay.isVisible {
            overlay.show(on: frame)
            hud.show(app: self)
        } else if !overlay.isDrawing && overlay.frame != frame {
            overlay.show(on: frame)
        }
        overlay.isDrawing.toggle()
        DispatchQueue.main.async {
            self.hud.resize()
            self.updateQuietZones()
        }
    }

    func hideOverlay() {
        overlay.hide()
        if recording == nil {
            hud.hide()
        }
        updateQuietZones()
    }

    func setCamera(_ on: Bool) async {
        if on {
            let screen = NSScreen.screens.first { screen in screen.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let shown = await camera.show(on: screen)
            cameraOn = shown
            if !shown {
                showError(L("app.recording.cameraUnavailable", AppInfo.name))
            }
        } else {
            camera.hide()
            cameraOn = false
        }
    }
}
