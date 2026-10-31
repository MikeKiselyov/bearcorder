import AVFoundation
import AppCore
import AppKit
import CoreMedia
import QuartzCore
import ScreenCaptureKit

extension ScreenBuffer {
    /// Appends one frame, rotating to a new segment when the current one is long enough. Queue only.
    /// `allowRotation` false keeps the frame in the open segment (the catch-up frame at a save: alone in
    /// a new segment it would be dropped as unplayable, and the clip would end early).
    func appendVideo(_ sampleBuffer: CMSampleBuffer, at time: Double, allowRotation: Bool = true) {
        if time <= lastFrameTime { return }

        // A segment has one size. A frame of another size (the display went to native resolution)
        // starts a new segment, unless it may not rotate: then it is left out.
        let frameSize = ScreenBuffer.pixelSize(of: sampleBuffer) ?? outputSize
        var sizeChanged = false
        if let index = currentSegmentIndex, segments[index].size != frameSize {
            sizeChanged = true
        }
        if sizeChanged && !allowRotation { return }
        var segmentFinished = false
        if let index = currentSegmentIndex, sizeChanged || (allowRotation && (time - segments[index].start >= segmentLength || startNewSegment)) {
            startNewSegment = false
            // The old segment's last picture stays on screen until this frame: it ends where the new
            // one starts, so a still screen (a frame a second) leaves no gap at the rotation.
            finishSegmentOnQueue(nextFrameAt: time, completion: nil)
            segmentFinished = true
        }
        if writer == nil {
            bridgeFromLastSegment(to: time, size: frameSize)
        }
        if writer == nil {
            openSegment(at: time, size: frameSize)
        }
        guard let input = videoInput, let index = currentSegmentIndex else { return }
        if !input.isReadyForMoreMediaData {
            droppedFrames += 1
            // A frame now and then while the Mac is busy is normal and the clip does not show it;
            // every 30 dropped (2 s at 15 fps) is worth an error.
            if droppedFrames == 1 {
                Log.info("buffer[\(displayID)] writer not ready, dropped a frame")
            } else if droppedFrames % 30 == 0 {
                Log.error("buffer[\(displayID)] writer not ready, dropped \(droppedFrames) frames")
            }
        }
        if input.isReadyForMoreMediaData {
            if !input.append(sampleBuffer) {
                Log.error("buffer[\(displayID)] append failed: \(writer?.error?.localizedDescription ?? "unknown") status=\(writer?.status.rawValue ?? -1)")
            } else {
                receivedFrames += 1
                if receivedFrames == 1 || receivedFrames % 900 == 0 {
                    Log.info("buffer[\(displayID)] frames written: \(receivedFrames)")
                }
                segments[index].end = time
                lastFrameTime = time
                lastSampleBuffer = sampleBuffer
                frameTimes.append(time)
                // Trim old timestamps in batches (every few seconds), not one by one per frame.
                let cutoff = time - configuration.retentionSeconds
                if let first = frameTimes.first, first < cutoff - 5 {
                    var stale = 0
                    for value in frameTimes {
                        if value >= cutoff { break }
                        stale += 1
                    }
                    frameTimes.removeFirst(stale)
                }
            }
        }
        // Old segments go when a segment finishes, otherwise at most once a second, not on every frame.
        if BufferTiming.shouldPrune(now: time, lastPrune: lastPrune, segmentFinished: segmentFinished) {
            lastPrune = time
            pruneSegments(now: time)
        }
    }

    /// A save closed the last segment one frame after its last frame. On a still screen the next frame
    /// comes from the heartbeat up to a second later, and the segment it opens would leave that second
    /// out of a later clip. While the buffer runs, the last picture opens the new segment where the
    /// closed one ended (as catchUp does), so the segments stay contiguous. Queue only.
    private func bridgeFromLastSegment(to time: Double, size: CGSize) {
        // A stopped buffer (no heartbeat) gets no made-up frames.
        guard heartbeat != nil, let last = lastSampleBuffer, let previous = segments.last else { return }
        let gapStart = previous.end
        // A rotation already ends the old segment at this frame.
        if time - gapStart < 0.001 || gapStart <= lastFrameTime { return }
        if previous.size != size || ScreenBuffer.pixelSize(of: last) != size { return }
        if let copy = ScreenBuffer.retimed(last, to: gapStart) {
            appendVideo(copy, at: gapStart, allowRotation: false)
        }
    }

    /// The pixel size of a frame, nil without a picture.
    static func pixelSize(of sampleBuffer: CMSampleBuffer) -> CGSize? {
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return CGSize(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image))
    }

    private func openSegment(at time: Double, size: CGSize) {
        let url = AppPaths.buffer.appendingPathComponent("segment-\(displayID)-\(UUID().uuidString).mov")
        guard let newWriter = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            Log.error("buffer[\(displayID)] cannot create writer")
            return
        }
        let fps = configuration.framesPerSecond
        let pixels = size.width * size.height
        let bitrate = min(20_000_000, max(2_000_000, pixels * Double(fps) * 0.12))
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(bitrate),
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard newWriter.canAdd(input) else { return }
        newWriter.add(input)

        // Audio tracks keep a fixed order: system first, then microphone.
        var newAudioInputs: [AudioSource: AVAssetWriterInput] = [:]
        var sources: [AudioSource] = []
        if configuration.systemAudio { sources.append(.system) }
        if configuration.microphone { sources.append(.microphone) }
        for source in sources {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if newWriter.canAdd(audioInput) {
                newWriter.add(audioInput)
                newAudioInputs[source] = audioInput
            }
        }

        guard newWriter.startWriting() else {
            Log.error("buffer[\(displayID)] startWriting failed: \(newWriter.error?.localizedDescription ?? "unknown")")
            return
        }
        newWriter.startSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 600))
        writer = newWriter
        videoInput = input
        audioInputs = newAudioInputs
        segments.append(Segment(url: url, start: time, end: time, state: .open, size: size))
        currentSegmentIndex = segments.count - 1
    }

    /// Finishes the open segment. Queue only. Completion runs on the queue. `nextFrameAt` is the time of
    /// the frame that starts the next segment: the session ends there. Without one (a save, a stop)
    /// it ends one frame after the last frame.
    private func finishSegmentOnQueue(nextFrameAt: Double? = nil, completion: (() -> Void)?) {
        guard let currentWriter = writer, let input = videoInput, let index = currentSegmentIndex else {
            completion?()
            return
        }
        let inputs = audioInputs
        writer = nil
        videoInput = nil
        audioInputs = [:]
        currentSegmentIndex = nil
        let url = segments[index].url

        // A single frame has a duration only when the next frame ends it: its picture stays until then.
        var hasNextFrame = false
        if let next = nextFrameAt, next > segments[index].end {
            hasNextFrame = true
        }
        if segments[index].end <= segments[index].start && !hasNextFrame {
            // Single frame with nothing after it: nothing playable, drop the file.
            currentWriter.cancelWriting()
            segments.remove(at: index)
            try? FileManager.default.removeItem(at: url)
            completion?()
            return
        }
        input.markAsFinished()
        for audioInput in inputs.values {
            audioInput.markAsFinished()
        }
        // End the session one frame after the last frame so it has a duration, or at the next frame.
        var sessionEnd = segments[index].end + 1.0 / Double(configuration.framesPerSecond)
        if let next = nextFrameAt, next > segments[index].end {
            sessionEnd = next
        }
        currentWriter.endSession(atSourceTime: CMTime(seconds: sessionEnd, preferredTimescale: 600))
        segments[index].end = sessionEnd
        let segmentEnd = sessionEnd
        currentWriter.finishWriting { [weak self] in
            guard let self = self else { return }
            self.queue.async {
                let completed = currentWriter.status == .completed
                for position in 0..<self.segments.count where self.segments[position].url == url {
                    self.segments[position].state = completed ? .finished : .failed
                }
                if !completed {
                    Log.error("buffer[\(self.displayID)] segment finish failed: \(currentWriter.error?.localizedDescription ?? "status \(currentWriter.status.rawValue)")")
                    // A failed file is of no use: remove it now, not when it leaves the window.
                    self.pruneSegments(now: segmentEnd)
                }
                completion?()
            }
        }
    }

    func finishCurrentSegment() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.finishSegmentOnQueue {
                    continuation.resume()
                }
            }
        }
    }

    private func pruneSegments(now: Double) {
        var keepFrom = now - configuration.retentionSeconds - segmentLength
        if let pinned = pinnedFrom {
            keepFrom = min(keepFrom, pinned - segmentLength)
        }
        var kept: [Segment] = []
        for segment in segments {
            if SegmentPruning.shouldRemove(state: segment.state, end: segment.end, keepFrom: keepFrom) {
                try? FileManager.default.removeItem(at: segment.url)
            } else {
                kept.append(segment)
            }
        }
        if kept.count == segments.count { return }
        var openURL: URL? = nil
        if let index = currentSegmentIndex {
            openURL = segments[index].url
        }
        segments = kept
        currentSegmentIndex = nil
        if let url = openURL {
            for position in 0..<segments.count where segments[position].url == url {
                currentSegmentIndex = position
            }
        }
    }

    // MARK: Status for the UI

    /// Seconds of screen available right now, and frame activity per bucket (oldest first).
    func status(buckets: Int) -> (covered: Double, activity: [Double]) {
        return queue.sync {
            let now = CACurrentMediaTime()
            var covered = 0.0
            if let first = segments.first {
                covered = min(configuration.retentionSeconds, now - first.start)
            }
            let window = configuration.retentionSeconds
            var counts = [Double](repeating: 0, count: buckets)
            for time in frameTimes {
                let age = now - time
                if age < 0 || age >= window { continue }
                let bucket = buckets - 1 - Int(age / window * Double(buckets))
                if bucket >= 0 && bucket < buckets {
                    counts[bucket] += 1
                }
            }
            let maximum = counts.max() ?? 0
            var activity: [Double] = []
            for count in counts {
                activity.append(maximum > 0 ? count / maximum : 0)
            }
            return (covered: max(0, covered), activity: activity)
        }
    }

    /// Keeps segments from `time` on (for "record from now"). Nil releases the pin.
    func pin(from time: Double?) {
        queue.async {
            self.pinnedFrom = time
        }
    }

    // MARK: Export

    /// Closes the open segment so everything up to now is in finished files. Call `catchUp(now:)`
    /// first, so a still screen reaches the moment of saving.
    func prepareForExport() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.flushHeldFrame(force: true)
                self.finishSegmentOnQueue {
                    continuation.resume()
                }
            }
        }
    }

    /// Segment layout relative to now, for the log.
    func describeSegments() -> String {
        return queue.sync {
            let now = CACurrentMediaTime()
            var parts: [String] = []
            for segment in segments {
                var label = "open"
                if segment.state == .finished {
                    label = "done"
                }
                if segment.state == .failed {
                    label = "failed"
                }
                parts.append(String(format: "[%.2f…%.2f %@]", segment.start - now, segment.end - now, label))
            }
            return parts.joined(separator: " ")
        }
    }

    /// Host-time span covered by finished segments.
    func availability() -> (start: Double, end: Double)? {
        return queue.sync {
            var start: Double? = nil
            var end: Double? = nil
            for segment in segments where segment.finished {
                start = min(start ?? segment.start, segment.start)
                end = max(end ?? segment.end, segment.end)
            }
            guard let from = start, let to = end else { return nil }
            return (start: from, end: to)
        }
    }

    /// Seconds of video the buffer holds at `now`: from its first segment's start (finished or open)
    /// to `now`, 0 without a segment.
    func heldSeconds(now: Double) -> Double {
        return queue.sync {
            guard let first = segments.first else { return 0 }
            return max(0, now - first.start)
        }
    }

    /// Adds this display's video (and audio when asked) for `pieces` to `composition`.
    /// Returns the new video track with where its picture size changes in the clip (more than one
    /// size when the display went to native resolution during an area recording), or nil when nothing
    /// overlaps.
    func addTracks(to composition: AVMutableComposition, pieces: [ClipPiece], includeAudio: Bool) async throws -> (track: AVMutableCompositionTrack, sizes: [SegmentSizes.Span])? {
        guard let overallStart = pieces.map({ piece in piece.hostStart }).min(),
              let overallEnd = pieces.map({ piece in piece.hostEnd }).max() else { return nil }
        let usable: [Segment] = queue.sync {
            var list: [Segment] = []
            for segment in segments where segment.finished && segment.end > overallStart && segment.start < overallEnd {
                list.append(segment)
            }
            return list
        }
        guard let first = usable.first else { return nil }

        // 1. Lay segments on one timeline starting at the first segment.
        let timeline = AVMutableComposition()
        guard let timelineVideo = timeline.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        var timelineAudio: [AVMutableCompositionTrack] = []
        let base = first.start
        var lastEnd = base
        for segment in usable {
            let asset = AVURLAsset(url: segment.url)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let range = try await sourceVideo.load(.timeRange)
            let at = CMTime(seconds: max(segment.start - base, 0), preferredTimescale: 600)
            try timelineVideo.insertTimeRange(range, of: sourceVideo, at: at)
            lastEnd = max(lastEnd, segment.start + range.duration.seconds)
            if includeAudio {
                let sourceAudio = try await asset.loadTracks(withMediaType: .audio)
                for (index, audioTrack) in sourceAudio.enumerated() {
                    while timelineAudio.count <= index {
                        if let track = timeline.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                            timelineAudio.append(track)
                        } else {
                            break
                        }
                    }
                    if index >= timelineAudio.count { continue }
                    let audioRange = try await audioTrack.load(.timeRange)
                    let offset = max(0, audioRange.start.seconds - range.start.seconds)
                    let audioAt = CMTime(seconds: max(segment.start - base, 0) + offset, preferredTimescale: 48000)
                    try? timelineAudio[index].insertTimeRange(audioRange, of: audioTrack, at: audioAt)
                }
            }
        }

        // 2. Copy each piece into the shared composition at its output time.
        guard let outputVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        var outputAudio: [AVMutableCompositionTrack] = []
        for _ in timelineAudio {
            if let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                outputAudio.append(track)
            }
        }
        for piece in pieces {
            let clipStart = max(piece.hostStart, base)
            let clipEnd = min(piece.hostEnd, lastEnd)
            if clipEnd - clipStart < 0.02 { continue }
            let sourceRange = CMTimeRange(
                start: CMTime(seconds: clipStart - base, preferredTimescale: 600),
                end: CMTime(seconds: clipEnd - base, preferredTimescale: 600)
            )
            let at = CMTime(seconds: piece.outputStart + (clipStart - piece.hostStart), preferredTimescale: 600)
            try outputVideo.insertTimeRange(sourceRange, of: timelineVideo, at: at)
            for index in 0..<min(timelineAudio.count, outputAudio.count) {
                let audioTrack = timelineAudio[index]
                let audioRange = CMTimeRangeGetIntersection(sourceRange, otherRange: audioTrack.timeRange)
                if audioRange.duration.seconds <= 0 { continue }
                let audioAt = CMTime(seconds: at.seconds + (audioRange.start.seconds - sourceRange.start.seconds), preferredTimescale: 48000)
                try? outputAudio[index].insertTimeRange(audioRange, of: audioTrack, at: audioAt)
            }
        }
        var sizedSegments: [SegmentSizes.Segment] = []
        for segment in usable {
            sizedSegments.append(SegmentSizes.Segment(start: segment.start, end: min(segment.end, lastEnd), pixels: segment.size))
        }
        var sizedPieces: [SegmentSizes.Piece] = []
        for piece in pieces {
            sizedPieces.append(SegmentSizes.Piece(hostStart: piece.hostStart, hostEnd: piece.hostEnd, outputStart: piece.outputStart))
        }
        return (track: outputVideo, sizes: SegmentSizes.spans(segments: sizedSegments, pieces: sizedPieces))
    }

    static func retimed(_ sampleBuffer: CMSampleBuffer, to seconds: Double) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sampleBuffer, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
        return copy
    }

    /// Deletes all segment files, for example on launch.
    static func clearBufferFolder() {
        let folder = AppPaths.buffer
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
