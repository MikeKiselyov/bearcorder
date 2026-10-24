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
                    Text("QA Helper").font(.system(size: 16, weight: .bold))
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
                    Picker("Frame rate", selection: $settings.framesPerSecond) {
                        Text("15 fps").tag(15)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    Picker("Resolution", selection: $settings.maxHeight) {
                        Text("720p").tag(720)
                        Text("1080p").tag(1080)
                        Text("1440p").tag(1440)
                        Text("Native").tag(0)
                    }
                    Toggle("Record all displays (side by side)", isOn: $settings.captureAllDisplays)
                    Toggle("Show the mouse pointer", isOn: $settings.showsCursor)
                    Toggle("Start the buffer when the app opens", isOn: $settings.startBufferOnLaunch)
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
                        }
                    }
                }

                ReportSettingsSection()

                StorageSettingsSection()

                UpdateSettingsSection()

                Section("Crashes and logs") {
                    Toggle("Save a clip when an app crashes", isOn: $settings.saveOnCrash)
                    Text("When an app you used in the last 10 minutes crashes, the minute before the crash is saved to Recent with the crash report.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Toggle("Attach the app's system log to clips", isOn: $settings.attachSystemLogs)
                }

                Section("Audio") {
                    Toggle("Record system audio", isOn: $settings.recordSystemAudio)
                    Toggle("Record microphone", isOn: $settings.recordMicrophone)
                }

                Section("Clicks and keys") {
                    Toggle("Record clicks", isOn: $settings.recordClicks)
                    Toggle("Record shortcut keys", isOn: $settings.recordKeys)
                    if settings.recordKeys && !app.hasAccessibilityAccess {
                        HStack {
                            Text("Needs Accessibility access")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.warning)
                            Spacer()
                            Button("Grant") { app.requestAccessibilityAccess() }
                        }
                    }
                    Text("Plain typing is never stored as text, only as “typing…”.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                Section("Environment") {
                    Toggle("Read the browser tab URL", isOn: $settings.readBrowserURL)
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
                    }
                }

                Section("General") {
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            setLaunchAtLogin(enabled)
                        }
                    HStack {
                        Text("Welcome guide")
                        Spacer()
                        Button("Show…") { WindowManager.shared.openOnboarding() }
                    }
                    HStack {
                        Text("Permissions")
                        Spacer()
                        Button("Screen Recording…") { app.requestScreenRecordingAccess() }
                        Button("Accessibility…") { app.requestAccessibilityAccess() }
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
