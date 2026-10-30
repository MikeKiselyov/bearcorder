import AVFoundation
import AppKit
import AppCore
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
                title: L("permissions.screen.title"),
                detail: L("permissions.screen.detail"),
                examples: PermissionUse.screen,
                granted: screenAccess,
                required: true,
                pane: "Privacy_ScreenCapture",
                action: { app.requestScreenRecordingAccess() },
                extra: screenAccess && app.bufferState == .needsPermission ? AnyView(Button(L("permissions.screen.relaunch")) { relaunch() }.buttonStyle(SecondaryButtonStyle())) : nil
            )
            row(
                title: L("permissions.accessibility.title"),
                detail: L("permissions.accessibility.detail"),
                examples: PermissionUse.accessibility,
                granted: accessibilityAccess,
                required: false,
                pane: "Privacy_Accessibility",
                action: { app.requestAccessibilityAccess() },
                extra: nil
            )
            row(
                title: L("permissions.microphone.title"),
                detail: L("permissions.microphone.detail"),
                examples: PermissionUse.microphone,
                granted: microphoneStatus == .authorized,
                required: false,
                pane: "Privacy_Microphone",
                action: { SystemActions.askPermission("Microphone") { Task { _ = await AVCaptureDevice.requestAccess(for: .audio); refresh() } } },
                extra: nil
            )
            row(
                title: L("permissions.camera.title"),
                detail: L("permissions.camera.detail"),
                examples: PermissionUse.camera,
                granted: cameraStatus == .authorized,
                required: false,
                pane: "Privacy_Camera",
                action: { SystemActions.askPermission("Camera") { Task { _ = await AVCaptureDevice.requestAccess(for: .video); refresh() } } },
                extra: nil
            )
            row(
                title: L("permissions.browsers.title"),
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
            return L("permissions.browsers.detail.denied", AppInfo.name)
        case .notRunning:
            return L("permissions.browsers.detail.notRunning")
        default:
            return L("permissions.browsers.detail.ask")
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
                        Text(required ? L("permissions.badge.required") : L("permissions.badge.optional"))
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
                    Text(L("permissions.allowed")).font(.system(size: 12)).foregroundStyle(Theme.success)
                    if opensAllowed {
                        Button(L("permissions.button.open")) { openPane(pane) }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityLabel(L("permissions.button.open.accessibility", title))
                            .tip(L("permissions.button.open.tip"))
                    }
                } else {
                    Button(L("permissions.button.allow"), action: action)
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityLabel(L("permissions.button.allow.accessibility", title))
                        .tip(L("permissions.button.allow.tip"))
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
