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

    /// The menu asks for the buffer's status once a second on the main thread. The capture queue
    /// opens a writer and an encoder every 10 s, finishes segments and deletes files, so the status
    /// is what the queue last published and the answer never waits for the queue.
    static func checkBufferStatusDoesNotWait(folder: URL) async {
        let previousSupport = AppPaths.supportOverride
        let support = folder.appendingPathComponent("buffer-status", isDirectory: true)
        AppPaths.supportOverride = support
        defer {
            AppPaths.supportOverride = previousSupport
        }
        let framesPerSecond = 10
        let size = CGSize(width: 160, height: 96)
        let buffer = ScreenBuffer(displayID: 990_011)
        buffer.queue.sync {
            buffer.configuration.framesPerSecond = framesPerSecond
            buffer.outputSize = size
        }
        let empty = buffer.status()
        check(empty.covered == 0 && empty.activity == [Double](repeating: 0, count: 16), "buffer status: an empty buffer covers nothing", "\(empty)")
        guard let pixels = solidPixelBuffer(size: size) else {
            check(false, "buffer status: made-up frame")
            return
        }
        // 12 s of frames until now: with the 180 s window, all of them are in the last two bars.
        let start = CACurrentMediaTime()
        let firstFrame = start - 12
        var time = firstFrame
        while time <= start {
            await waitUntilBufferTakesFrames(buffer)
            if let sample = sampleBuffer(pixels, at: time) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
            }
            time += 1.0 / Double(framesPerSecond)
        }
        let expected = CACurrentMediaTime() - firstFrame
        let status = buffer.status()
        check(abs(status.covered - expected) < 0.1, "buffer status: the covered time is the time since the first frame", String(format: "%.3f s of %.3f s", status.covered, expected))
        check(status.activity.count == 16 && status.activity[15] == 1 && status.activity[0] == 0, "buffer status: the newest bar is the busiest", "\(status.activity)")

        // The queue is busy for a second, as while a segment opens on a loaded Mac.
        let gate = DispatchSemaphore(value: 0)
        buffer.queue.async {
            gate.wait()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            gate.signal()
        }
        let asked = CACurrentMediaTime()
        let whileBusy = buffer.status()
        let waited = CACurrentMediaTime() - asked
        check(waited < 0.2 && whileBusy.covered >= status.covered, "buffer status: the answer does not wait for a busy capture queue", String(format: "waited %.2f s", waited))
        await buffer.finishCurrentSegment()
        try? FileManager.default.removeItem(at: support)
    }

    /// The stream's delegate, a stop and the main thread touch the buffer's heartbeat at once (the lid
    /// closes while the displays change), and the microphone's queue reads the sink the main thread
    /// replaces. Both are behind a lock; without it these loops crash the self-test.
    static func checkBufferStateFromSeveralThreads() {
        let buffer = ScreenBuffer(displayID: 990_012)
        DispatchQueue.concurrentPerform(iterations: 20_000) { iteration in
            if iteration % 2 == 0 {
                buffer.startHeartbeat()
            } else {
                buffer.stopHeartbeat()
            }
        }
        buffer.stopHeartbeat()
        check(!buffer.hasHeartbeat, "the buffer's heartbeat takes starts and stops from several threads at once")

        final class Readers: @unchecked Sendable {
            var finished = false
        }
        let app = AppState.shared
        let savedSink = app.micSink
        let readers = Readers()
        let done = DispatchSemaphore(value: 0)
        for _ in 0..<3 {
            DispatchQueue.global().async {
                var seen = 0
                while !readers.finished {
                    if let sink = app.micSink {
                        seen += Int(sink.displayID % 2)
                    }
                }
                done.signal()
            }
        }
        for number in 0..<20_000 {
            app.micSink = ScreenBuffer(displayID: CGDirectDisplayID(991_000 + number))
        }
        readers.finished = true
        for _ in 0..<3 {
            done.wait()
        }
        app.micSink = savedSink
        check(app.micSink === savedSink, "the microphone's sink is replaced while its queue reads it")
    }

    /// A writer that failed (a full disk) refuses every frame until its segment ends. That is one line
    /// in the log and a count at the end of the segment, not a line per frame. The writer is failed
    /// here by a frame stamped before the ones it already has.
    static func checkFailedAppendsLogOnce(folder: URL) async {
        let previousSupport = AppPaths.supportOverride
        let support = folder.appendingPathComponent("failed-appends", isDirectory: true)
        AppPaths.supportOverride = support
        defer {
            AppPaths.supportOverride = previousSupport
        }
        let framesPerSecond = 10
        let size = CGSize(width: 160, height: 96)
        let buffer = ScreenBuffer(displayID: 990_013)
        buffer.queue.sync {
            buffer.configuration.framesPerSecond = framesPerSecond
            buffer.outputSize = size
        }
        guard let pixels = solidPixelBuffer(size: size) else {
            check(false, "failed appends: made-up frame")
            return
        }
        final class Lines: @unchecked Sendable {
            private let lock = NSLock()
            private var kept: [String] = []
            func add(_ line: String) {
                lock.lock()
                kept.append(line)
                lock.unlock()
            }
            var all: [String] {
                lock.lock()
                defer { lock.unlock() }
                return kept
            }
        }
        // Only this buffer's lines, and they stay out of the real log file.
        let lines = Lines()
        Log.errorObserver = { line in
            if !line.contains("buffer[990013]") { return false }
            lines.add(line)
            return true
        }
        defer {
            Log.errorObserver = nil
        }
        let start = CACurrentMediaTime()
        var time = start - 4
        while time <= start - 3 {
            await waitUntilBufferTakesFrames(buffer)
            if let sample = sampleBuffer(pixels, at: time) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
            }
            time += 1.0 / Double(framesPerSecond)
        }
        for step in 0..<20 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if let sample = sampleBuffer(pixels, at: start - 10 + Double(step) * 0.01) {
                buffer.queue.sync {
                    buffer.appendVideo(sample, at: time)
                }
            }
            time += 1.0 / Double(framesPerSecond)
        }
        let refused = buffer.queue.sync { buffer.failedAppends }
        var whileOpen = 0
        for line in lines.all where line.contains("append failed") {
            whileOpen += 1
        }
        check(refused >= 10 && whileOpen == 1, "failed appends: one log line while the segment is open", "\(refused) frames refused, \(whileOpen) lines")
        await buffer.finishCurrentSegment()
        var counted = 0
        for line in lines.all where line.contains("append failed for \(refused) frames") {
            counted += 1
        }
        check(counted == 1, "failed appends: the count is logged once, when the segment ends", lines.all.joined(separator: " | "))
        try? FileManager.default.removeItem(at: support)
    }

    /// A recording keeps every segment and would fill the disk. The buffer looks at the free space
    /// when a recording starts and at every new segment, and tells the app once per recording; the
    /// rolling buffer alone (nothing kept) tells nothing.
    static func checkRecordingIsToldAboutFullDisk(folder: URL) async {
        let previousSupport = AppPaths.supportOverride
        let support = folder.appendingPathComponent("disk-almost-full", isDirectory: true)
        AppPaths.supportOverride = support
        defer {
            AppPaths.supportOverride = previousSupport
        }
        let framesPerSecond = 10
        let size = CGSize(width: 160, height: 96)
        let almostFull: Int64 = 500_000_000
        let plenty: Int64 = 50_000_000_000
        let buffer = ScreenBuffer(displayID: 990_014)
        buffer.queue.sync {
            buffer.configuration.framesPerSecond = framesPerSecond
            buffer.outputSize = size
            buffer.freeBytesForTests = almostFull
        }
        var told = 0
        buffer.onDiskAlmostFull = {
            told += 1
        }
        // The made-up full disk stays out of the real log file.
        Log.errorObserver = { line in
            return line.contains("buffer[990014]")
        }
        defer {
            Log.errorObserver = nil
        }
        guard let pixels = solidPixelBuffer(size: size) else {
            check(false, "disk almost full: made-up frame")
            return
        }
        var time = CACurrentMediaTime() - 5
        /// Feeds half a second of frames; the first one starts a new segment when asked.
        func feed(newSegment: Bool) async {
            for position in 0..<5 {
                await waitUntilBufferTakesFrames(buffer)
                if let sample = sampleBuffer(pixels, at: time) {
                    let frameTime = time
                    buffer.queue.sync {
                        if newSegment && position == 0 {
                            buffer.startNewSegment = true
                        }
                        buffer.appendVideo(sample, at: frameTime)
                    }
                }
                time += 1.0 / Double(framesPerSecond)
            }
            await settle(buffer)
        }
        await feed(newSegment: false)
        check(told == 0, "disk almost full: the buffer alone, with no recording, stops nothing", "told \(told) times")
        buffer.pin(from: time)
        await settle(buffer)
        check(told == 1, "disk almost full: a recording that starts is told at once", "told \(told) times")
        await feed(newSegment: true)
        check(told == 1, "disk almost full: a recording is told once", "told \(told) times")

        buffer.pin(from: nil)
        buffer.queue.sync {
            buffer.freeBytesForTests = plenty
        }
        buffer.pin(from: time)
        await feed(newSegment: true)
        check(told == 1, "disk almost full: a recording with room goes on", "told \(told) times")
        buffer.queue.sync {
            buffer.freeBytesForTests = almostFull
        }
        await feed(newSegment: false)
        check(told == 1, "disk almost full: the disk is looked at when a segment starts, not at every frame", "told \(told) times")
        await feed(newSegment: true)
        check(told == 2, "disk almost full: a disk that fills up while recording is seen at the next segment", "told \(told) times")
        buffer.pin(from: nil)
        await buffer.finishCurrentSegment()
        try? FileManager.default.removeItem(at: support)
    }

    /// Waits until the buffer's queue, and then the main queue, ran what was put on them.
    private static func settle(_ buffer: ScreenBuffer) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            buffer.queue.async {
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }

    /// After a start the app checks every 2 s, up to a minute, whether the capture leaves its own
    /// windows out. A new start or a pause ends the check of the start before it, which would go on
    /// asking macOS about the new buffers.
    static func checkFilterRefreshEndsWithTheBuffer() async {
        let app = AppState.shared
        let savedState = app.bufferState
        let savedRefresh = app.bufferFilterRefresh
        defer {
            app.bufferFilterRefresh = savedRefresh
            app.setBufferState(savedState)
        }
        let beforeStart = Task {
            _ = try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        app.bufferFilterRefresh = beforeStart
        // Without Screen Recording access a start ends right away and captures nothing.
        ScreenBuffer.pretendNoAccess = true
        await app.startBuffer()
        ScreenBuffer.pretendNoAccess = false
        check(beforeStart.isCancelled, "a new buffer start ends the capture filter check of the start before it")
        let beforePause = Task {
            _ = try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        app.bufferFilterRefresh = beforePause
        await app.pauseBuffer()
        check(beforePause.isCancelled, "pausing the buffer ends the capture filter check")
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
