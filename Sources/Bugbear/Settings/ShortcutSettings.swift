import AppKit
import SwiftUI

/// Settings → Shortcuts: click a shortcut, press the new keys. Esc cancels, Delete removes it.
struct ShortcutSettingsSection: View {
    @State private var hotKeys = HotKeySettings.shared
    @State private var recording: HotKeyAction?
    @State private var problem: String?
    @State private var monitor: Any?

    var body: some View {
        Section(L("settings.shortcuts.section")) {
            ForEach(HotKeyAction.allCases) { action in
                HStack {
                    Text(action.title)
                    Spacer()
                    Button {
                        startRecording(action)
                    } label: {
                        Text(label(for: action))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(minWidth: 96)
                    }
                    .accessibilityLabel(L("settings.shortcuts.row.label", action.title, label(for: action)))
                    .tip(L("settings.shortcuts.row.tip"))
                }
            }
            if let message = problem {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.warning)
            }
            HStack {
                Text(L("settings.shortcuts.note"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(L("settings.shortcuts.reset")) {
                    stopRecording()
                    hotKeys.resetAll()
                    problem = nil
                }
                .disabled(!hotKeys.isCustomized)
                .tip(L("settings.shortcuts.reset.tip"))
            }
        }
        .onDisappear { stopRecording() }
    }

    private func label(for action: HotKeyAction) -> String {
        if recording == action {
            return L("settings.shortcuts.recording")
        }
        let text = hotKeys.text(for: action)
        if text.isEmpty {
            return L("settings.shortcuts.none")
        }
        return text
    }

    private func startRecording(_ action: HotKeyAction) {
        stopRecording()
        recording = action
        problem = nil
        // While recording, the global shortcuts would swallow the keys we want to read.
        HotKeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            MainActor.assumeIsolated {
                handle(event, for: action)
            }
            return nil
        }
    }

    private func handle(_ event: NSEvent, for action: HotKeyAction) {
        if event.keyCode == 53 {
            stopRecording()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            stopRecording()
            hotKeys.set(nil, for: action)
            return
        }
        guard let shortcut = Shortcut.from(event) else {
            problem = L("settings.shortcuts.error.noModifier")
            return
        }
        if let owner = hotKeys.owner(of: shortcut, except: action) {
            problem = L("settings.shortcuts.error.taken", shortcut.display, owner.title)
            return
        }
        stopRecording()
        hotKeys.set(shortcut, for: action)
    }

    private func stopRecording() {
        if let active = monitor {
            NSEvent.removeMonitor(active)
        }
        monitor = nil
        if recording != nil {
            recording = nil
            AppState.shared.registerHotKeys()
        }
    }
}
