import AppKit
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

QAHelperApp.main()

struct QAHelperApp: App {
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
            return "QA Helper, recording \(app.menuBarText)"
        }
        if app.bufferState == .running {
            return "QA Helper, buffer running"
        }
        return "QA Helper"
    }
}
