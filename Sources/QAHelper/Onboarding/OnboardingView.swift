import AVFoundation
import AppKit
import SwiftUI

/// First-launch guide: what the app does, permissions, shortcuts, where to find it.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var page = 0
    @State private var screenAccess = ScreenBuffer.hasScreenRecordingAccess
    @State private var accessibilityAccess = InputEventRecorder.hasAccessibilityAccess
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private let pageCount = 4
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    static let completedKey = "onboardingCompleted"

    init(startPage: Int = 0) {
        _page = State(initialValue: startPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: permissions
                case 2: shortcuts
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 48)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.text : Theme.borderStrong)
                            .frame(width: index == page ? 18 : 7, height: 7)
                    }
                }
                .accessibilityLabel("Step \(page + 1) of \(pageCount)")
                Spacer()
                if page > 0 {
                    Button("Back") { page -= 1 }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Skip") { complete() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.trailing, 8)
                }
                Button(page == pageCount - 1 ? "Start using QA Helper" : "Continue") {
                    if page == pageCount - 1 {
                        complete()
                    } else {
                        page += 1
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 20)
            .background(Theme.sidebar)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.window)
        .onReceive(ticker) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        screenAccess = ScreenBuffer.hasScreenRecordingAccess
        accessibilityAccess = InputEventRecorder.hasAccessibilityAccess
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: OnboardingView.completedKey)
        WindowManager.shared.close(id: "onboarding")
        if app.bufferState != .running && ScreenBuffer.hasScreenRecordingAccess && app.settings.startBufferOnLaunch {
            Task { await app.startBuffer() }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                LogoView(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to QA Helper").font(.system(size: 26, weight: .bold))
                    Text("Catch the bug that already happened.").font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                }
            }
            feature("gobackward", "Rolling screen buffer", "The last minutes of your screen are always kept. Saw a bug? Save what just happened, no need to reproduce it.")
            feature("record.circle", "Record with pause and drawing", "Record a screen, all screens or an area. Pause, draw arrows on the screen, add your camera and voice.")
            feature("pencil.and.outline", "Mark up and send", "Arrows, boxes, steps and blur on screenshots and videos. The environment (OS, app, URL) is added for you.")
            feature("wrench.and.screwdriver", "Dev toolbox", "Format JSON and XML, decode JWT, convert timestamps and time zones, generate UUIDs.")
            Text("Everything stays on your Mac. Nothing is uploaded.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Theme.accentSoft)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions").font(.system(size: 24, weight: .bold))
            Text("Only Screen Recording is required. The rest turn on extras and can be granted later in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            permissionRow(
                title: "Screen & System Audio Recording",
                detail: "Required for the buffer, recordings and screenshots. After allowing it, relaunch the app.",
                granted: screenAccess,
                required: true,
                action: { app.requestScreenRecordingAccess() },
                extra: screenAccess && app.bufferState == .needsPermission ? AnyView(Button("Relaunch") { relaunch() }.buttonStyle(SecondaryButtonStyle())) : nil
            )
            permissionRow(
                title: "Accessibility",
                detail: "Shows the shortcut keys you press in videos. Plain typing is never recorded as text.",
                granted: accessibilityAccess,
                required: false,
                action: { app.requestAccessibilityAccess() },
                extra: nil
            )
            permissionRow(
                title: "Microphone",
                detail: "Your voice in recordings, when you turn the mic on.",
                granted: microphoneStatus == .authorized,
                required: false,
                action: { Task { _ = await AVCaptureDevice.requestAccess(for: .audio); refreshPermissions() } },
                extra: nil
            )
            permissionRow(
                title: "Camera",
                detail: "The round camera bubble you can show while recording.",
                granted: cameraStatus == .authorized,
                required: false,
                action: { Task { _ = await AVCaptureDevice.requestAccess(for: .video); refreshPermissions() } },
                extra: nil
            )
        }
    }

    private func permissionRow(title: String, detail: String, granted: Bool, required: Bool, action: @escaping () -> Void, extra: AnyView?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : (required ? "exclamationmark.circle.fill" : "circle"))
                .font(.system(size: 18))
                .foregroundStyle(granted ? Theme.success : (required ? Theme.warning : Theme.textTertiary))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(required ? "Required" : "Optional")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.control)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let extraView = extra {
                extraView
            }
            if granted {
                Text("Allowed").font(.system(size: 12)).foregroundStyle(Theme.success)
            } else {
                Button("Allow…", action: action).buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shortcuts").font(.system(size: 24, weight: .bold))
            Text("They work from any app. Everything is also in the menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                shortcut("⌥⇧2", "Save the last minute of the screen", "⌥⇧1 for 30 s, ⌥⇧3 for the whole buffer")
                shortcut("⌥⇧M", "Mark the moment", "The next save reaches back to it and opens there")
                shortcut("⌥⇧4", "Screenshot an area", "⌥⇧5 for a window, ⌥⇧O copies the text in an area")
                shortcut("⌥⇧6", "Start or stop a recording", "⌥⇧7 pauses and resumes")
                shortcut("⌥⇧A", "Draw on the screen", "Arrows and boxes appear in the video")
                shortcut("⌥⇧C", "Camera bubble", "Drag it, scroll to resize")
                shortcut("⌥⇧D", "Dev toolbox", "Opens with what is on your clipboard")
            }
        }
    }

    private func shortcut(_ keys: String, _ title: String, _ hint: String) -> some View {
        GridRow {
            Text(keys)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.control)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(hint).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("You're set").font(.system(size: 24, weight: .bold))
            HStack(spacing: 14) {
                Image(nsImage: Logo.menuBarImage(recording: true))
                    .renderingMode(.template)
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .background(Theme.control)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("QA Helper lives in the menu bar, top right. Click the bear to save from the buffer, take screenshots, record, or open the toolbox.")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Try it now")
                tryStep("1", "Click around in any app for a few seconds.")
                tryStep("2", "Press ⌥⇧1: the last 30 seconds open in the video editor.")
                tryStep("3", "Add an arrow, then Copy and paste it into a ticket.")
            }
            if !screenAccess {
                Label("Screen Recording is not allowed yet, so the buffer cannot start. Go back one step to allow it.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("You can open this guide again from Settings.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func tryStep(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 22, height: 22)
                .background(Theme.accent)
                .clipShape(Circle())
            Text(text).font(.system(size: 13))
        }
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
