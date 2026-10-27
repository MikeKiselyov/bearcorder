import AVFoundation
import AppKit
import BugbearCore
import SwiftUI

/// Every permission with what it is for, whether it is given, and Allow…: on the welcome guide's
/// Permissions step and on the Permissions page of Settings. Checks again every second, so a
/// permission given in System Settings shows up here at once.
struct PermissionsList: View {
    @Environment(AppState.self) private var app
    /// What Relaunch does: the guide also remembers its step first.
    var relaunch: () -> Void
    /// Settings shows Open… on allowed ones, to check or take a permission back in System Settings.
    var opensAllowed: Bool = false

    @State private var screenAccess = ScreenBuffer.hasScreenRecordingAccess
    @State private var accessibilityAccess = InputEventRecorder.hasAccessibilityAccess
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var browsers = EnvironmentCollector.BrowserAccess.notRunning
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(
                title: "Screen & System Audio Recording",
                detail: "Required for screenshots, recordings and the buffer. After allowing it, relaunch the app.",
                examples: PermissionUse.screen,
                granted: screenAccess,
                required: true,
                pane: "Privacy_ScreenCapture",
                action: { app.requestScreenRecordingAccess() },
                extra: screenAccess && app.bufferState == .needsPermission ? AnyView(Button("Relaunch") { relaunch() }.buttonStyle(SecondaryButtonStyle())) : nil
            )
            row(
                title: "Accessibility",
                detail: "Names what you click and type into, and shows the shortcut keys you press, as steps in videos and bug reports.",
                examples: PermissionUse.accessibility,
                granted: accessibilityAccess,
                required: false,
                pane: "Privacy_Accessibility",
                action: { app.requestAccessibilityAccess() },
                extra: nil
            )
            row(
                title: "Microphone",
                detail: "Your voice in recordings, when you turn the mic on.",
                examples: PermissionUse.microphone,
                granted: microphoneStatus == .authorized,
                required: false,
                pane: "Privacy_Microphone",
                action: { SystemActions.askPermission("Microphone") { Task { _ = await AVCaptureDevice.requestAccess(for: .audio); refresh() } } },
                extra: nil
            )
            row(
                title: "Camera",
                detail: "The round camera bubble you can show while recording.",
                examples: PermissionUse.camera,
                granted: cameraStatus == .authorized,
                required: false,
                pane: "Privacy_Camera",
                action: { SystemActions.askPermission("Camera") { Task { _ = await AVCaptureDevice.requestAccess(for: .video); refresh() } } },
                extra: nil
            )
            row(
                title: "Browsers (Automation)",
                detail: browserDetail,
                examples: PermissionUse.browsers,
                granted: browsers == .allowed,
                required: false,
                pane: "Privacy_Automation",
                action: { allowBrowsers() },
                extra: nil
            )
        }
        .onReceive(ticker) { _ in refresh() }
        .onAppear { refresh() }
    }

    private var browserDetail: String {
        switch browsers {
        case .denied:
            return "Turned off for a browser: the URL stays empty. Allow… opens System Settings → Automation, switch \(AppInfo.name) on there."
        case .notRunning:
            return "Reads the address of the open tab for the URL field. Open your browser to check it here."
        default:
            return "Reads the address of the open tab for the URL field. macOS asks once for each browser."
        }
    }

    /// Asks for every open browser; one already turned off can only be switched on in System Settings.
    private func allowBrowsers() {
        if browsers == .denied || browsers == .notRunning {
            openPane("Privacy_Automation")
            return
        }
        let open = EnvironmentCollector.runningBrowsers
        SystemActions.askPermission("Automation") {
            Task.detached {
                _ = EnvironmentCollector.browsersAccess(open, ask: true)
                await MainActor.run { refresh() }
            }
        }
    }

    private func refresh() {
        screenAccess = ScreenBuffer.hasScreenRecordingAccess
        accessibilityAccess = InputEventRecorder.hasAccessibilityAccess
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let open = EnvironmentCollector.runningBrowsers
        Task.detached {
            let access = EnvironmentCollector.browsersAccess(open, ask: false)
            await MainActor.run { browsers = access }
        }
    }

    private func openPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            SystemActions.open(url)
        }
    }

    private func row(title: String, detail: String, examples: [PermissionUse], granted: Bool, required: Bool, pane: String, action: @escaping () -> Void, extra: AnyView?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
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
                    if opensAllowed {
                        Button("Open…") { openPane(pane) }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityLabel("Open \(title) in System Settings")
                            .tip("See or take back this permission in System Settings")
                    }
                } else {
                    Button("Allow…", action: action)
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityLabel("Allow \(title)")
                        .tip("Ask macOS for this permission")
                }
            }
            // Examples of what it is for, across the whole row and lined up with the text.
            PermissionUses(uses: examples)
                .padding(.leading, 32)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
