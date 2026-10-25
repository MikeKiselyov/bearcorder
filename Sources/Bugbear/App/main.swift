import AppKit
import BugbearCore
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

// `--self-test <folder>`, `--snapshot <folder>` and `--readme-media <folder>`: developer checks and
// README pictures, see DevChecks.swift and ReadmeMedia.swift.
for flag in ["--self-test", "--snapshot", "--readme-media"] {
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
        } else {
            status = await DevChecks.snapshot(folder: folder)
        }
        exit(status)
    }
    RunLoop.main.run()
}

BugbearApp.main()

struct BugbearApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
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
            return "Bugbear, recording"
        }
        if app.bufferState == .running {
            return "Bugbear, buffer running"
        }
        return "Bugbear"
    }
}
