import AVFoundation
import AppCore
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
        case .noDisplay: return L("capture.error.noDisplay")
        case .nothingRecorded: return L("capture.error.nothingRecorded")
        case .exportFailed(let message): return L("capture.error.exportFailed", message)
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
        var state: SegmentState
        /// Playable and closed. A failed segment is not.
        var finished: Bool { state == .finished }
        /// The picture size in pixels. A segment has one size: a display that goes to native
        /// resolution while recording starts a new one.
        var size: CGSize
    }

    enum AudioSource: Int {
        case system = 0
        case microphone = 1
    }

    /// What the menu shows about the buffer, as the queue last saw it.
    struct PublishedStatus {
        var firstSegmentStart: Double?
        var retentionSeconds: Double = 0
        var activity = [Double](repeating: 0, count: ScreenBuffer.activityBuckets)
    }

    /// The bars of the activity strip in the menu.
    static let activityBuckets = 16

    let displayID: CGDirectDisplayID
    let queue: DispatchQueue
    let segmentLength: Double = 10
    /// Guards the fields marked "Locked": the stream's delegate, `start` and `stop` (thread pool) and
    /// the main thread all touch them. Held for a few lines that wait for nothing, never across an
    /// `await` or a `queue.sync`, so the queue may take it too.
    let lock = NSLock()
    /// Locked.
    private var stream: SCStream?
    /// The settings the stream runs with, kept to change the frame rate without a restart. Locked.
    private var streamSettings: SCStreamConfiguration?
    /// Start a new segment with the next frame (after a frame rate or size change). Queue only.
    var startNewSegment = false
    /// Queue only.
    var configuration = BufferConfiguration(retentionSeconds: 180, framesPerSecond: 30, maxHeight: 1080, showsCursor: true, systemAudio: false, microphone: false)

    // Queue-confined state.
    var segments: [Segment] = []
    var writer: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var audioInputs: [AudioSource: AVAssetWriterInput] = [:]
    var currentSegmentIndex: Int?
    var lastSampleBuffer: CMSampleBuffer?
    var lastFrameTime: Double = 0
    var outputSize = CGSize(width: 1920, height: 1080)
    var pinnedFrom: Double?
    var frameTimes: [Double] = []
    /// When old segments were last looked at (`pruneSegments`).
    var lastPrune: Double = 0
    /// Locked.
    private var capturedDisplay: SCDisplay?
    /// The display's full pixel size (even), what `upgradeToNative` goes to. Locked.
    private var nativeSize: CGSize = .zero
    /// Counts `stop()` calls. A start that sees it change while it waits was stopped meanwhile and
    /// must not keep the stream it made. Locked.
    private var stopCount = 0
    /// Locked.
    private var excludedApplications: [SCRunningApplication] = []
    var receivedFrames = 0
    /// Repeats the last frame while the screen is static (ScreenCaptureKit only sends
    /// frames on change), so the buffer timeline has no holes. Locked.
    var heartbeat: DispatchSourceTimer?
    var droppedFrames = 0
    /// Frames the open segment's writer refused. Queue only.
    var failedAppends = 0
    /// The queue writes it (`publishStatus`), so the main thread reads the status without waiting
    /// for the queue. Locked.
    var publishedStatus = PublishedStatus()

    /// Called on the main thread when the stream stops unexpectedly.
    var onStop: ((Error?) -> Void)?
    /// Called on the main thread when the disk is almost full while a recording keeps every segment.
    var onDiskAlmostFull: (() -> Void)?
    /// The app was told about the disk; once per recording. Queue only.
    var toldDiskAlmostFull = false
    /// Global AppKit frame of the captured display (origin bottom-left).
    var displayFrame: CGRect {
        return lock.withLock { lockedDisplayFrame }
    }
    private var lockedDisplayFrame: CGRect = .zero
    /// Height of the menu bar on this display, 0 when it hides itself. Queue only.
    var menuBarHeight: CGFloat = 0
    /// While recording, frames that changed only in the menu bar or under the recording bar are
    /// encoded a few times a second (see `FramePacing`). Queue only.
    var pacer = FramePacer()
    /// The newest frame `pacer` held back. Queue only.
    var heldSample: CMSampleBuffer?
    /// Inputs of the quiet zones, kept so the zones follow the current output size. Queue only.
    var busyWindows: [CGRect] = []
    var quietZonesEnabled = false
    var ownWindows: [CGRect] = []

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.queue = DispatchQueue(label: "app.buffer.\(displayID)", qos: .userInitiated)
    }

    #if AUTOMATION
    /// e2e (screen-access:missing): the access check says no, to show what a Mac without it shows.
    static var pretendNoAccess = false
    /// Self-test: the free space the buffer sees instead of the disk's. Queue only.
    var freeBytesForTests: Int64?
    #endif

    static var hasScreenRecordingAccess: Bool {
        #if AUTOMATION
        if pretendNoAccess {
            return false
        }
        #endif
        return CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingAccess() {
        CGRequestScreenCaptureAccess()
        // macOS lists an app under Screen & System Audio Recording only once it tries to capture.
        // On a new install nothing has tried yet (the buffer waits for the welcome guide), so the
        // person found no entry for the app to switch on: asking for the screens puts it on the list.
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    }

    // MARK: Start / stop

    func start(_ newConfiguration: BufferConfiguration, allowedWindowNumbers: [Int]) async throws {
        await stop()
        let startedAfterStop = lock.withLock { stopCount }
        queue.sync {
            configuration = newConfiguration
        }

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
        lock.withLock {
            capturedDisplay = display
            excludedApplications = excluded
        }

        let screenInfo = await MainActor.run { () -> (scale: CGFloat, frame: CGRect, menuBar: CGFloat) in
            for screen in NSScreen.screens {
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                if number?.uint32Value == self.displayID {
                    return (scale: screen.backingScaleFactor, frame: screen.frame, menuBar: screen.frame.maxY - screen.visibleFrame.maxY)
                }
            }
            return (scale: 2, frame: NSScreen.main?.frame ?? .zero, menuBar: 0)
        }

        var width = Double(display.width) * Double(screenInfo.scale)
        var height = Double(display.height) * Double(screenInfo.scale)
        let native = CGSize(width: Int(width / 2) * 2, height: Int(height / 2) * 2)
        if newConfiguration.maxHeight > 0 && height > Double(newConfiguration.maxHeight) {
            let ratio = Double(newConfiguration.maxHeight) / height
            width *= ratio
            height *= ratio
        }
        // H.264 wants even dimensions.
        let evenWidth = Int(width / 2) * 2
        let evenHeight = Int(height / 2) * 2

        let streamConfiguration = ScreenBuffer.streamConfiguration(width: evenWidth, height: evenHeight, framesPerSecond: newConfiguration.framesPerSecond, configuration: newConfiguration)
        lock.withLock {
            lockedDisplayFrame = screenInfo.frame
            nativeSize = native
            streamSettings = streamConfiguration
        }

        queue.sync {
            outputSize = CGSize(width: evenWidth, height: evenHeight)
            menuBarHeight = max(0, screenInfo.menuBar)
        }

        let newStream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if newConfiguration.systemAudio {
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        try await newStream.startCapture()
        // Stopped while this start waited (the buffer was replaced): the new capture belongs to no one.
        // Checked and kept in one step, so a stop cannot come in between and miss the stream.
        let kept = lock.withLock { () -> Bool in
            if stopCount != startedAfterStop { return false }
            stream = newStream
            startHeartbeatLocked()
            return true
        }
        if !kept {
            try? await newStream.stopCapture()
            Log.info("buffer[\(displayID)] stopped while starting, capture ended")
            throw CancellationError()
        }
        Log.info("buffer[\(displayID)] started \(evenWidth)x\(evenHeight) @\(newConfiguration.framesPerSecond)fps systemAudio=\(newConfiguration.systemAudio) mic=\(newConfiguration.microphone) allowed=\(allowed.count) excludedApps=\(excluded.count)")
    }

    /// What the stream runs with. A new object every time: a change is tried on a copy, and the kept
    /// settings change only once the stream took it.
    static func streamConfiguration(width: Int, height: Int, framesPerSecond: Int, configuration: BufferConfiguration) -> SCStreamConfiguration {
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = width
        streamConfiguration.height = height
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        streamConfiguration.showsCursor = configuration.showsCursor
        // The H.264 encoder's own format: frames go to it without a colour conversion per frame,
        // which is most of the CPU a running buffer used to take.
        streamConfiguration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        streamConfiguration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        streamConfiguration.queueDepth = 4
        streamConfiguration.capturesAudio = configuration.systemAudio
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = 48000
        streamConfiguration.channelCount = 2
        return streamConfiguration
    }

    func stop() async {
        // Taken before waiting for the capture to end, so a change on its way (upgradeToNative)
        // sees the stream is going and does not start it again.
        if let current = releaseStream() {
            Log.info("buffer[\(displayID)] stopping")
            try? await current.stopCapture()
        }
        dropHeldFrame()
        await finishCurrentSegment()
    }

    /// On quit: only ends the capture, so macOS takes its indicator down. The segment is not
    /// finished, the buffer folder is deleted right after anyway.
    func stopCaptureForQuit() async {
        if let current = releaseStream() {
            try? await current.stopCapture()
            Log.info("buffer[\(displayID)] capture stopped for quit")
        }
    }

    /// Lets go of the stream and its heartbeat in one step: a stop from here and one from the
    /// stream's delegate (the lid closed) come at once, and only one of them gets the stream to end.
    private func releaseStream() -> SCStream? {
        return lock.withLock {
            stopCount += 1
            stopHeartbeatLocked()
            let current = stream
            stream = nil
            return current
        }
    }

    var isRunning: Bool {
        return lock.withLock { stream != nil }
    }

    var size: CGSize {
        return queue.sync { outputSize }
    }

    var excludesOwnApp: Bool {
        return lock.withLock { !excludedApplications.isEmpty }
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
        let running = lock.withLock { (stream: stream, settings: streamSettings) }
        guard let current = running.stream, let settings = running.settings else { return }
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

    /// Native resolution and at least `framesPerSecond` on the running stream, for a recorded area that
    /// now touches this display. What the buffer holds stays; the first frame at the new size starts a
    /// new segment. False when the stream did not take the change: the caller restarts this display on
    /// the buffer's start chain (a restart from here could outlive a stop and leave a capture no one owns).
    func upgradeToNative(framesPerSecond: Int) async -> Bool {
        let running = lock.withLock { (stream: stream, nativeSize: nativeSize) }
        guard let current = running.stream else { return true }
        let state = queue.sync { (size: outputSize, framesPerSecond: configuration.framesPerSecond, configuration: configuration) }
        let target = running.nativeSize
        let rate = max(framesPerSecond, state.framesPerSecond)
        if target.width <= 0 || (state.size == target && state.framesPerSecond == rate) { return true }
        let settings = ScreenBuffer.streamConfiguration(width: Int(target.width), height: Int(target.height), framesPerSecond: rate, configuration: state.configuration)
        // Native frames can arrive before the change returns: the segment they open needs the new rate.
        queue.sync {
            configuration.framesPerSecond = rate
        }
        do {
            try await current.updateConfiguration(settings)
        } catch {
            queue.sync {
                configuration.framesPerSecond = state.framesPerSecond
            }
            // Stopped meanwhile (the recording ended and the buffer restarts): nothing to change.
            if lock.withLock({ stream !== current }) { return true }
            Log.error("buffer[\(displayID)] native resolution change failed: \(error.localizedDescription)")
            return false
        }
        lock.withLock {
            if stream === current {
                streamSettings = settings
            }
        }
        queue.sync {
            applyNativeSize(target, framesPerSecond: rate)
        }
        Log.info("buffer[\(displayID)] now native \(Int(target.width))x\(Int(target.height)) @\(rate)fps")
        return true
    }

    /// The stream now sends `size` frames at `framesPerSecond`. A size change starts its new segment by
    /// itself with the first frame of that size (`appendVideo`); a segment break asked for here as well
    /// would close a segment holding one frame still on its way at the old size, and that frame would be
    /// lost. Only a frame rate change alone asks for a break. Queue only.
    func applyNativeSize(_ size: CGSize, framesPerSecond: Int) {
        if size == outputSize {
            startNewSegment = true
        }
        outputSize = size
        configuration.maxHeight = 0
        configuration.framesPerSecond = framesPerSecond
        updatePacerZones()
    }

    /// Leaves our own windows out of the capture again, and lets the listed ones (drawing overlay,
    /// camera bubble) in.
    func allowOwnWindows(_ windowNumbers: [Int]) async {
        let running = lock.withLock { (stream: stream, display: capturedDisplay) }
        guard let current = running.stream, let display = running.display else { return }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
        let own = ScreenBuffer.ownApplications(in: content)
        let excludedBefore = lock.withLock { () -> Int in
            let count = excludedApplications.count
            excludedApplications = own
            return count
        }
        if own.count != excludedBefore {
            Log.info("buffer[\(displayID)] now excludes \(own.count) own app(s)")
        }
        var allowed: [SCWindow] = []
        for window in content.windows where windowNumbers.contains(Int(window.windowID)) {
            allowed.append(window)
        }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: allowed)
        try? await current.updateContentFilter(filter)
    }

    #if AUTOMATION
    /// Self-test: a buffer fed made-up frames has no display of its own.
    func setDisplayFrameForTests(_ frame: CGRect) {
        lock.withLock { lockedDisplayFrame = frame }
    }
    #endif

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.error("buffer[\(displayID)] stream stopped: \(error.localizedDescription)")
        // Only the stream this buffer still runs. One that `stop()` already took is being ended
        // there, and a late word about a stream that was replaced must not drop the new one.
        let wasRunning = lock.withLock { () -> Bool in
            if self.stream !== stream { return false }
            self.stream = nil
            stopHeartbeatLocked()
            return true
        }
        if !wasRunning { return }
        dropHeldFrame()
        Task {
            await finishCurrentSegment()
            await MainActor.run {
                self.onStop?(error)
            }
        }
    }
}
