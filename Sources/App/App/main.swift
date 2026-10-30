import AppKit
import ServiceManagement
import AppCore
import SwiftUI

// `--render-iconset <folder>` writes the logo PNGs for the build script, then exits.
let arguments = CommandLine.arguments
if let flagIndex = arguments.firstIndex(of: "--render-iconset"), flagIndex + 1 < arguments.count {
    let folder = URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
    do {
        try Logo.writeIconset(to: folder)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Failed to render icon: \(error)\n".utf8))
        exit(1)
    }
}

// `--version` prints the newest release's version (build-app.sh puts it in Info.plist);
// `--release-notes` prints that release as Markdown (CI uses it for the GitHub release).
// For uninstall.sh: takes the app off the login items before it is deleted (only the app itself can).
if arguments.contains("--forget-login-item") {
    if SMAppService.mainApp.status == .enabled {
        try? SMAppService.mainApp.unregister()
    }
    print("login item: \(SMAppService.mainApp.status == .enabled ? "still on" : "off")")
    exit(0)
}
if arguments.contains("--version") {
    print(WhatsNew.latestVersion(WhatsNewCatalog.releases))
    exit(0)
}
if arguments.contains("--release-notes") {
    if let newest = WhatsNew.unseen(WhatsNewCatalog.releases, lastSeenID: 0).first {
        print(WhatsNew.markdown(newest))
    }
    exit(0)
}

// Developer flags, only in builds with AUTOMATION (see DevTools/).
#if AUTOMATION
// `--clip-frame <capture folder> <seconds> <out.png>`: the video editor's preview frame of a saved
// clip, with its marks, at a time of the source clip. For working out what the editor shows.
if let flagIndex = arguments.firstIndex(of: "--clip-frame"), flagIndex + 3 < arguments.count {
    let folder = URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
    let seconds = Double(arguments[flagIndex + 2]) ?? 0
    let output = URL(fileURLWithPath: arguments[flagIndex + 3])
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    Task { @MainActor in
        exit(await DevChecks.clipFrame(folder: folder, seconds: seconds, to: output))
    }
    RunLoop.main.run()
}

if arguments.contains("--perf-core") {
    _ = NSApplication.shared
    let status = MainActor.assumeIsolated { DevChecks.perfCore() }
    exit(status)
}

if let flagIndex = arguments.firstIndex(of: "--export-check"), flagIndex + 2 < arguments.count {
    let file = URL(fileURLWithPath: arguments[flagIndex + 1])
    let folder = URL(fileURLWithPath: arguments[flagIndex + 2], isDirectory: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    Task { @MainActor in
        exit(await DevChecks.exportCheck(file: file, folder: folder))
    }
    RunLoop.main.run()
}

// `--self-test <folder>`, `--snapshot <folder>`, `--readme-media <folder>` and
// `--whats-new-media <folder>`: developer checks, README pictures and "What's new" animations, see
// DevChecks.swift, ReadmeMedia.swift and WhatsNewMedia.swift.
for flag in ["--self-test", "--snapshot", "--readme-media", "--whats-new-media"] {
    guard let flagIndex = arguments.firstIndex(of: flag), flagIndex + 1 < arguments.count else { continue }
    let folder = URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    Task { @MainActor in
        let status: Int32
        if flag == "--self-test" {
            status = await DevChecks.selfTest(folder: folder)
        } else if flag == "--readme-media" {
            status = await ReadmeMedia.make(folder: folder)
        } else if flag == "--whats-new-media" {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let written = WhatsNewMedia.writeStepsGIF(to: folder.appendingPathComponent("steps.gif"))
            status = written ? 0 : 1
        } else {
            status = await DevChecks.snapshot(folder: folder)
        }
        exit(status)
    }
    RunLoop.main.run()
}
#else
// A release has no developer tools: say so instead of starting the app.
for flag in ["--self-test", "--snapshot", "--readme-media", "--whats-new-media", "--clip-frame", "--perf-core", "--export-check"] where arguments.contains(flag) {
    FileHandle.standardError.write(Data("\(flag) needs a build with the developer tools (swift build, or APP_AUTOMATION=1 scripts/build-app.sh)\n".utf8))
    exit(2)
}
#endif

MainApp.main()

struct MainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { state.showsMenuBarItem }, set: { value in state.showsMenuBarItem = value })) {
            MenuBarView()
                .environment(state)
                .preferredColorScheme(.dark)
        } label: {
            MenuBarLabel()
                .environment(state)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = Logo.nsImage
        MainActor.assumeIsolated {
            AppState.shared.launch()
        }
    }

    /// `pkill` and `kill` send SIGTERM, which ends the process before AppKit can clean up; it becomes
    /// an ordinary quit instead.
    private var terminationSignal: DispatchSourceSignal?
    private var quitReplied = false

    /// Longest wait for the captures to stop before quitting anyway.
    static let quitTimeout: Double = 2

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Until the person drags the bear somewhere, it goes next to the system icons: as the newest
        // item it would otherwise be the leftmost, the first one hidden behind the notch.
        if UserDefaults.standard.object(forKey: MenuBarPlacement.positionKey) == nil {
            UserDefaults.standard.set(MenuBarPlacement.visiblePosition, forKey: MenuBarPlacement.positionKey)
        }
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            // A modal alert or a busy main thread can hold the quit back; SIGTERM still has to end
            // the process, or an update would replace the app under a copy that keeps running.
            // Set first: nothing after the quit starts is sure to run.
            DispatchQueue.global().asyncAfter(deadline: .now() + AppDelegate.quitTimeout + 2) {
                Log.error("quit did not finish, exiting")
                _exit(0)
            }
            Log.info("quit requested by SIGTERM")
            // Not from this handler: it runs as part of the main queue, and the quit waits for a
            // main queue task (stopping the capture) that cannot start until the handler returns.
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    NSApp.terminate(nil)
                }
            }
        }
        source.resume()
        terminationSignal = source
    }

    /// Stops every screen capture first, so macOS takes its "Currently Sharing" indicator down
    /// instead of keeping it for a process that is gone.

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            WindowManager.shared.reopenFromDock()
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitReplied = false
        let quitSender = AppDelegate.quitSenderBundleID()
        if QuitRequest.comesFromSystemSettings(senderBundleID: quitSender) {
            Log.info("quit from \(quitSender ?? ""): opening again")
            Relaunch.openAgainAfterQuit()
        }
        Task { @MainActor in
            await AppState.shared.stopCaptureForQuit()
            if !self.quitReplied {
                Log.info("capture stopped for quit")
            }
            self.replyToQuit()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + AppDelegate.quitTimeout) {
            MainActor.assumeIsolated {
                if !self.quitReplied {
                    Log.error("quit timed out waiting for the capture to stop")
                }
                self.replyToQuit()
            }
        }
        return .terminateLater
    }

    /// The app that sent the Quit Apple event being handled, nil for the app's own Quit.
    static func quitSenderBundleID() -> String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return nil }
        guard let pidDescriptor = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) else { return nil }
        let pid = pidDescriptor.int32Value
        if pid == 0 || pid == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        if let running = NSRunningApplication(processIdentifier: pid), let bundleID = running.bundleIdentifier {
            return bundleID
        }
        // An extension (the System Settings panes are) is not always known as a running app: the
        // bundle id comes from the .appex or .app its executable sits in.
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) <= 0 {
            return nil
        }
        var folder = URL(fileURLWithPath: String(cString: pathBuffer))
        while folder.path != "/" {
            if folder.pathExtension == "appex" || folder.pathExtension == "app" {
                return Bundle(url: folder)?.bundleIdentifier
            }
            folder.deleteLastPathComponent()
        }
        return nil
    }

    @MainActor private func replyToQuit() {
        if quitReplied { return }
        quitReplied = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScreenBuffer.clearBufferFolder()
    }
}

/// Menu bar item: the bear glyph only, always the same width. A label that grows (a timer next to
/// the icon) gets pushed behind the notch and hidden, most often right when recording starts and
/// macOS adds its own screen recording indicator. The recording timer lives in the HUD instead.
/// Images are created once: a new NSImage on every render makes the status item relayout in a loop.
struct MenuBarLabel: View {
    @Environment(AppState.self) private var app

    private static let recordingImage = Logo.menuBarImage(recording: true)
    private static let bufferingImage = Logo.menuBarImage(recording: false, buffering: true)
    private static let idleImage = Logo.menuBarImage(recording: false)

    var body: some View {
        Image(nsImage: image)
            .accessibilityLabel(accessibilityText)
    }

    private var image: NSImage {
        if app.recording != nil {
            return MenuBarLabel.recordingImage
        }
        if app.bufferState == .running {
            return MenuBarLabel.bufferingImage
        }
        return MenuBarLabel.idleImage
    }

    private var accessibilityText: String {
        if app.recording != nil {
            // No running time here: a label that changes every second redraws the menu bar item,
            // and every redraw is a new frame for the capture to encode.
            return L("app.menuBar.accessibility.recording", AppInfo.name)
        }
        if app.bufferState == .running {
            return L("app.menuBar.accessibility.buffering", AppInfo.name)
        }
        return AppInfo.name
    }
}
