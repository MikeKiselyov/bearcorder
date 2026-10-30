import AVFoundation
import BugbearCore
import AppKit
import CoreMedia
import QuartzCore
import ScreenCaptureKit

extension ScreenBuffer {
    /// A frame held back for later must not open a new segment after the capture stopped.
    /// Queued ahead of the segment's finish, so it runs first.
    func dropHeldFrame() {
        queue.async {
            self.heldSample = nil
            self.pacer.reset()
        }
    }

    /// While recording, changes only in the menu bar or under the recording bar (`windows`, global
    /// AppKit frames) are encoded a few times a second instead of every frame.
    /// `ownWindows`: our windows themselves; the pointer over them is not work on the recorded screen.
    func setQuietZones(busyWindows windows: [CGRect], ownWindows: [CGRect], enabled: Bool) {
        queue.async {
            self.busyWindows = windows
            self.ownWindows = ownWindows
            self.quietZonesEnabled = enabled
            self.updatePacerZones()
        }
    }

    /// Queue only.
    func updatePacerZones() {
        if quietZonesEnabled {
            pacer.zones = FramePacing.zones(displayFrame: displayFrame, menuBarHeight: menuBarHeight, busyWindows: busyWindows, outputSize: outputSize)
        } else {
            pacer.zones = []
            flushHeldFrame(force: true)
        }
    }

    /// Encodes the frame held back by the pacer once it is due, or at once with `force`. Queue only.
    func flushHeldFrame(force: Bool) {
        guard let sample = heldSample, writer != nil else { return }
        guard let time = pacer.takeHeld(now: CACurrentMediaTime(), lastKept: lastFrameTime, force: force) else {
            if pacer.heldTime == nil {
                heldSample = nil
            }
            return
        }
        heldSample = nil
        appendVideo(sample, at: time)
    }

    // MARK: Samples

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        if type == .audio {
            appendAudio(sampleBuffer, source: .system)
            return
        }
        guard type == .screen else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusValue),
              status == .complete else {
            return
        }
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if !pacer.zones.isEmpty {
            var dirty: [CGRect] = []
            for item in attachments.first?[.dirtyRects] as? [NSDictionary] ?? [] {
                if let rect = CGRect(dictionaryRepresentation: item) {
                    dirty.append(rect)
                }
            }
            let mouse = NSEvent.mouseLocation
            var pointer = FramePacing.pixelPoint(mouse, displayFrame: displayFrame, outputSize: outputSize)
            for window in ownWindows where window.contains(mouse) {
                pointer = nil
            }
            if pacer.receive(dirty: dirty, at: time, lastKept: lastFrameTime, pointer: pointer) == .hold {
                // Kept for later: if the screen goes still now, this is its last picture.
                heldSample = sampleBuffer
                queue.asyncAfter(deadline: .now() + FramePacing.quietInterval) { [weak self] in
                    self?.flushHeldFrame(force: false)
                }
                return
            }
            heldSample = nil
        }
        appendVideo(sampleBuffer, at: time)
    }

    func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + BufferTiming.heartbeatInterval, repeating: BufferTiming.heartbeatInterval)
        timer.setEventHandler { [weak self] in
            self?.repeatLastFrameIfIdle()
        }
        timer.resume()
        heartbeat = timer
    }

    func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    /// Queue only.
    private func repeatLastFrameIfIdle() {
        flushHeldFrame(force: false)
        let now = CACurrentMediaTime()
        guard let last = lastSampleBuffer, BufferTiming.shouldRepeat(now: now, lastFrame: lastFrameTime) else { return }
        if let copy = ScreenBuffer.retimed(last, to: now) {
            appendVideo(copy, at: now)
        }
    }

    /// Before a clip is cut: repeats the last frame at `now` (the moment of saving), so a clip saved
    /// after a still second reaches that moment. A frame held back by the pacer goes in first, it is
    /// the newest picture. Runs on the queue in short steps; between them it waits for a busy writer,
    /// which would drop the frame.
    func catchUp(now: Double) async {
        await waitForWriter()
        queue.sync {
            flushHeldFrame(force: true)
            guard let last = lastSampleBuffer, writer == nil else { return }
            // The last save closed the segment and the screen has been still since. While the buffer
            // runs, a new segment starts where the old one ended, so this clip is playable and reaches
            // its save too. A stopped buffer gets no made-up frames.
            guard heartbeat != nil else { return }
            let reopen = lastFrameTime + 1.0 / Double(configuration.framesPerSecond)
            guard BufferTiming.catchUpTime(now: now, lastFrame: reopen) != nil else { return }
            if let copy = ScreenBuffer.retimed(last, to: reopen) {
                appendVideo(copy, at: reopen, allowRotation: false)
            }
        }
        await waitForWriter()
        queue.sync {
            guard let last = lastSampleBuffer, writer != nil else { return }
            guard let time = BufferTiming.catchUpTime(now: now, lastFrame: lastFrameTime) else { return }
            if let copy = ScreenBuffer.retimed(last, to: time) {
                appendVideo(copy, at: time, allowRotation: false)
            }
        }
    }

    /// Waits up to half a second while the open segment's writer takes no more frames.
    private func waitForWriter() async {
        for _ in 0..<50 {
            let ready = queue.sync { videoInput?.isReadyForMoreMediaData ?? true }
            if ready { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Microphone samples from `MicrophoneSource` (host-time stamped). Any thread.
    func receiveMicrophone(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            self.appendAudio(sampleBuffer, source: .microphone)
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, source: AudioSource) {
        guard let input = audioInputs[source], writer != nil, input.isReadyForMoreMediaData else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if let index = currentSegmentIndex, time < segments[index].start { return }
        input.append(sampleBuffer)
    }
}
