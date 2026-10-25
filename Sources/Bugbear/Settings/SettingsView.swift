import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsRestart = false

    var body: some View {
        @Bindable var settings = app.settings
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LogoView(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bugbear").font(.system(size: 16, weight: .bold))
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 40)
            .padding(.bottom, 12)

            Form {
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
                        .tip("Start keeping the recent screen as soon as Bugbear launches")
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

                ReportSettingsSection()

                StorageSettingsSection()

                UpdateSettingsSection()

                Section("Feedback") {
                    HStack {
                        Button("Report a problem…") { WindowManager.shared.openFeedback(kind: .problem) }
                            .tip("Open a GitHub issue about Bugbear with the version, macOS and logs filled in")
                        Button("Suggest a feature…") { WindowManager.shared.openFeedback(kind: .idea) }
                            .tip("Share an idea for Bugbear as a GitHub issue")
                    }
                    Toggle("Offer a report after Bugbear crashes", isOn: $settings.offerCrashReports)
                        .tip("When Bugbear quit unexpectedly, open a report with the crash details on the next launch")
                    Text("Opens a filled issue on GitHub. You check it and submit it from your account.")
                        .font(.system(size: 12))
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
                    Text("Plain typing is never stored as text, only as “typing…”.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                Section("Screenshots") {
                    Toggle("Copy a new screenshot to the clipboard", isOn: $settings.copyScreenshots)
                        .tip("Put every new screenshot on the clipboard so you can paste it right away")
                    Text("Paste it with ⌘V right away; the editor opens too, and ⌘C there copies your marks.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                Section("Environment") {
                    Toggle("Read the browser tab URL", isOn: $settings.readBrowserURL)
                        .tip("Add the current browser tab URL to the environment info of captures")
                    Text("Safari, Chrome, Arc, Brave, Edge, Vivaldi and Opera. macOS asks once per browser.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
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

                Section("General") {
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .tip("Start Bugbear automatically when you log in to your Mac")
                        .onChange(of: launchAtLogin) { _, enabled in
                            setLaunchAtLogin(enabled)
                        }
                    HStack {
                        Text("Welcome guide")
                        Spacer()
                        Button("Show…") { WindowManager.shared.openOnboarding() }
                            .tip("Open the welcome guide again")
                    }
                    HStack {
                        Text("Permissions")
                        Spacer()
                        Button("Screen Recording…") { app.requestScreenRecordingAccess() }
                            .tip("Ask macOS for Screen Recording access, needed for screenshots and the buffer")
                        Button("Accessibility…") { app.requestAccessibilityAccess() }
                            .tip("Ask macOS for Accessibility access, needed for shortcut keys and window tools")
                    }
                }

                ShortcutSettingsSection()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.window)
        .onChange(of: settings.bufferMinutes) { needsRestart = true }
        .onChange(of: settings.framesPerSecond) { needsRestart = true }
        .onChange(of: settings.maxHeight) { needsRestart = true }
        .onChange(of: settings.captureAllDisplays) { needsRestart = true }
        .onChange(of: settings.showsCursor) { needsRestart = true }
        .onChange(of: settings.recordSystemAudio) { needsRestart = true }
        .onChange(of: settings.recordMicrophone) { needsRestart = true }
        .onChange(of: settings.recordClicks) { needsRestart = true }
        .onChange(of: settings.recordKeys) { needsRestart = true }
        .onChange(of: settings.saveOnCrash) { app.updateCrashWatcher() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = app.settings.outputFolder
        if panel.runModal() == .OK, let url = panel.url {
            app.settings.outputFolderPath = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            app.statusMessage = "Open at login works when the app is in /Applications (scripts/build-app.sh --install)."
        }
    }
}
