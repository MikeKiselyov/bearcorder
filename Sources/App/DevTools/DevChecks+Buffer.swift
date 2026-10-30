// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AppKit
import AppCore
import CoreMedia
import QuartzCore

@MainActor
extension DevChecks {
    /// A clip saved after the screen was still reaches the moment of saving: before the clip is cut,
    /// the buffer repeats its last frame at that moment (catch-up). The buffer is fed made-up frames
    /// (no Screen Recording needed): 7.5 s of frames until 3 s ago, then nothing, then a save of the
    /// last 5 s. The save is always more than one segment length (10 s) after the first frame, so the
    /// catch-up frame must stay in the open segment. A second save half a second later, the screen
    /// still and the buffer running, must reach its own moment too. Times are taken from the clock as
    /// the check goes, so a slow machine only makes the still part longer.
    static func checkClipReachesSaveAfterStill(folder: URL) async {
        let previousSupport = AppPaths.supportOverride
        AppPaths.supportOverride = folder.appendingPathComponent("clip-after-still", isDirectory: true)
        defer {
            AppPaths.supportOverride = previousSupport
        }
        let framesPerSecond = 10
        let size = CGSize(width: 160, height: 96)
        let buffer = ScreenBuffer(displayID: 990_001)
        buffer.queue.sync {
            buffer.configuration.framesPerSecond = framesPerSecond
            buffer.outputSize = size
        }
        guard let pixels = solidPixelBuffer(size: size) else {
            check(false, "clip after a still screen: made-up frame")
            return
        }

        let start = CACurrentMediaTime()
        let stillFrom = start - 3
        var fed = 0
        let firstFrame = start - 10.5
        var time = firstFrame
        while time <= stillFrom {
            await waitUntilBufferTakesFrames(buffer)
            if let sample = sampleBuffer(pixels, at: time) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
                fed += 1
            }
            time += 1.0 / Double(framesPerSecond)
        }
        let written = buffer.queue.sync { buffer.receivedFrames }
        check(written == fed && fed > 50, "clip after a still screen: the buffer took every frame", "fed \(fed), written \(written)")

        // A save right after a frame needs no extra frame, and one in the past adds none.
        let lastFrame = buffer.queue.sync { buffer.lastFrameTime }
        await buffer.catchUp(now: lastFrame + 0.03)
        await buffer.catchUp(now: lastFrame - 1)
        let afterCloseSave = buffer.queue.sync { buffer.receivedFrames }
        check(afterCloseSave == written, "catch-up adds no frame when the last one is close", "frames \(written) -> \(afterCloseSave)")

        // A burst of frames a fraction of a millisecond apart keeps the writer busy at the save, as on
        // a busy screen: the catch-up frame must wait for it instead of being dropped.
        var writerBusy = false
        var burstTime = buffer.queue.sync { buffer.lastFrameTime }
        for _ in 0..<2000 {
            burstTime += 0.0002
            let busy = buffer.queue.sync { () -> Bool in
                if let sample = sampleBuffer(pixels, at: burstTime) {
                    buffer.appendVideo(sample, at: burstTime)
                }
                return !(buffer.videoInput?.isReadyForMoreMediaData ?? true)
            }
            if busy {
                writerBusy = true
                break
            }
        }
        check(writerBusy, "clip after a still screen: the writer is busy at the save")

        let saveMoment = CACurrentMediaTime()
        check(saveMoment - firstFrame >= buffer.segmentLength, "clip after a still screen: the save is past one segment length", String(format: "%.2f s", saveMoment - firstFrame))
        do {
            let clip = try await ClipComposer.export(buffers: [buffer], ranges: [(start: saveMoment - 5, end: saveMoment)], area: nil, framesPerSecond: framesPerSecond)
            let caughtUp = buffer.queue.sync { buffer.lastFrameTime }
            check(abs(caughtUp - saveMoment) < 0.1, "clip after a still screen: the buffer's last frame is at the save", String(format: "last frame %.3f s from the save", caughtUp - saveMoment))
            check(abs(clip.duration - 5) < 0.1, "clip after a still screen: the clip is 5 s long", "got \(clip.duration)")
            let asset = AVURLAsset(url: clip.url)
            var pictureEnd = 0.0
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                pictureEnd = try await track.load(.timeRange).end.seconds
            }
            check(abs(pictureEnd - 5) < 0.1, "clip after a still screen: the picture lasts to the save", "video ends at \(pictureEnd)")
            try? FileManager.default.removeItem(at: clip.url)
        } catch {
            check(false, "clip after a still screen: export", "\(error)")
        }

        // The first save closed the segment. The buffer runs (heartbeat on, it fires only after 1 s).
        buffer.startHeartbeat()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let secondSave = CACurrentMediaTime()
        do {
            let clip = try await ClipComposer.export(buffers: [buffer], ranges: [(start: secondSave - 5, end: secondSave)], area: nil, framesPerSecond: framesPerSecond)
            check(abs(clip.duration - 5) < 0.1, "a second save right after the first: the clip is 5 s long", "got \(clip.duration)")
            let asset = AVURLAsset(url: clip.url)
            var pictureEnd = 0.0
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                pictureEnd = try await track.load(.timeRange).end.seconds
            }
            check(abs(pictureEnd - 5) < 0.1, "a second save right after the first: the picture lasts to the save", "video ends at \(pictureEnd)")
            try? FileManager.default.removeItem(at: clip.url)
        } catch {
            check(false, "a second save right after the first: export", "\(error)")
        }
        buffer.stopHeartbeat()
        await buffer.finishCurrentSegment()
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("clip-after-still", isDirectory: true))
    }

    /// On a still screen only the heartbeat sends frames, one a second. A segment that rotates on such
    /// a frame must end where the next one starts (the last picture stays on screen until the next
    /// frame), or the clip loses almost a second at every rotation and a 25 s save comes out shorter.
    static func checkStillScreenSegmentsAreContiguous(folder: URL) async {
        let previousSupport = AppPaths.supportOverride
        let support = folder.appendingPathComponent("still-segments", isDirectory: true)
        AppPaths.supportOverride = support
        defer {
            AppPaths.supportOverride = previousSupport
        }
        let framesPerSecond = 10
        let size = CGSize(width: 160, height: 96)
        let buffer = ScreenBuffer(displayID: 990_003)
        buffer.queue.sync {
            buffer.configuration.framesPerSecond = framesPerSecond
            buffer.outputSize = size
        }
        guard let pixels = solidPixelBuffer(size: size) else {
            check(false, "still screen segments: made-up frame")
            return
        }
        // 30 s of heartbeat frames, one a second, until a second ago: three segment rotations.
        let start = CACurrentMediaTime()
        var time = start - 30
        while time <= start - 1 {
            await waitUntilBufferTakesFrames(buffer)
            if let sample = sampleBuffer(pixels, at: time) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
            }
            time += 1
        }
        let saveMoment = CACurrentMediaTime()
        do {
            let clip = try await ClipComposer.export(buffers: [buffer], ranges: [(start: saveMoment - 25, end: saveMoment)], area: nil, framesPerSecond: framesPerSecond)
            let finished = buffer.queue.sync { () -> [ScreenBuffer.Segment] in
                var list: [ScreenBuffer.Segment] = []
                for segment in buffer.segments where segment.finished {
                    list.append(segment)
                }
                return list
            }
            check(finished.count >= 3, "still screen segments: the buffer rotated at least twice", "\(finished.count) segments")
            var gaps: [String] = []
            for position in 1..<max(finished.count, 1) {
                let gap = finished[position].start - finished[position - 1].end
                if abs(gap) > 0.01 {
                    gaps.append(String(format: "%.3f s", gap))
                }
            }
            check(gaps.isEmpty, "still screen segments: each segment ends where the next one starts", gaps.joined(separator: ", "))
            // The saved file, not the planned length: gaps between segments do not reach the file.
            let asset = AVURLAsset(url: clip.url)
            let fileLength = try await asset.load(.duration).seconds
            // Time with frames, without empty stretches (players and avmediainfo count only these).
            var pictureLength = 0.0
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                for segment in try await track.load(.segments) where !segment.isEmpty {
                    pictureLength += segment.timeMapping.target.duration.seconds
                }
            }
            check(abs(fileLength - 25) < 0.2, "still screen segments: a 25 s clip is 25 s long", "file \(fileLength) s")
            check(abs(pictureLength - 25) < 0.2, "still screen segments: the picture lasts the whole 25 s", "video \(pictureLength) s")
            try? FileManager.default.removeItem(at: clip.url)
        } catch {
            check(false, "still screen segments: export", "\(error)")
        }
        await buffer.finishCurrentSegment()
        try? FileManager.default.removeItem(at: support)
    }

    /// A segment that holds one frame when the next one starts (a frame rate change right after a
    /// still second) still has a duration: its picture stays on screen until the next frame. It is
    /// kept, or the clip loses that stretch between the segments around it.
    static func checkSingleFrameSegmentKeepsItsTime(folder: URL) async {
        let previousSupport = AppPaths.supportOverride
        let support = folder.appendingPathComponent("single-frame-segment", isDirectory: true)
        AppPaths.supportOverride = support
        defer {
            AppPaths.supportOverride = previousSupport
        }
        let framesPerSecond = 10
        let size = CGSize(width: 160, height: 96)
        let buffer = ScreenBuffer(displayID: 990_004)
        buffer.queue.sync {
            buffer.configuration.framesPerSecond = framesPerSecond
            buffer.outputSize = size
        }
        guard let pixels = solidPixelBuffer(size: size) else {
            check(false, "single-frame segment: made-up frame")
            return
        }
        let start = CACurrentMediaTime()
        // 2 s of frames, then one frame that starts a segment of its own, then a second later the
        // next segment, then 2 s of frames again.
        var times: [Double] = []
        var time = start - 6
        while time < start - 4 {
            times.append(time)
            time += 1.0 / Double(framesPerSecond)
        }
        let lonelyFrame = start - 3.5
        let nextSegmentFrame = start - 2.5
        for time in times {
            await waitUntilBufferTakesFrames(buffer)
            if let sample = sampleBuffer(pixels, at: time) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
            }
        }
        var later: [Double] = []
        time = nextSegmentFrame
        while time < start - 0.5 {
            later.append(time)
            time += 1.0 / Double(framesPerSecond)
        }
        for (position, time) in ([lonelyFrame] + later).enumerated() {
            await waitUntilBufferTakesFrames(buffer)
            guard let sample = sampleBuffer(pixels, at: time) else { continue }
            buffer.queue.sync {
                // The lonely frame and the one after it each start a new segment.
                if position <= 1 {
                    buffer.startNewSegment = true
                }
                buffer.appendVideo(sample, at: time)
            }
        }
        await buffer.finishCurrentSegment()
        let segments = buffer.queue.sync { buffer.segments }
        var lonelyKept = false
        for segment in segments where abs(segment.start - lonelyFrame) < 0.001 {
            lonelyKept = abs(segment.end - nextSegmentFrame) < 0.01
        }
        check(lonelyKept, "single-frame segment: kept until the next frame", describe(segments, from: start))
        var gaps: [String] = []
        for position in 1..<max(segments.count, 1) {
            let gap = segments[position].start - segments[position - 1].end
            if abs(gap) > 0.01 {
                gaps.append(String(format: "%.3f s", gap))
            }
        }
        check(segments.count == 3 && gaps.isEmpty, "single-frame segment: the segments around it leave no gap", "\(segments.count) segments, gaps \(gaps.joined(separator: ", "))")
        try? FileManager.default.removeItem(at: support)
    }

    /// A save closes the open segment one frame after the last frame. On a still screen the next
    /// frame is the heartbeat's, up to a second later: the segment it opens starts where the closed one
    /// ended (with the last picture), so a later save covering that moment has no hole in it.
    static func checkSaveLeavesNoGapOnStillScreen(folder: URL) async {
        let previousSupport = AppPaths.supportOverride
        let support = folder.appendingPathComponent("save-no-gap", isDirectory: true)
        AppPaths.supportOverride = support
        defer {
            AppPaths.supportOverride = previousSupport
        }
        let framesPerSecond = 10
        let size = CGSize(width: 160, height: 96)
        let buffer = ScreenBuffer(displayID: 990_005)
        buffer.queue.sync {
            buffer.configuration.framesPerSecond = framesPerSecond
            buffer.outputSize = size
        }
        guard let pixels = solidPixelBuffer(size: size) else {
            check(false, "save on a still screen: made-up frame")
            return
        }
        // 3 s of frames until now, then a save of the last 2 s while the buffer runs.
        let start = CACurrentMediaTime()
        var time = start - 3
        while time <= start {
            await waitUntilBufferTakesFrames(buffer)
            if let sample = sampleBuffer(pixels, at: time) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
            }
            time += 1.0 / Double(framesPerSecond)
        }
        buffer.startHeartbeat()
        let firstSave = CACurrentMediaTime()
        do {
            let clip = try await ClipComposer.export(buffers: [buffer], ranges: [(start: firstSave - 2, end: firstSave)], area: nil, framesPerSecond: framesPerSecond)
            try? FileManager.default.removeItem(at: clip.url)
        } catch {
            check(false, "save on a still screen: first export", "\(error)")
        }
        // The screen stays still for more than a second: the heartbeat sends the next frame.
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        let heartbeatFrame = CACurrentMediaTime()
        if let sample = sampleBuffer(pixels, at: heartbeatFrame) {
            buffer.queue.sync {
                buffer.appendVideo(sample, at: heartbeatFrame)
            }
        }
        let secondSave = CACurrentMediaTime()
        do {
            let clip = try await ClipComposer.export(buffers: [buffer], ranges: [(start: firstSave - 1, end: secondSave)], area: nil, framesPerSecond: framesPerSecond)
            let segments = buffer.queue.sync { buffer.segments }
            var gaps: [String] = []
            for position in 1..<max(segments.count, 1) {
                let gap = segments[position].start - segments[position - 1].end
                if abs(gap) > 0.01 {
                    gaps.append(String(format: "%.3f s", gap))
                }
            }
            check(gaps.isEmpty, "save on a still screen: the next segment starts where the save closed the last one", "\(describe(segments, from: secondSave)) gaps \(gaps.joined(separator: ", "))")
            let asset = AVURLAsset(url: clip.url)
            var pictureLength = 0.0
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                for segment in try await track.load(.segments) where !segment.isEmpty {
                    pictureLength += segment.timeMapping.target.duration.seconds
                }
            }
            let expected = secondSave - (firstSave - 1)
            check(abs(pictureLength - expected) < 0.15, "save on a still screen: a second save across the first has picture all the way", String(format: "video %.3f s of %.3f s", pictureLength, expected))
            try? FileManager.default.removeItem(at: clip.url)
        } catch {
            check(false, "save on a still screen: second export", "\(error)")
        }
        buffer.stopHeartbeat()
        await buffer.finishCurrentSegment()
        try? FileManager.default.removeItem(at: support)
    }

    /// `buffer-seconds` for e2e: how much video a buffer holds, from its first segment to now.
    static func checkBufferHeldSeconds(folder: URL) async {
        let previousSupport = AppPaths.supportOverride
        let support = folder.appendingPathComponent("held-seconds", isDirectory: true)
        AppPaths.supportOverride = support
        defer {
            AppPaths.supportOverride = previousSupport
        }
        let framesPerSecond = 10
        let size = CGSize(width: 160, height: 96)
        let buffer = ScreenBuffer(displayID: 990_006)
        buffer.queue.sync {
            buffer.configuration.framesPerSecond = framesPerSecond
            buffer.outputSize = size
        }
        let empty = buffer.heldSeconds(now: CACurrentMediaTime())
        check(empty == 0, "buffer seconds: an empty buffer holds nothing", "\(empty)")
        guard let pixels = solidPixelBuffer(size: size) else {
            check(false, "buffer seconds: made-up frame")
            return
        }
        let start = CACurrentMediaTime()
        var time = start - 12
        while time <= start {
            await waitUntilBufferTakesFrames(buffer)
            if let sample = sampleBuffer(pixels, at: time) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
            }
            time += 1.0 / Double(framesPerSecond)
        }
        // 12 s across a finished and an open segment.
        let held = buffer.heldSeconds(now: start)
        check(abs(held - 12) < 0.05, "buffer seconds: 12 s of frames read as 12 s", String(format: "%.3f s", held))
        await buffer.finishCurrentSegment()
        try? FileManager.default.removeItem(at: support)
    }

    /// Segment layout relative to `now`, for a failed check.
    private static func describe(_ segments: [ScreenBuffer.Segment], from now: Double) -> String {
        var parts: [String] = []
        for segment in segments {
            parts.append(String(format: "[%.2f…%.2f]", segment.start - now, segment.end - now))
        }
        return parts.joined(separator: " ")
    }

    /// During an area recording only the displays the area touches run at native resolution and the
    /// recording frame rate; the others keep the buffer's resolution and frame rate.
    static func checkBufferConfigurationPerDisplay() {
        let app = AppState.shared
        let saved = app.nativeDisplaysForArea
        defer {
            app.nativeDisplaysForArea = saved
        }
        let touched: CGDirectDisplayID = 990_101
        let other: CGDirectDisplayID = 990_102
        app.nativeDisplaysForArea = [touched]
        let native = app.bufferConfiguration(for: touched)
        let normal = app.bufferConfiguration(for: other)
        let recordingRate = max(app.settings.recordingFramesPerSecond, app.settings.framesPerSecond)
        check(native.maxHeight == 0 && native.framesPerSecond == recordingRate, "the display the area touches runs at native resolution and the recording frame rate", "maxHeight \(native.maxHeight), \(native.framesPerSecond) fps, expected \(recordingRate)")
        check(normal.maxHeight == app.settings.maxHeight && normal.framesPerSecond == app.settings.framesPerSecond, "a display the area does not touch keeps the buffer's resolution and frame rate", "maxHeight \(normal.maxHeight), \(normal.framesPerSecond) fps")
        check(native.retentionSeconds == normal.retentionSeconds && native.showsCursor == normal.showsCursor, "native resolution changes nothing else")
        app.nativeDisplaysForArea = []
        let none = app.bufferConfiguration(for: touched)
        check(none.maxHeight == app.settings.maxHeight && none.framesPerSecond == app.settings.framesPerSecond, "without an area recording every display keeps the buffer's resolution")
    }

    /// Moving the area while recording takes each newly touched display to native resolution once,
    /// never takes one back during the recording, and does nothing without a recording. Real screen
    /// frames, no buffers (the self-test has none), so no stream is changed.
    static func checkAreaMovedGrowsNativeSet() {
        let app = AppState.shared
        guard let screen = NSScreen.screens.first else { return }
        let display = AppState.displayID(of: screen)
        let savedNative = app.nativeDisplaysForArea
        let savedRecording = app.recording
        defer {
            app.nativeDisplaysForArea = savedNative
            app.recording = savedRecording
        }
        app.nativeDisplaysForArea = []
        app.recording = nil
        app.areaMoved(to: screen.frame.insetBy(dx: 100, dy: 100))
        check(app.nativeDisplaysForArea.isEmpty, "moving an area without a recording changes no display")
        app.recording = RecordingSession()
        app.areaMoved(to: screen.frame.insetBy(dx: 100, dy: 100))
        check(app.nativeDisplaysForArea == [display], "the display a moved area touches goes to native resolution", "\(app.nativeDisplaysForArea)")
        let farAway = CGRect(x: screen.frame.maxX + 100_000, y: 0, width: 200, height: 200)
        app.areaMoved(to: farAway)
        check(app.nativeDisplaysForArea == [display], "a display the area left stays at native resolution during the recording", "\(app.nativeDisplaysForArea)")
    }

    /// A display that goes to native resolution while an area is recorded (the area was moved onto it)
    /// starts a new segment at the new size with the next real frame, and the clip scales the earlier,
    /// smaller part up to the clip's density instead of leaving it small in a corner. Made-up frames:
    /// light grey at 160x96 pixels on a 160x96 pt display (1x), then dark grey at 320x192 (2x).
    static func checkClipAcrossSizeChange(folder: URL) async {
        let previousSupport = AppPaths.supportOverride
        let support = folder.appendingPathComponent("clip-across-size", isDirectory: true)
        AppPaths.supportOverride = support
        defer {
            AppPaths.supportOverride = previousSupport
        }
        let framesPerSecond = 10
        let small = CGSize(width: 160, height: 96)
        let large = CGSize(width: 320, height: 192)
        let buffer = ScreenBuffer(displayID: 990_002)
        buffer.setDisplayFrameForTests(CGRect(x: 0, y: 0, width: 160, height: 96))
        buffer.queue.sync {
            buffer.configuration.framesPerSecond = framesPerSecond
            buffer.outputSize = small
        }
        guard let light = solidPixelBuffer(size: small, grey: 0xC0), let dark = solidPixelBuffer(size: large, grey: 0x40) else {
            check(false, "clip across a size change: made-up frames")
            return
        }
        let start = CACurrentMediaTime()
        var time = start - 8
        while time <= start - 5 {
            await waitUntilBufferTakesFrames(buffer)
            if let sample = sampleBuffer(light, at: time) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
            }
            time += 1.0 / Double(framesPerSecond)
        }
        // What upgradeToNative does once the stream takes the native size. A size change asks for no
        // segment break of its own: the first native frame starts the new segment.
        let breakAsked = buffer.queue.sync { () -> Bool in
            buffer.applyNativeSize(large, framesPerSecond: framesPerSecond)
            return buffer.startNewSegment
        }
        check(!breakAsked, "a size change asks for no extra segment break")
        // A frame still on its way at the old size goes into the small segment, not into a segment of
        // its own that would be dropped as one frame.
        let inTransit = time
        await waitUntilBufferTakesFrames(buffer)
        if let sample = sampleBuffer(light, at: inTransit) {
            buffer.queue.sync {
                buffer.appendVideo(sample, at: inTransit)
            }
        }
        time += 1.0 / Double(framesPerSecond)
        while time <= start - 1 {
            await waitUntilBufferTakesFrames(buffer)
            if let sample = sampleBuffer(dark, at: time) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
            }
            time += 1.0 / Double(framesPerSecond)
        }
        // A heartbeat repeat of an old small frame after the native ones must not go into the big segment.
        let lastTime = buffer.queue.sync { buffer.lastFrameTime }
        if let stale = sampleBuffer(light, at: lastTime + 0.05) {
            buffer.queue.sync {
                buffer.appendVideo(stale, at: lastTime + 0.05, allowRotation: false)
            }
        }
        let openSize = buffer.queue.sync { () -> CGSize in
            guard let index = buffer.currentSegmentIndex else { return .zero }
            return buffer.segments[index].size
        }
        check(openSize == large, "the open segment keeps one size", "open segment \(openSize)")

        let saveMoment = CACurrentMediaTime()
        do {
            let clip = try await ClipComposer.export(buffers: [buffer], ranges: [(start: start - 7.5, end: saveMoment)], area: CGRect(x: 0, y: 0, width: 160, height: 96), framesPerSecond: framesPerSecond)
            let segmentSizes = buffer.queue.sync { () -> [CGSize] in
                var sizes: [CGSize] = []
                for segment in buffer.segments where segment.finished {
                    sizes.append(segment.size)
                }
                return sizes
            }
            check(segmentSizes.first == small && segmentSizes.last == large, "the size change started a new segment", "\(segmentSizes)")
            // A finished segment ends one frame after its last frame: past the in-transit frame's time
            // only when that frame is in it.
            let keptInTransit = buffer.queue.sync { () -> Bool in
                for segment in buffer.segments where segment.finished && segment.size == small && segment.start <= inTransit && segment.end > inTransit + 0.01 {
                    return true
                }
                return false
            }
            check(keptInTransit, "the last frame at the old size is kept")
            if let lastSegment = buffer.queue.sync(execute: { buffer.segments.last }) {
                let track = try await AVURLAsset(url: lastSegment.url).loadTracks(withMediaType: .video).first
                let natural = try await track?.load(.naturalSize) ?? .zero
                check(natural == large, "the new segment's writer has the native size", "\(natural)")
            }
            let asset = AVURLAsset(url: clip.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let early = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            let late = try await generator.image(at: CMTime(seconds: clip.duration - 1, preferredTimescale: 600)).image
            check(early.width == 320 && early.height == 192, "the clip has the native density", "\(early.width)x\(early.height)")
            let earlyCorner = greyNearBottomRight(early)
            let lateCorner = greyNearBottomRight(late)
            check(earlyCorner > 140, "the part from before the size change fills the clip (scaled up, not in a corner)", "bottom-right grey \(earlyCorner)")
            check(lateCorner > 35 && lateCorner < 100, "the native part fills the clip", "bottom-right grey \(lateCorner)")
            try? FileManager.default.removeItem(at: clip.url)
        } catch {
            check(false, "clip across a size change: export", "\(error)")
        }
        await buffer.finishCurrentSegment()
        try? FileManager.default.removeItem(at: support)
    }

    /// The red channel of a pixel near the bottom-right corner (where a picture left small would be black).
    private static func greyNearBottomRight(_ image: CGImage) -> Int {
        guard let pixels = ScreenshotComparison.rgba(image, width: image.width, height: image.height) else { return -1 }
        let column = image.width - 8
        let row = image.height - 8
        return Int(pixels[(row * image.width + column) * 4])
    }

    /// Waits while the buffer's writer is busy, so no made-up frame is dropped.
    private static func waitUntilBufferTakesFrames(_ buffer: ScreenBuffer) async {
        for _ in 0..<200 {
            let ready = buffer.queue.sync { buffer.videoInput?.isReadyForMoreMediaData ?? true }
            if ready { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// A grey BGRA picture like the ones ScreenCaptureKit sends; `grey` is every channel's value.
    private static func solidPixelBuffer(size: CGSize, grey: Int32 = 0x80) -> CVPixelBuffer? {
        var pixels: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixels)
        guard let pixels else { return nil }
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            memset(base, grey, CVPixelBufferGetBytesPerRow(pixels) * Int(size.height))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    private static func sampleBuffer(_ pixels: CVPixelBuffer, at seconds: Double) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        return sample
    }
}
#endif
