import AppKit
import Observation
import BugbearCore
import QuartzCore

enum RecordingTarget: String, CaseIterable, Identifiable {
    case screens
    case area

    var id: String { rawValue }
}

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    enum BufferState: Equatable {
        case off
        case starting
        case running
        case paused
        case needsPermission
        case failed(String)
    }

    let settings = AppSettings.shared
    let store = CaptureStore.shared
    let overlay = LiveOverlay()

    var bufferState: BufferState = .off
    var coveredSeconds: Double = 0
    var activity: [Double] = Array(repeating: 0, count: 16)
    var recording: RecordingSession?
    var recordingTarget: RecordingTarget = .screens
    var isSaving = false
    var statusMessage: String?
    var environmentPreview: EnvironmentSnapshot?
    var hasAccessibilityAccess = InputEventRecorder.hasAccessibilityAccess
    var cameraOn = false
    /// Text next to the menu bar icon; updated once a second by the status timer.
    var menuBarText = ""
    var displayCount = NSScreen.screens.count

    @ObservationIgnored private(set) var buffers: [ScreenBuffer] = []
    @ObservationIgnored let inputRecorder = InputEventRecorder()
    @ObservationIgnored let crashWatcher = CrashWatcher()
    @ObservationIgnored let recordingOutline = RecordingOutline()
    @ObservationIgnored let microphone = MicrophoneSource()
    @ObservationIgnored let camera = CameraBubble()
    @ObservationIgnored let regionSelector = RegionSelector()
    @ObservationIgnored private let hud = RecordingHUDController()
    @ObservationIgnored private var statusTimer: Timer?
    @ObservationIgnored private(set) var lastExternalApp: NSRunningApplication? {
        didSet {
            let name = lastExternalApp?.localizedName ?? ""
            if name != lastExternalAppName {
                lastExternalAppName = name
            }
        }
    }
    /// For the menu: which app "the window you test" is.
    private(set) var lastExternalAppName = ""
    @ObservationIgnored private var launched = false
    @ObservationIgnored private(set) var recordingRegion: RegionSelector.Selection?
    /// While an area is recorded the buffer runs at the display's full resolution, so a "720p" area
    /// really comes out 1280×720 instead of a crop of the downscaled buffer.
    @ObservationIgnored private var nativeResolutionForArea = false
    /// The one display a recording keeps: the area's, or the one under the pointer when "Record all
    /// displays" is off. Nil records every buffered display side by side.
    @ObservationIgnored private var recordingDisplay: CGDirectDisplayID?
    /// A display the buffer does not normally capture, added for the length of one recording.
    @ObservationIgnored private var extraDisplayForRecording: CGDirectDisplayID?

    private init() {}

    var primaryBuffer: ScreenBuffer? {
        return buffers.first
    }

    // MARK: Launch

    func launch() {
        if launched { return }
        launched = true
        ScreenBuffer.clearBufferFolder()

        let workspace = NSWorkspace.shared
        if let front = workspace.frontmostApplication, AppState.isTestedApp(front) {
            lastExternalApp = front
        }
        workspace.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app = app, AppState.isTestedApp(app) {
                    AppState.shared.lastExternalApp = app
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                AppState.shared.screensChanged()
            }
        }

        overlay.onVisibilityChange = { [weak self] _ in
            self?.updateAllowedWindows()
        }
        camera.onVisibilityChange = { [weak self] _ in
            self?.updateAllowedWindows()
        }
        camera.size = CGFloat(settings.cameraBubbleSize)
        microphone.onSample = { [weak self] sample in
            // Microphone audio is written into the primary display's segments.
            self?.micSink?.receiveMicrophone(sample)
        }

        registerHotKeys()
        Automation.install()
        Updater.shared.start()
        startStorageCleanUp()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                AppState.shared.refreshStatus()
            }
        }

        let isFirstLaunch = !UserDefaults.standard.bool(forKey: OnboardingView.completedKey)
        if isFirstLaunch {
            WhatsNewTracker.markAllSeen()
        } else if !Automation.isEnabled {
            WhatsNewTracker.checkOnLaunch()
        }
        if isFirstLaunch && !Automation.isEnabled {
            // First launch: the guide asks for permissions before the buffer starts.
            bufferState = ScreenBuffer.hasScreenRecordingAccess ? .paused : .needsPermission
            WindowManager.shared.openOnboarding()
        } else if settings.startBufferOnLaunch {
            Task { await startBuffer() }
        } else {
            bufferState = ScreenBuffer.hasScreenRecordingAccess ? .paused : .needsPermission
        }
    }

    /// System prompts (password, keychain, permission dialogs) take focus but are not the app under test.
    nonisolated static let systemAgents: Set<String> = [
        "com.apple.SecurityAgent", "com.apple.UserNotificationCenter", "com.apple.loginwindow",
        "com.apple.coreautha", "com.apple.CoreServicesUIAgent", "com.apple.universalAccessAuthWarn",
        "com.apple.screencaptureui", "com.apple.dock", "com.apple.notificationcenterui",
    ]

    nonisolated static func isTestedApp(_ app: NSRunningApplication) -> Bool {
        guard let bundleId = app.bundleIdentifier else { return false }
        if bundleId == Bundle.main.bundleIdentifier { return false }
        return !systemAgents.contains(bundleId)
    }

    /// Thread-safe reference for the microphone callback.
    @ObservationIgnored nonisolated(unsafe) private var micSink: ScreenBuffer?

    /// Registers the shortcuts from Settings (defaults: ⌥⇧ + key). Called again whenever they change.
    func registerHotKeys() {
        var bindings: [HotKeyCenter.Binding] = []
        for action in HotKeyAction.allCases {
            guard let shortcut = HotKeySettings.shared.shortcut(for: action) else { continue }
            bindings.append(HotKeyCenter.Binding(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, display: shortcut.display) {
                action.perform()
            })
        }
        HotKeyCenter.shared.register(bindings)
    }

    func refreshStatus() {
        var text = ""
        if let session = recording {
            let clock = TimeFormat.clock(session.elapsed())
            text = session.isPaused ? "❚❚ \(clock)" : "REC \(clock)"
        } else if bufferState == .running {
            text = TimeFormat.clock(settings.bufferSeconds)
        }
        if text != menuBarText {
            menuBarText = text
        }
        let accessibility = InputEventRecorder.hasAccessibilityAccess
        if accessibility != hasAccessibilityAccess {
            hasAccessibilityAccess = accessibility
        }
        guard let primary = primaryBuffer, primary.isRunning else {
            coveredSeconds = 0
            return
        }
        let status = primary.status(buckets: 16)
        if Int(status.covered) != Int(coveredSeconds) {
            coveredSeconds = status.covered
        }
        if status.activity != activity {
            activity = status.activity
        }
    }

    @ObservationIgnored private var screenSignature = AppState.currentScreenSignature()

    /// Display IDs and frames. The Dock appearing (when an editor opens) also posts a
    /// screen-parameters notification; only a real display change should restart capture.
    static func currentScreenSignature() -> String {
        var parts: [String] = []
        for screen in NSScreen.screens {
            parts.append("\(AppState.displayID(of: screen)):\(Int(screen.frame.minX)),\(Int(screen.frame.minY)),\(Int(screen.frame.width))x\(Int(screen.frame.height))@\(screen.backingScaleFactor)")
        }
        return parts.sorted().joined(separator: "|")
    }

    private func screensChanged() {
        displayCount = NSScreen.screens.count
        let signature = AppState.currentScreenSignature()
        if signature == screenSignature { return }
        Log.info("displays changed: \(signature)")
        screenSignature = signature
        if bufferState == .running && recording == nil {
            Task { await restartBufferIfRunning() }
        }
    }

    // MARK: Buffer

    var bufferConfiguration: BufferConfiguration {
        return BufferConfiguration(
            retentionSeconds: settings.bufferSeconds,
            framesPerSecond: settings.framesPerSecond,
            maxHeight: nativeResolutionForArea ? 0 : settings.maxHeight,
            showsCursor: settings.showsCursor,
            systemAudio: settings.recordSystemAudio,
            microphone: settings.recordMicrophone
        )
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value ?? CGMainDisplayID()
    }

    /// Main display first, then the others when "all displays" is on.
    private func displaysToCapture() -> [CGDirectDisplayID] {
        var ids: [CGDirectDisplayID] = [CGMainDisplayID()]
        if settings.captureAllDisplays {
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

    private func updateAllowedWindows() {
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
    private func refreshBufferFilters() async {
        let numbers = allowedWindowNumbers
        for buffer in buffers {
            await buffer.allowOwnWindows(numbers)
        }
    }

    func startBuffer() async {
        if !ScreenBuffer.hasScreenRecordingAccess {
            bufferState = .needsPermission
            return
        }
        bufferState = .starting
        for buffer in buffers {
            await buffer.stop()
        }
        buffers = []
        let configuration = bufferConfiguration
        do {
            for (index, displayID) in displaysToCapture().enumerated() {
                let buffer = ScreenBuffer(displayID: displayID)
                var displayConfiguration = configuration
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
                    statusMessage = "Microphone access was denied; recording without it."
                }
            } else {
                microphone.stop()
            }
            inputRecorder.start(clicks: settings.recordClicks, keys: settings.recordKeys && InputEventRecorder.hasAccessibilityAccess, retentionSeconds: settings.bufferSeconds)
            bufferState = .running
            updateCrashWatcher()
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
            bufferState = .failed(error.localizedDescription)
        }
        refreshStatus()
    }

    private func bufferStopped(_ error: Error?) {
        if bufferState != .running { return }
        bufferState = .failed(error?.localizedDescription ?? "Capture stopped")
        // Display changes stop the stream; try again shortly.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if recording == nil {
                await startBuffer()
            }
        }
    }

    func pauseBuffer() async {
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
    }

    func toggleBuffer() async {
        if bufferState == .running {
            await pauseBuffer()
        } else {
            await startBuffer()
        }
    }

    /// Applies new settings by restarting a running buffer (drops what was recorded).
    func restartBufferIfRunning() async {
        if bufferState == .running && recording == nil {
            await startBuffer()
        }
    }

    func requestScreenRecordingAccess() {
        ScreenBuffer.requestScreenRecordingAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestAccessibilityAccess() {
        InputEventRecorder.requestAccessibilityAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Saving clips

    /// ⌥⇧M: remembers "the bug is here". The next save reaches back to include it.
    func markMoment() {
        if bufferState != .running {
            showError("The buffer is not recording. Start it from the menu bar first.")
            return
        }
        inputRecorder.mark()
        Log.info("marker added")
        Toast.shared.show("Moment marked. Save the clip when you're ready.", symbol: "flag.fill")
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
            showError("The buffer is not recording. Start it from the menu bar first.")
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
    private func saveClip(from source: [ScreenBuffer], ranges: [(start: Double, end: Double)], app: NSRunningApplication?) async throws -> Capture {
        guard let main = source.first else { throw BufferError.noDisplay }
        let environment = await EnvironmentCollector.snapshot(for: app, readURL: settings.readBrowserURL)
        if source.count == 1 {
            let clip = try await ClipComposer.export(buffers: source, ranges: ranges, region: nil, framesPerSecond: settings.framesPerSecond)
            Log.info("clip exported: \(clip.duration)s → \(clip.url.lastPathComponent)")
            let capture = try store.add(kind: .video, mediaFile: clip.url, environment: environment, events: inputRecorder.events(for: clip), duration: clip.duration)
            attachSystemLog(to: capture, clip: clip, app: app)
            return capture
        }

        let ordered = source.sorted { first, second in first.displayFrame.minX < second.displayFrame.minX }
        var clips: [ClipExport] = []
        var variants: [ScreenVariant] = []
        for buffer in ordered {
            let clip = try await ClipComposer.export(buffers: [buffer], ranges: ranges, region: nil, framesPerSecond: settings.framesPerSecond, audioFrom: main)
            clips.append(clip)
            variants.append(ScreenVariant(id: "display-\(buffer.displayID)", name: AppState.screenName(buffer.displayID), file: "screen-\(buffer.displayID).mp4", events: inputRecorder.events(for: clip), isMain: buffer === main))
        }
        // Clicks for the side-by-side picture, which is built only if someone picks it.
        let sideBySide = ClipExport(url: clips[0].url, pieces: clips[0].pieces, duration: clips[0].duration, layout: ClipComposer.sideBySideLayout(source))
        variants.append(ScreenVariant(id: ScreenVariant.allID, name: "Side by side", file: "screen-all.mp4", events: inputRecorder.events(for: sideBySide), isMain: false))

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
                return "Built-in"
            }
            return screen.localizedName
        }
        return "Display \(wanted)"
    }

    // MARK: Storage

    @ObservationIgnored private var cleanUpTimer: Timer?

    /// Settings → Storage limits, applied shortly after launch and then once a day.
    private func startStorageCleanUp() {
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await cleanUpStorage()
        }
        cleanUpTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in
                await AppState.shared.cleanUpStorage()
            }
        }
    }

    @discardableResult
    func cleanUpStorage() async -> Int {
        return await store.cleanUp(maxAgeDays: settings.keepCapturesDays, maxGB: settings.maxCapturesGB)
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
            Toast.shared.show("\(report.appName) crashed. The minute before is saved in Recent.", symbol: "exclamationmark.triangle.fill", seconds: 5)
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
        }
    }

    private func finishClip(_ clip: ClipExport, app: NSRunningApplication?) async {
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
        if recording != nil { return }
        closeMenuPanel()
        recordingRegion = presetRegion
        if target == .area && presetRegion == nil {
            let screen = NSScreen.screens.first { screen in screen.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            guard let chosen = screen, let selection = await regionSelector.pick(on: chosen, initial: nil) else { return }
            recordingRegion = selection
        }
        // Which display to keep: the area's, or the one under the pointer when only one is wanted.
        recordingDisplay = nil
        if let region = recordingRegion {
            recordingDisplay = AppState.displayID(of: region.screen)
        } else if !settings.captureAllDisplays, let screen = NSScreen.screens.first(where: { screen in screen.frame.contains(NSEvent.mouseLocation) }) {
            recordingDisplay = AppState.displayID(of: screen)
        }
        var restart = bufferState != .running
        if let display = recordingDisplay, !buffers.contains(where: { buffer in buffer.displayID == display }) {
            extraDisplayForRecording = display
            restart = true
            Log.info("recording: adding display \(display) to the buffer")
        }
        if recordingRegion != nil && settings.maxHeight > 0 {
            nativeResolutionForArea = true
            restart = true
            Log.info("area recording: buffer at native resolution")
        }
        if restart {
            await startBuffer()
        }
        if bufferState != .running {
            await restoreBufferResolution()
            showError("Screen recording is not available. Grant Screen Recording access and try again.")
            return
        }
        await refreshBufferFilters()
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
        recordingOutline.show(region: recordingRegion, recordedDisplays: recordedDisplays)
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
        recordingDisplay = nil
        do {
            if region == nil {
                let capture = try await saveClip(from: exportBuffers, ranges: ranges, app: app)
                WindowManager.shared.openEditor(for: capture)
            } else {
                let clip = try await ClipComposer.export(buffers: exportBuffers, ranges: ranges, region: region?.normalized, framesPerSecond: settings.framesPerSecond)
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
        for buffer in buffers {
            buffer.pin(from: nil)
        }
        Task { await restoreBufferResolution() }
    }

    /// Back to the displays and resolution from Settings after a recording that changed them.
    private func restoreBufferResolution() async {
        if !nativeResolutionForArea && extraDisplayForRecording == nil { return }
        nativeResolutionForArea = false
        extraDisplayForRecording = nil
        if recording == nil && bufferState == .running {
            await startBuffer()
            Log.info("recording done: buffer back to \(settings.qualityLabel)")
        }
    }

    // MARK: Drawing on screen and camera

    func toggleDrawing() {
        if !overlay.isVisible {
            let screen = NSScreen.screens.first { screen in screen.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            overlay.show(on: screen?.frame ?? .zero)
            hud.show(app: self)
        }
        overlay.isDrawing.toggle()
        DispatchQueue.main.async {
            self.hud.resize()
        }
    }

    func hideOverlay() {
        overlay.hide()
        if recording == nil {
            hud.hide()
        }
    }

    func setCamera(_ on: Bool) async {
        if on {
            let screen = NSScreen.screens.first { screen in screen.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let shown = await camera.show(on: screen)
            cameraOn = shown
            if !shown {
                showError("Camera is not available. Allow camera access for Bugbear in System Settings › Privacy & Security › Camera.")
            }
        } else {
            camera.hide()
            cameraOn = false
        }
    }

    // MARK: Screenshots

    func takeScreenshot(_ mode: ScreenshotMode) async {
        closeMenuPanel()
        let app = lastExternalApp
        try? await Task.sleep(nanoseconds: 250_000_000)
        let recentEvents = inputRecorder.recentEvents(seconds: 60)
        if (mode == .fullScreen || mode == .allDisplays) && NSScreen.screens.count > 1 {
            await takeScreenshotOfEachDisplay(showAll: mode == .allDisplays, app: app, events: recentEvents)
            return
        }
        guard let file = await ScreenshotCapture.capture(mode) else { return }
        let environment = await EnvironmentCollector.snapshot(for: app, readURL: settings.readBrowserURL)
        do {
            let capture = try store.add(kind: .screenshot, mediaFile: file, environment: environment, events: recentEvents)
            WindowManager.shared.openEditor(for: capture)
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Several displays: every display as its own picture plus all of them side by side, like clips.
    /// The editor opens on the display under the pointer, or on all of them for "All displays".
    private func takeScreenshotOfEachDisplay(showAll: Bool, app: NSRunningApplication?, events: [InputEvent]) async {
        let displays = await ScreenshotCapture.captureEachDisplay()
        guard displays.count > 1 else {
            for display in displays {
                try? FileManager.default.removeItem(at: display.url)
            }
            showError("Could not take a screenshot of the displays.")
            return
        }
        var images: [CGImage] = []
        for display in displays {
            if let image = ImageFiles.load(display.url) {
                images.append(image)
            }
        }
        let sideBySide = AppPaths.temporary.appendingPathComponent("all-\(UUID().uuidString).png")
        if let stitched = ScreenshotCapture.stitchHorizontally(images) {
            ImageFiles.write(stitched, to: sideBySide, type: "public.png")
        }
        var files: [URL] = []
        var variants: [ScreenVariant] = []
        for display in displays {
            files.append(display.url)
            variants.append(ScreenVariant(id: "display-\(display.displayID)", name: AppState.screenName(display.displayID), file: "screen-\(display.displayID).png", events: events, isMain: display.displayID == CGMainDisplayID()))
        }
        files.append(sideBySide)
        variants.append(ScreenVariant(id: ScreenVariant.allID, name: "Side by side", file: "screen-all.png", events: events, isMain: false))

        var chosen = variants.count - 1
        if !showAll {
            let mouse = NSEvent.mouseLocation
            for (index, display) in displays.enumerated() where display.frame.contains(mouse) {
                chosen = index
            }
        }
        let environment = await EnvironmentCollector.snapshot(for: app, readURL: settings.readBrowserURL)
        do {
            var capture = try store.add(kind: .screenshot, mediaFile: files[chosen], environment: environment, events: events)
            for (index, file) in files.enumerated() {
                let target = capture.folder.appendingPathComponent(variants[index].file)
                if index == chosen {
                    try FileManager.default.linkItem(at: capture.mediaURL, to: target)
                } else {
                    try FileManager.default.moveItem(at: file, to: target)
                }
            }
            capture.screens = variants
            capture.selectedScreen = variants[chosen].id
            try store.replace(capture)
            WindowManager.shared.openEditor(for: capture)
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// ⌥⇧O: select an area, its text goes to the clipboard. Nothing is added to history.
    func copyTextFromScreen() async {
        closeMenuPanel()
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard let file = await ScreenshotCapture.capture(.area) else { return }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let image = ImageFiles.load(file) else { return }
        // A QR code in the area: its link is more useful than the text around it.
        let codes = await QRCode.read(image)
        if !codes.isEmpty {
            let payload = codes.joined(separator: "\n")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(payload, forType: .string)
            var preview = payload
            if preview.count > 40 {
                preview = String(preview.prefix(40)) + "…"
            }
            Toast.shared.show("Copied QR: \(preview)", symbol: "qrcode")
            return
        }
        do {
            let lines = try await TextRecognizer.recognize(image)
            let text = TextRecognizer.text(of: lines)
            if text.isEmpty {
                Toast.shared.show("No text found in that area", symbol: "text.viewfinder")
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            var preview = text.replacingOccurrences(of: "\n", with: " ")
            if preview.count > 40 {
                preview = String(preview.prefix(40)) + "…"
            }
            Log.info("copied \(text.count) characters of recognized text")
            Toast.shared.show("Copied: \(preview)", symbol: "doc.on.clipboard")
        } catch {
            showError("Text recognition failed: \(error.localizedDescription)")
        }
    }

    // MARK: Scrolling screenshot

    /// Pick an area, then the app scrolls it and glues the frames into one long screenshot.
    func takeScrollingScreenshot() async {
        if ScrollingCapture.shared.isRunning { return }
        closeMenuPanel()
        if !InputEventRecorder.hasAccessibilityAccess {
            requestAccessibilityAccess()
            Toast.shared.show("Allow Accessibility for Bugbear so it can scroll, then try again", symbol: "lock.fill", seconds: 4)
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { item in item.frame.contains(mouse) } ?? NSScreen.main
        guard let chosen = screen, let area = await regionSelector.pick(on: chosen, initial: nil, confirmTitle: "Capture  ↩", showsSizes: false) else { return }
        let app = lastExternalApp
        // Let the picker disappear before the first frame.
        try? await Task.sleep(nanoseconds: 300_000_000)
        do {
            guard let image = try await ScrollingCapture.shared.run(on: chosen, area: area) else { return }
            let file = AppPaths.temporary.appendingPathComponent("scroll-\(UUID().uuidString).png")
            ImageFiles.write(image, to: file, type: "public.png")
            let environment = await EnvironmentCollector.snapshot(for: app, readURL: settings.readBrowserURL)
            let capture = try store.add(kind: .screenshot, mediaFile: file, environment: environment)
            Toast.shared.show("Long screenshot: \(image.height) px", symbol: "arrow.down.to.line", seconds: 2)
            WindowManager.shared.openEditor(for: capture)
        } catch ScrollingCapture.Failure.noAccessibility {
            requestAccessibilityAccess()
        } catch {
            showError("Scrolling screenshot failed: \(error.localizedDescription)")
        }
    }

    // MARK: Screen checks

    /// Resizes the front window of the app you were using (needs Accessibility).
    func resizeFrontWindow(to preset: WindowResizer.Preset) {
        closeMenuPanel()
        let app = lastExternalApp
        switch WindowResizer.resize(app: app, to: preset.size) {
        case .success(let size):
            let name = app?.localizedName ?? "Window"
            var text = "\(name): \(Int(size.width)) × \(Int(size.height))"
            let wider = size.width > preset.size.width + 1
            let smaller = size.width < preset.size.width - 1 || size.height < preset.size.height - 1
            if wider && AppState.isBrowser(app) {
                text += ". Narrower than \(Int(size.width)) pt needs the browser's responsive mode: ⌥⌘R in Safari, ⇧⌘M in Chrome DevTools"
            } else if wider {
                text += " (the app's minimum width)"
            } else if smaller {
                text += " (limited by the screen)"
            }
            Toast.shared.show(text, symbol: "macwindow", seconds: wider ? 5 : 2)
        case .failure(.noAccess):
            requestAccessibilityAccess()
            Toast.shared.show("Allow Accessibility for Bugbear, then try again", symbol: "lock.fill", seconds: 3)
        case .failure(.noApp), .failure(.noWindow):
            Toast.shared.show("No window to resize: click the app first", symbol: "macwindow", seconds: 3)
        case .failure(.refused):
            Toast.shared.show("That window cannot be resized", symbol: "macwindow", seconds: 3)
        }
    }

    static func isBrowser(_ app: NSRunningApplication?) -> Bool {
        let browsers = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser", "com.operasoftware.Opera"]
        return browsers.contains(app?.bundleIdentifier ?? "")
    }

    func startRuler() {
        closeMenuPanel()
        ScreenRuler.shared.start()
    }

    func pickColor() {
        closeMenuPanel()
        Task { await ColorPick.pickAndCopy() }
    }

    func openDesignOverlay(fromClipboard: Bool) {
        closeMenuPanel()
        if fromClipboard {
            if !DesignOverlay.shared.openFromClipboard() {
                Toast.shared.show("No image on the clipboard", symbol: "photo", seconds: 3)
            }
        } else {
            DesignOverlay.shared.openFromFile()
        }
    }

    // MARK: Toolbox, environment, misc

    func openToolbox(tool: ToolKind?) {
        closeMenuPanel()
        WindowManager.shared.openToolbox(tool: tool)
    }

    func refreshEnvironmentPreview() async {
        environmentPreview = await EnvironmentCollector.snapshot(for: lastExternalApp, readURL: false)
    }

    func showError(_ message: String) {
        Log.error("alert: \(message)")
        statusMessage = message
        if Automation.isEnabled { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Bugbear"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Hides the MenuBarExtra panel before capturing so it is not in the shot.
    var isMenuPanelOpen: Bool {
        for window in NSApp.windows where window.className.contains("MenuBarExtra") && window.isVisible {
            return true
        }
        return false
    }

    /// Closes the menu bar panel the way a click on the bear does. Hiding the panel window directly
    /// left SwiftUI thinking it was still open, so the next click on the bear only "closed" it and
    /// nothing appeared.
    func closeMenuPanel() {
        if !isMenuPanelOpen { return }
        if let button = statusItemButton() {
            button.performClick(nil)
            return
        }
        for window in NSApp.windows where window.className.contains("MenuBarExtra") {
            window.orderOut(nil)
        }
    }

    /// The bear in the menu bar, as an AppKit button.
    func statusItemButton() -> NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = AppState.findStatusButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func findStatusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view = view else { return nil }
        if let button = view as? NSStatusBarButton {
            return button
        }
        for child in view.subviews {
            if let found = findStatusButton(in: child) {
                return found
            }
        }
        return nil
    }
}
