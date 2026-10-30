import AppKit
import ScreenCaptureKit
import Observation
import AppCore
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
    var displayCount = NSScreen.screens.count

    @ObservationIgnored var buffers: [ScreenBuffer] = []
    @ObservationIgnored let inputRecorder = InputEventRecorder()
    @ObservationIgnored let crashWatcher = CrashWatcher()
    @ObservationIgnored let recordingOutline = RecordingOutline()
    @ObservationIgnored let microphone = MicrophoneSource()
    @ObservationIgnored let camera = CameraBubble()
    @ObservationIgnored let regionSelector = RegionSelector()
    @ObservationIgnored let hud = RecordingHUDController()
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
    @ObservationIgnored var recordingRegion: RegionSelector.Selection?
    /// While an area is recorded the displays it touches run at their full resolution (and the
    /// recording frame rate), so a "720p" area really comes out 1280×720 instead of a crop of the
    /// downscaled buffer. The other displays keep the buffer's resolution. Grows when the area is moved
    /// onto another display, never shrinks during a recording.
    @ObservationIgnored var nativeDisplaysForArea: Set<CGDirectDisplayID> = []
    /// The one display a recording keeps: the one under the pointer when "Record all displays" is
    /// off. Nil records every buffered display side by side, or the area wherever it is.
    @ObservationIgnored var recordingDisplay: CGDirectDisplayID?
    /// The buffer runs at the recording frame rate while recording.
    @ObservationIgnored var boostedFrameRate = false
    /// Between pressing record and the recording running: a second press must not start another.
    @ObservationIgnored var isStartingRecording = false
    @ObservationIgnored var screensChangedWhileRecording = false
    /// A display the buffer does not normally capture, added for the length of one recording.
    @ObservationIgnored var extraDisplayForRecording: CGDirectDisplayID?
    /// An area recording keeps every display, so the area can go to any of them.
    @ObservationIgnored var allDisplaysForArea = false
    /// A buffer that stopped on its own (the displays went away) and comes back by itself.
    var bufferRecovery = BufferRecovery()
    @ObservationIgnored var bufferRecoveryTask: Task<Void, Never>?
    @ObservationIgnored var bufferStart: Task<Void, Never>?
    /// Tests only: the next starts fail as if no display were there.
    @ObservationIgnored var failingBufferStartsForTests = 0

    /// Inserted in the menu bar; taken out and put back to move it.
    var showsMenuBarItem = true
    /// The hint about a full menu bar is shown once per launch.
    @ObservationIgnored var toldAboutHiddenItem = false
    @ObservationIgnored var cleanUpTimer: Timer?
    /// Tests pick storage limits in Settings and put them back; the timed clean-up waits meanwhile,
    /// so a limit that is on for a moment never deletes the person's captures.
    @ObservationIgnored var scheduledCleanUpPaused = false
    /// The capture whose editor should say "Copied" when it opens.
    @ObservationIgnored var justCopiedScreenshot: UUID?

    private init() {}

    var primaryBuffer: ScreenBuffer? {
        return buffers.first
    }

    // MARK: Launch

    func launch() {
        if launched { return }
        launched = true
        ScreenBuffer.clearBufferFolder()
        Task { await keepMenuBarItemVisible(reason: "launch") }

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
        // The displays of a closed lid or a sleeping Mac come back without a display change.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    AppState.shared.recoverBufferNow(reason: "screens woke")
                }
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
        // macOS writes the crash report a moment after the crash, so it is there by the next launch.
        // Checked right away; test runs (automation on at launch) never get the window.
        let offerCrashReport = settings.offerCrashReports && !Automation.isEnabled
        Task { @MainActor in
            await Feedback.offerReportAfterCrash(enabled: offerCrashReport)
        }
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
        // e2e tests open the guide like a new person would only when they ask for it.
        let showsGuideInTests = Automation.isEnabled && UserDefaults.standard.bool(forKey: "automationFirstLaunch")
        if isFirstLaunch && (!Automation.isEnabled || showsGuideInTests) {
            // First launch: the guide asks for permissions before the buffer starts.
            Log.info("first launch: opening the welcome guide")
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
    @ObservationIgnored nonisolated(unsafe) var micSink: ScreenBuffer?

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

    /// Called every second. The activity bars and the covered time are only shown in the menu bar
    /// panel, so with the panel closed they are left alone (no work for hidden views); `force`
    /// updates them anyway.
    func refreshStatus(force: Bool = false) {
        let accessibility = InputEventRecorder.hasAccessibilityAccess
        if accessibility != hasAccessibilityAccess {
            hasAccessibilityAccess = accessibility
        }
        guard let primary = primaryBuffer, primary.isRunning else {
            if coveredSeconds != 0 {
                coveredSeconds = 0
            }
            return
        }
        if !force && !isMenuPanelOpen { return }
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
        if signature == screenSignature {
            // Displays that wake up keep their frames, but a waiting buffer can start now.
            recoverBufferNow(reason: "displays woke")
            return
        }
        Log.info("displays changed: \(signature)")
        screenSignature = signature
        Task { await keepMenuBarItemVisible(reason: "displays changed") }
        if bufferState == .running && recording == nil {
            Task { await restartBufferIfRunning() }
        } else if recording != nil {
            // The buffer is restarted when the recording ends.
            screensChangedWhileRecording = true
        }
        recoverBufferNow(reason: "displays changed")
    }

}
