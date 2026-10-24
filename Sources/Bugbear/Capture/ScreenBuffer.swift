import AVFoundation
import AppKit
import CoreMedia
import QuartzCore
import ScreenCaptureKit

struct BufferConfiguration: Equatable {
    var retentionSeconds: Double
    var framesPerSecond: Int
    var maxHeight: Int
    var showsCursor: Bool
    var systemAudio: Bool
    var microphone: Bool
}

enum BufferError: LocalizedError {
    case noDisplay
    case nothingRecorded
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display available for capture"
        case .nothingRecorded: return "The buffer has no frames for that range yet"
        case .exportFailed(let message): return "Export failed: \(message)"
        }
    }
}

/// A host-time range and where it starts in the exported clip.
struct ClipPiece {
    var hostStart: Double
    var hostEnd: Double
    var outputStart: Double
}

/// Keeps the last N minutes of one display on disk as short segments.
///
/// Frames (and optional audio) arrive on `queue`. Every `segmentLength` seconds the open
/// segment is finished and a new one starts, so a save only has to close the open segment
/// and stitch the recent files. Old segments are deleted as they leave the window.
final class ScreenBuffer: NSObject, SCStreamOutput, SCStreamDelegate {
    struct Segment {
        var url: URL
        var start: Double
        var end: Double
        var finished: Bool
    }

    enum AudioSource: Int {
        case system = 0
        case microphone = 1
    }

    let displayID: CGDirectDisplayID
    private let queue: DispatchQueue
    private let segmentLength: Double = 10
    private var stream: SCStream?
    /// The settings the stream runs with, kept to change the frame rate without a restart.
    private var streamSettings: SCStreamConfiguration?
    /// Start a new segment with the next frame (after a frame rate change). Queue only.
    private var startNewSegment = false
    private var configuration = BufferConfiguration(retentionSeconds: 180, framesPerSecond: 30, maxHeight: 1080, showsCursor: true, systemAudio: false, microphone: false)

    // Queue-confined state.
    private var segments: [Segment] = []
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInputs: [AudioSource: AVAssetWriterInput] = [:]
    private var currentSegmentIndex: Int?
    private var lastSampleBuffer: CMSampleBuffer?
    private var lastFrameTime: Double = 0
    private var outputSize = CGSize(width: 1920, height: 1080)
    private var pinnedFrom: Double?
    private var frameTimes: [Double] = []
    private var capturedDisplay: SCDisplay?
    private var excludedApplications: [SCRunningApplication] = []
    private var receivedFrames = 0
    /// Repeats the last frame while the screen is static (ScreenCaptureKit only sends
    /// frames on change), so the buffer timeline has no holes.
    private var heartbeat: DispatchSourceTimer?
    private var droppedFrames = 0

    /// Called on the main thread when the stream stops unexpectedly.
    var onStop: ((Error?) -> Void)?
    /// Global AppKit frame of the captured display (origin bottom-left).
    private(set) var displayFrame: CGRect = .zero

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.queue = DispatchQueue(label: "bugbear.buffer.\(displayID)", qos: .userInitiated)
    }

    static var hasScreenRecordingAccess: Bool {
        return CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingAccess() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: Start / stop

    func start(_ newConfiguration: BufferConfiguration, allowedWindowNumbers: [Int]) async throws {
        await stop()
        configuration = newConfiguration

        // All windows, not only on-screen ones: an app without visible windows is left out of
        // `applications`, and then our own windows (outline, HUD, editors) would not be excluded.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        var chosen: SCDisplay? = nil
        for display in content.displays where display.displayID == displayID {
            chosen = display
        }
        guard let display = chosen else {
            throw BufferError.noDisplay
        }

        // Leave our own windows (editors, menu panel, HUD) out of the recording,
        // except the drawing overlay and camera bubble.
        let excluded = ScreenBuffer.ownApplications(in: content)
        var allowed: [SCWindow] = []
        for window in content.windows where allowedWindowNumbers.contains(Int(window.windowID)) {
            allowed.append(window)
        }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: allowed)
        capturedDisplay = display
        excludedApplications = excluded

        let screenInfo = await MainActor.run { () -> (scale: CGFloat, frame: CGRect) in
            for screen in NSScreen.screens {
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                if number?.uint32Value == self.displayID {
                    return (scale: screen.backingScaleFactor, frame: screen.frame)
                }
            }
            return (scale: 2, frame: NSScreen.main?.frame ?? .zero)
        }
        displayFrame = screenInfo.frame

        var width = Double(display.width) * Double(screenInfo.scale)
        var height = Double(display.height) * Double(screenInfo.scale)
        if configuration.maxHeight > 0 && height > Double(configuration.maxHeight) {
            let ratio = Double(configuration.maxHeight) / height
            width *= ratio
            height *= ratio
        }
        // H.264 wants even dimensions.
        let evenWidth = Int(width / 2) * 2
        let evenHeight = Int(height / 2) * 2

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = evenWidth
        streamConfiguration.height = evenHeight
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.framesPerSecond))
        streamConfiguration.showsCursor = configuration.showsCursor
        // The H.264 encoder's own format: frames go to it without a colour conversion per frame,
        // which is most of the CPU a running buffer used to take.
        streamConfiguration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        streamConfiguration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        streamConfiguration.queueDepth = 6
        streamConfiguration.capturesAudio = configuration.systemAudio
        streamSettings = streamConfiguration
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = 48000
        streamConfiguration.channelCount = 2

        queue.sync {
            outputSize = CGSize(width: evenWidth, height: evenHeight)
        }

        let newStream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if configuration.systemAudio {
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        try await newStream.startCapture()
        stream = newStream
        startHeartbeat()
        Log.info("buffer[\(displayID)] started \(evenWidth)x\(evenHeight) @\(configuration.framesPerSecond)fps systemAudio=\(configuration.systemAudio) mic=\(configuration.microphone) allowed=\(allowed.count) excludedApps=\(excluded.count)")
    }

    func stop() async {
        if stream != nil {
            Log.info("buffer[\(displayID)] stopping")
        }
        stopHeartbeat()
        if let current = stream {
            try? await current.stopCapture()
        }
        stream = nil
        await finishCurrentSegment()
    }

    var isRunning: Bool {
        return stream != nil
    }

    var size: CGSize {
        return queue.sync { outputSize }
    }

    var excludesOwnApp: Bool {
        return !excludedApplications.isEmpty
    }

    /// Our own app as ScreenCaptureKit lists it. Right after launch it may not be listed yet, so the
    /// list is read again whenever the filter is updated.
    private static func ownApplications(in content: SCShareableContent) -> [SCRunningApplication] {
        var own: [SCRunningApplication] = []
        guard let ownBundleId = Bundle.main.bundleIdentifier else { return own }
        for app in content.applications where app.bundleIdentifier == ownBundleId {
            own.append(app)
        }
        return own
    }

    /// Changes the frame rate on the running stream, keeping what the buffer holds. The next frame
    /// starts a new segment, so the encoder's bitrate matches the new rate.
    func setFrameRate(_ framesPerSecond: Int) async {
        guard let current = stream, let settings = streamSettings else { return }
        settings.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        do {
            try await current.updateConfiguration(settings)
        } catch {
            Log.error("buffer[\(displayID)] frame rate change failed: \(error.localizedDescription)")
            return
        }
        queue.sync {
            configuration.framesPerSecond = framesPerSecond
            startNewSegment = true
        }
        Log.info("buffer[\(displayID)] now \(framesPerSecond) fps")
    }

    /// Leaves our own windows out of the capture again, and lets the listed ones (drawing overlay,
    /// camera bubble) in.
    func allowOwnWindows(_ windowNumbers: [Int]) async {
        guard let current = stream, let display = capturedDisplay else { return }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
        let own = ScreenBuffer.ownApplications(in: content)
        if own.count != excludedApplications.count {
            Log.info("buffer[\(displayID)] now excludes \(own.count) own app(s)")
        }
        excludedApplications = own
        var allowed: [SCWindow] = []
        for window in content.windows where windowNumbers.contains(Int(window.windowID)) {
            allowed.append(window)
        }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: allowed)
        try? await current.updateContentFilter(filter)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.error("buffer[\(displayID)] stream stopped: \(error.localizedDescription)")
        self.stream = nil
        stopHeartbeat()
        Task {
            await finishCurrentSegment()
            await MainActor.run {
                self.onStop?(error)
            }
        }
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
        appendVideo(sampleBuffer, at: time)
    }

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.repeatLastFrameIfIdle()
        }
        timer.resume()
        heartbeat = timer
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    /// Queue only.
    private func repeatLastFrameIfIdle() {
        let now = CACurrentMediaTime()
        guard let last = lastSampleBuffer, now - lastFrameTime >= 0.45 else { return }
        if let copy = ScreenBuffer.retimed(last, to: now) {
            appendVideo(copy, at: now)
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

    /// Appends one frame, rotating to a new segment when the current one is long enough. Queue only.
    private func appendVideo(_ sampleBuffer: CMSampleBuffer, at time: Double) {
        if time <= lastFrameTime { return }

        if let index = currentSegmentIndex, time - segments[index].start >= segmentLength || startNewSegment {
            startNewSegment = false
            finishSegmentOnQueue(completion: nil)
        }
        if writer == nil {
            openSegment(at: time)
        }
        guard let input = videoInput, let index = currentSegmentIndex else { return }
        if !input.isReadyForMoreMediaData {
            droppedFrames += 1
            if droppedFrames % 30 == 1 {
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
        pruneSegments(now: time)
    }

    private func openSegment(at time: Double) {
        let url = AppPaths.buffer.appendingPathComponent("segment-\(displayID)-\(UUID().uuidString).mov")
        guard let newWriter = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            Log.error("buffer[\(displayID)] cannot create writer")
            return
        }
        let fps = configuration.framesPerSecond
        let pixels = outputSize.width * outputSize.height
        let bitrate = min(20_000_000, max(2_000_000, pixels * Double(fps) * 0.12))
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
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
        segments.append(Segment(url: url, start: time, end: time, finished: false))
        currentSegmentIndex = segments.count - 1
    }

    /// Finishes the open segment. Queue only. Completion runs on the queue.
    private func finishSegmentOnQueue(completion: (() -> Void)?) {
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

        if segments[index].end <= segments[index].start {
            // Single frame: nothing playable, drop the file.
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
        // End the session one frame after the last frame so it has a duration.
        let frame = 1.0 / Double(configuration.framesPerSecond)
        currentWriter.endSession(atSourceTime: CMTime(seconds: segments[index].end + frame, preferredTimescale: 600))
        segments[index].end += frame
        currentWriter.finishWriting { [weak self] in
            guard let self = self else { return }
            self.queue.async {
                for position in 0..<self.segments.count where self.segments[position].url == url {
                    self.segments[position].finished = currentWriter.status == .completed
                }
                if currentWriter.status != .completed {
                    Log.error("buffer[\(self.displayID)] segment finish failed: \(currentWriter.error?.localizedDescription ?? "status \(currentWriter.status.rawValue)")")
                }
                completion?()
            }
        }
    }

    private func finishCurrentSegment() async {
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
            if segment.finished && segment.end < keepFrom {
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

    /// Closes the open segment so everything up to now is in finished files.
    /// Repeats the last frame at "now" so a static screen still reaches the end.
    func prepareForExport() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                let now = CACurrentMediaTime()
                if let last = self.lastSampleBuffer, now - self.lastFrameTime > 0.1, self.writer != nil {
                    if let copy = ScreenBuffer.retimed(last, to: now) {
                        self.appendVideo(copy, at: now)
                    }
                }
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
                parts.append(String(format: "[%.2f…%.2f %@]", segment.start - now, segment.end - now, segment.finished ? "done" : "open"))
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

    /// Adds this display's video (and audio when asked) for `pieces` to `composition`.
    /// Returns the new video track, or nil when nothing overlaps.
    func addTracks(to composition: AVMutableComposition, pieces: [ClipPiece], includeAudio: Bool) async throws -> AVMutableCompositionTrack? {
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
        return outputVideo
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
