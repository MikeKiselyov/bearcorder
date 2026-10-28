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

    /// The page's name in the sidebar and the header. `rawValue` stays the English name for automation.
    var title: String {
        switch self {
        case .general: return L("settings.page.general")
        case .permissions: return L("settings.page.permissions")
        case .recording: return L("settings.page.recording")
        case .reports: return L("settings.page.reports")
        case .storage: return L("settings.page.storage")
        case .shortcuts: return L("settings.page.shortcuts")
        case .updates: return L("settings.page.updates")
        }
    }

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
        case .general: return L("settings.page.general.help")
        case .permissions: return L("settings.page.permissions.help", AppInfo.name)
        case .recording: return L("settings.page.recording.help")
        case .reports: return L("settings.page.reports.help")
        case .storage: return L("settings.page.storage.help")
        case .shortcuts: return L("settings.page.shortcuts.help")
        case .updates: return L("settings.page.updates.help")
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
                        Text(navigation.page.title).font(.system(size: 22, weight: .bold))
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
                    Text(L("settings.sidebar.version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"))
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
                        Text(page.title)
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
                .accessibilityLabel(L("settings.sidebar.page.label", page.title))
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
        Section(L("settings.general.section")) {
            Toggle(L("settings.general.openAtLogin"), isOn: $launchAtLogin)
                .tip(L("settings.general.openAtLogin.tip", AppInfo.name))
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            HStack {
                Text(L("settings.general.welcomeGuide"))
                Spacer()
                Button(L("settings.general.welcomeGuide.show")) { WindowManager.shared.openOnboarding() }
                    .accessibilityLabel(L("settings.general.welcomeGuide.show.label"))
                    .tip(L("settings.general.welcomeGuide.show.tip"))
            }
        }

        Section(L("settings.export.section")) {
            HStack {
                Text(L("settings.export.saveTo"))
                Spacer()
                Text(settings.outputFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(L("settings.export.choose")) { chooseFolder() }
                    .tip(L("settings.export.choose.tip"))
            }
        }

        Section(L("settings.screenshots.section")) {
            Toggle(L("settings.screenshots.copy"), isOn: $settings.copyScreenshots)
                .tip(L("settings.screenshots.copy.tip"))
            Text(L("settings.screenshots.copy.note"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder private var recordingPage: some View {
        @Bindable var settings = app.settings
        Section(L("settings.buffer.section")) {
            Picker(L("settings.buffer.length"), selection: $settings.bufferMinutes) {
                Text(L("settings.buffer.length.minutes", 1)).tag(1)
                Text(L("settings.buffer.length.minutes", 2)).tag(2)
                Text(L("settings.buffer.length.minutes", 3)).tag(3)
                Text(L("settings.buffer.length.minutes", 5)).tag(5)
            }
            .tip(L("settings.buffer.length.tip"))
            Picker(L("settings.buffer.frameRate"), selection: $settings.framesPerSecond) {
                Text(L("settings.buffer.frameRate.lightest", 15)).tag(15)
                Text(L("settings.buffer.frameRate.fps", 30)).tag(30)
                Text(L("settings.buffer.frameRate.fps", 60)).tag(60)
            }
            .tip(L("settings.buffer.frameRate.tip"))
            Picker(L("settings.buffer.recordingFrameRate"), selection: $settings.recordingFramesPerSecond) {
                Text(L("settings.buffer.frameRate.fps", 30)).tag(30)
                Text(L("settings.buffer.frameRate.fps", 60)).tag(60)
            }
            .tip(L("settings.buffer.recordingFrameRate.tip"))
            Picker(L("settings.buffer.resolution"), selection: $settings.maxHeight) {
                Text("720p").tag(720)
                Text("1080p").tag(1080)
                Text("1440p").tag(1440)
                Text(L("settings.buffer.resolution.native")).tag(0)
            }
            .tip(L("settings.buffer.resolution.tip"))
            Toggle(L("settings.buffer.allDisplays"), isOn: $settings.captureAllDisplays)
                .tip(L("settings.buffer.allDisplays.tip"))
            Toggle(L("settings.buffer.pointer"), isOn: $settings.showsCursor)
                .tip(L("settings.buffer.pointer.tip"))
            Toggle(L("settings.buffer.startOnLaunch"), isOn: $settings.startBufferOnLaunch)
                .tip(L("settings.buffer.startOnLaunch.tip", AppInfo.name))
            if needsRestart {
                HStack {
                    Text(L("settings.buffer.restart.note"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button(L("settings.buffer.restart")) {
                        needsRestart = false
                        Task { await app.restartBufferIfRunning() }
                    }
                    .tip(L("settings.buffer.restart.tip"))
                }
            }
        }

        Section(L("settings.audio.section")) {
            Toggle(L("settings.audio.system"), isOn: $settings.recordSystemAudio)
                .tip(L("settings.audio.system.tip"))
            Toggle(L("settings.audio.microphone"), isOn: $settings.recordMicrophone)
                .tip(L("settings.audio.microphone.tip"))
        }

        Section(L("settings.input.section")) {
            Toggle(L("settings.input.clicks"), isOn: $settings.recordClicks)
                .tip(L("settings.input.clicks.tip"))
            Toggle(L("settings.input.keys"), isOn: $settings.recordKeys)
                .tip(L("settings.input.keys.tip"))
            if settings.recordKeys && !app.hasAccessibilityAccess {
                HStack {
                    Text(L("settings.input.keys.needsAccess"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warning)
                    Spacer()
                    Button(L("settings.input.keys.grant")) { app.requestAccessibilityAccess() }
                        .tip(L("settings.input.keys.grant.tip"))
                }
            }
            TypedTextChoice(isOn: $settings.recordTypedText)
        }
    }

    @ViewBuilder private var reportsPage: some View {
        @Bindable var settings = app.settings
        ReportSettingsSection()

        Section(L("settings.environment.section")) {
            Toggle(L("settings.environment.browserURL"), isOn: $settings.readBrowserURL)
                .tip(L("settings.environment.browserURL.tip"))
            Text(L("settings.environment.browserURL.note"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }

        Section(L("settings.crashes.section")) {
            Toggle(L("settings.crashes.saveClip"), isOn: $settings.saveOnCrash)
                .tip(L("settings.crashes.saveClip.tip"))
            Text(L("settings.crashes.saveClip.note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Toggle(L("settings.crashes.systemLog"), isOn: $settings.attachSystemLogs)
                .tip(L("settings.crashes.systemLog.tip"))
        }
    }

    @ViewBuilder private var updatesPage: some View {
        @Bindable var settings = app.settings
        UpdateSettingsSection()

        Section(L("settings.feedback.section")) {
            HStack {
                Button(L("settings.feedback.problem")) { WindowManager.shared.openFeedback(kind: .problem) }
                    .tip(L("settings.feedback.problem.tip", AppInfo.name))
                Button(L("settings.feedback.feature")) { WindowManager.shared.openFeedback(kind: .idea) }
                    .tip(L("settings.feedback.feature.tip", AppInfo.name))
            }
            Toggle(L("settings.feedback.offerCrashReport", AppInfo.name), isOn: $settings.offerCrashReports)
                .tip(L("settings.feedback.offerCrashReport.tip", AppInfo.name))
            Text(L("settings.feedback.note"))
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
            app.statusMessage = L("settings.general.openAtLogin.error")
        }
    }
}

/// The person's choice to show what they type in steps, with what it means. Used in the welcome
/// guide and in Settings.
struct TypedTextChoice: View {
    @Binding var isOn: Bool

    private var explanation: String {
        if isOn {
            return L("settings.typedText.on")
        }
        return L("settings.typedText.off")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(L("settings.typedText.toggle"), isOn: $isOn)
                .tip(L("settings.typedText.toggle.tip"))
            // Verbatim: as a localized string the example address turned into a mail link.
            Text(verbatim: explanation)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
