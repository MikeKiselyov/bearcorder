import AppKit
import ServiceManagement
import SwiftUI
import BugbearCore

/// The pages of Settings, listed in its sidebar.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General"
    case permissions = "Permissions"
    case recording = "Buffer and recording"
    case reports = "Bug reports"
    case storage = "Storage"
    case shortcuts = "Shortcuts"
    case updates = "Updates and feedback"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .permissions: return "lock.shield"
        case .recording: return "record.circle"
        case .reports: return "ladybug"
        case .storage: return "internaldrive"
        case .shortcuts: return "keyboard"
        case .updates: return "arrow.down.circle"
        }
    }

    var tint: TileTint {
        switch self {
        case .general: return .gray
        case .permissions: return .teal
        case .recording: return .coral
        case .reports: return .green
        case .storage: return .blue
        case .shortcuts: return .purple
        case .updates: return .yellow
        }
    }

    var help: String {
        switch self {
        case .general: return "Open at login, the save folder and screenshots"
        case .permissions: return "What \(AppInfo.name) may use on your Mac, and what each one is for"
        case .recording: return "The buffer, frame rates, sound, clicks and keys"
        case .reports: return "Bug report format, your fields, the environment and crash clips"
        case .storage: return "Space used by captures and automatic clean-up"
        case .shortcuts: return "Change the keyboard shortcuts"
        case .updates: return "New versions, what's new and feedback"
        }
    }
}

/// Which Settings page is shown. Shared so tests can open the page a control is on.
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var page: SettingsPage = .general
}

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var navigation = SettingsNavigation.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsRestart = false

    var body: some View {
        @Bindable var settings = app.settings
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    IconTile(systemImage: navigation.page.symbol, tint: navigation.page.tint, size: 52)
                        .shadow(color: navigation.page.tint.color.opacity(0.45), radius: 14, y: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(navigation.page.rawValue).font(.system(size: 22, weight: .bold))
                        Text(navigation.page.help).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .accessibilityElement(children: .combine)
                if navigation.page == .permissions {
                    // Rows with examples under them: their own layout, not form rows.
                    ScrollView {
                        PermissionsList(relaunch: {
                            if SystemActions.recordInstead("relaunch") { return }
                            Relaunch.now()
                        }, opensAllowed: true)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 20)
                    }
                } else {
                    Form {
                        switch navigation.page {
                        case .general:
                            generalPage
                        case .permissions:
                            EmptyView()
                        case .recording:
                            recordingPage
                        case .reports:
                            reportsPage
                        case .storage:
                            StorageSettingsSection()
                        case .shortcuts:
                            ShortcutSettingsSection()
                        case .updates:
                            updatesPage
                        }
                    }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .auroraBackground()
        .onChange(of: settings.bufferMinutes) { needsRestart = true }
        .onChange(of: settings.framesPerSecond) { needsRestart = true }
        .onChange(of: settings.maxHeight) { needsRestart = true }
        .onChange(of: settings.captureAllDisplays) { needsRestart = true }
        .onChange(of: settings.showsCursor) { needsRestart = true }
        .onChange(of: settings.recordSystemAudio) { needsRestart = true }
        .onChange(of: settings.recordMicrophone) { needsRestart = true }
        .onChange(of: settings.recordClicks) { needsRestart = true }
        .onChange(of: settings.recordKeys) { needsRestart = true }
        .onChange(of: settings.recordTypedText) { app.applyStepPrivacy() }
        .onChange(of: settings.readBrowserURL) { app.applyStepPrivacy() }
        .onChange(of: settings.saveOnCrash) { app.updateCrashWatcher() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                LogoView(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name).font(.system(size: 14, weight: .bold))
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
            ForEach(SettingsPage.allCases) { page in
                Button {
                    navigation.page = page
                } label: {
                    HStack(spacing: 10) {
                        IconTile(systemImage: page.symbol, tint: page.tint, size: 26)
                        Text(page.rawValue)
                    }
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                        .background(navigation.page == page ? Theme.controlSelected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(navigation.page == page ? Theme.text : Theme.textSecondary)
                .accessibilityLabel("Page: \(page.rawValue)")
                .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
                .tip(page.help)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 40)
        .frame(width: 210)
        .background(Theme.sidebar)
    }

    @ViewBuilder private var generalPage: some View {
        @Bindable var settings = app.settings
        Section("General") {
            Toggle("Open at login", isOn: $launchAtLogin)
                .tip("Start \(AppInfo.name) automatically when you log in to your Mac")
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            HStack {
                Text("Welcome guide")
                Spacer()
                Button("Show…") { WindowManager.shared.openOnboarding() }
                    .accessibilityLabel("Show the welcome guide")
                    .tip("Open the welcome guide again")
            }
        }

        Section("Export") {
            HStack {
                Text("Save to")
                Spacer()
                Text(settings.outputFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…") { chooseFolder() }
                    .tip("Choose the folder where exported files are saved")
            }
        }

        Section("Screenshots") {
            Toggle("Copy a new screenshot to the clipboard", isOn: $settings.copyScreenshots)
                .tip("Put every new screenshot on the clipboard so you can paste it right away")
            Text("Paste it with ⌘V right away; the editor opens too, and ⌘C there copies your marks.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder private var recordingPage: some View {
        @Bindable var settings = app.settings
        Section("Buffer") {
            Picker("Keep the last", selection: $settings.bufferMinutes) {
                Text("1 minute").tag(1)
                Text("2 minutes").tag(2)
                Text("3 minutes").tag(3)
                Text("5 minutes").tag(5)
            }
            .tip("How much of the recent screen the buffer keeps, ready to save as a clip")
            Picker("Buffer frame rate", selection: $settings.framesPerSecond) {
                Text("15 fps (lightest)").tag(15)
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            .tip("Frames per second of the background buffer; lower uses less CPU and memory")
            Picker("Recording frame rate", selection: $settings.recordingFramesPerSecond) {
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            .tip("Frames per second of regular screen recordings")
            Picker("Resolution", selection: $settings.maxHeight) {
                Text("720p").tag(720)
                Text("1080p").tag(1080)
                Text("1440p").tag(1440)
                Text("Native").tag(0)
            }
            .tip("Maximum height of saved clips; lower makes smaller files")
            Toggle("Keep all displays (pick one or all side by side in the editor)", isOn: $settings.captureAllDisplays)
                .tip("Buffer every connected display instead of only the main one")
            Toggle("Show the mouse pointer", isOn: $settings.showsCursor)
                .tip("Include the mouse pointer in the buffer and recordings")
            Toggle("Start the buffer when the app opens", isOn: $settings.startBufferOnLaunch)
                .tip("Start keeping the recent screen as soon as \(AppInfo.name) launches")
            if needsRestart {
                HStack {
                    Text("Restart the buffer to apply. What it holds now is dropped.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Restart buffer") {
                        needsRestart = false
                        Task { await app.restartBufferIfRunning() }
                    }
                    .tip("Restart the buffer so the new settings apply; the clip it holds now is lost")
                }
            }
        }

        Section("Audio") {
            Toggle("Record system audio", isOn: $settings.recordSystemAudio)
                .tip("Include the sound your Mac plays in the buffer and recordings")
            Toggle("Record microphone", isOn: $settings.recordMicrophone)
                .tip("Include your microphone in the buffer and recordings")
        }

        Section("Clicks and keys") {
            Toggle("Record clicks", isOn: $settings.recordClicks)
                .tip("Remember mouse clicks so they show up as steps and highlights in clips")
            Toggle("Record shortcut keys", isOn: $settings.recordKeys)
                .tip("Remember shortcut keys like ⌘S so they show up as steps in clips")
            if settings.recordKeys && !app.hasAccessibilityAccess {
                HStack {
                    Text("Needs Accessibility access")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warning)
                    Spacer()
                    Button("Grant") { app.requestAccessibilityAccess() }
                        .tip("Ask macOS for Accessibility access, needed to see shortcut keys")
                }
            }
            TypedTextChoice(isOn: $settings.recordTypedText)
        }
    }

    @ViewBuilder private var reportsPage: some View {
        @Bindable var settings = app.settings
        ReportSettingsSection()

        Section("Environment") {
            Toggle("Read the browser tab URL", isOn: $settings.readBrowserURL)
                .tip("Add the current browser tab URL to the environment info of captures, and an Open step for every page in the steps")
            Text("Safari, Chrome, Arc, Brave, Edge, Vivaldi and Opera. macOS asks once per browser.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }

        Section("Crashes and logs") {
            Toggle("Save a clip when an app crashes", isOn: $settings.saveOnCrash)
                .tip("Automatically save the minute before a crash together with the crash report")
            Text("When an app you used in the last 10 minutes crashes, the minute before the crash is saved to Recent with the crash report.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Toggle("Attach the app's system log to clips", isOn: $settings.attachSystemLogs)
                .tip("Add the front app's recent system log lines to saved clips for debugging")
        }
    }

    @ViewBuilder private var updatesPage: some View {
        @Bindable var settings = app.settings
        UpdateSettingsSection()

        Section("Feedback") {
            HStack {
                Button("Report a problem…") { WindowManager.shared.openFeedback(kind: .problem) }
                    .tip("Open a GitHub issue about \(AppInfo.name) with the version, macOS and logs filled in")
                Button("Suggest a feature…") { WindowManager.shared.openFeedback(kind: .idea) }
                    .tip("Share an idea for \(AppInfo.name) as a GitHub issue")
            }
            Toggle("Offer a report after \(AppInfo.name) crashes", isOn: $settings.offerCrashReports)
                .tip("When \(AppInfo.name) quit unexpectedly, open a report with the crash details on the next launch")
            Text("Opens a filled issue on GitHub. You check it and submit it from your account.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func chooseFolder() {
        if let url = SystemActions.chooseFolder(startingAt: app.settings.outputFolder) {
            app.settings.outputFolderPath = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try SystemActions.setOpenAtLogin(enabled)
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            app.statusMessage = "Open at login works when the app is in /Applications (scripts/build-app.sh --install)."
        }
    }
}

/// The person's choice to show what they type in steps, with what it means. Used in the welcome
/// guide and in Settings.
struct TypedTextChoice: View {
    @Binding var isOn: Bool

    private var explanation: String {
        if isOn {
            return "Steps show the text of the field you typed into, like Type “john@test.com” in “Email” text field. Password fields are never read."
        }
        return "Steps say which field you typed into, not what. Turn on to include the text; password fields are never read."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Show what I type in steps", isOn: $isOn)
                .tip("Steps say Type \"john@test.com\" in \"Email\" text field instead of Type text in \"Email\" text field")
            // Verbatim: as a localized string the example address turned into a mail link.
            Text(verbatim: explanation)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
