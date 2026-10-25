import AppKit
import SwiftUI

/// Settings → Shortcuts: click a shortcut, press the new keys. Esc cancels, Delete removes it.
struct ShortcutSettingsSection: View {
    @State private var hotKeys = HotKeySettings.shared
    @State private var recording: HotKeyAction?
    @State private var problem: String?
    @State private var monitor: Any?

    var body: some View {
        Section("Shortcuts") {
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
                    .help("Click, then press the new keys. Esc cancels, Delete removes the shortcut.")
                }
            }
            if let message = problem {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.warning)
            }
            HStack {
                Text("Shortcuts need ⌘, ⌥ or ⌃ so they don't get in the way of typing.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Reset to defaults") {
                    stopRecording()
                    hotKeys.resetAll()
                    problem = nil
                }
                .disabled(!hotKeys.isCustomized)
                .help("Restore every shortcut to its default keys")
            }
        }
        .onDisappear { stopRecording() }
    }

    private func label(for action: HotKeyAction) -> String {
        if recording == action {
            return "Press keys…"
        }
        let text = hotKeys.text(for: action)
        if text.isEmpty {
            return "None"
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
            problem = "Add ⌘, ⌥ or ⌃ to the key."
            return
        }
        if let owner = hotKeys.owner(of: shortcut, except: action) {
            problem = "\(shortcut.display) is already \"\(owner.title)\". Pick another or change that one first."
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
