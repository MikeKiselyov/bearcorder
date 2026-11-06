import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// What the app hands to macOS: System Settings pages, files in Finder or their app, the login
/// item, the folder chooser. Tests switch on recording and read what a button would have opened,
/// so they press every button without opening System Settings or a dialog on the person's Mac.
@MainActor
enum SystemActions {
    static var isRecording = false
    private(set) static var recorded: [String] = []
    /// What the file chooser "picks" while recording.
    static var chosenFiles: [URL] = []

    static func startRecording() {
        isRecording = true
        recorded = []
    }

    static func stopRecording() {
        isRecording = false
        recorded = []
        chosenFiles = []
    }

    /// Something that would run for real (an update, a check on GitHub): while recording it is only
    /// noted, and the caller stops. True when the caller should stop.
    static func recordInstead(_ action: String) -> Bool {
        if isRecording {
            recorded.append(action)
            return true
        }
        return false
    }

    /// A System Settings page, a file or a folder.
    static func open(_ url: URL) {
        if isRecording {
            recorded.append("open \(url.isFileURL ? url.path : url.absoluteString)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Shows files selected in Finder.
    static func reveal(_ urls: [URL]) {
        if isRecording {
            var paths: [String] = []
            for url in urls {
                paths.append(url.path)
            }
            recorded.append("reveal \(paths.joined(separator: ","))")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Moves a file to the Trash; while recording the file stays where it is.
    static func trash(_ url: URL) throws {
        if isRecording {
            recorded.append("trash \(url.path)")
            return
        }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// "Not in the list?" next to Screen Recording: Allow… asked macOS and there is still no access,
    /// so the app may be missing from the list to switch on.
    /// Views read the flag through @AppStorage(askedScreenRecordingKey), so the row appears as soon as Allow… sets it.
    static func offersScreenRecordingFix(hasAccess: Bool, asked: Bool) -> Bool {
        return asked && !hasAccess
    }

    static let askedScreenRecordingKey = "askedPermission.Privacy_ScreenCapture"

    /// Fix for "Not in the list?". macOS's Screen Recording window comes from universalAccessAuthWarn,
    /// which keeps the bundle id it once saw at the app's path: after a copy with another id sat
    /// there, it files the request under the old id and the app never shows up in the list. Quitting
    /// it is safe (macOS starts it again for the next window); macOS is asked again once it is gone,
    /// so the new window does not go to the old process.
    static func fixScreenRecordingList(prompt: @escaping @MainActor () -> Void) {
        if recordInstead("restart permission alert") {
            askPermission("Screen Recording", prompt: prompt)
            return
        }
        Task.detached {
            run("/usr/bin/killall", ["universalAccessAuthWarn"])
            for _ in 0..<20 {
                if run("/usr/bin/pgrep", ["-x", "universalAccessAuthWarn"]) != 0 {
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            await MainActor.run {
                askPermission("Screen Recording", prompt: prompt)
            }
        }
    }

    /// Runs a tool and returns its exit status (-1 when it did not start).
    nonisolated private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) == nil {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Allow… for Screen Recording or Accessibility. macOS shows its own window with Open System
    /// Settings only the first time an app asks, so the first press only asks and later presses
    /// open System Settings: both at once put two windows on the screen.
    static func askOnceThenOpenSettings(_ name: String, pane: String, defaults: UserDefaults = .standard, prompt: () -> Void) {
        let key = "askedPermission.\(pane)"
        if !defaults.bool(forKey: key) {
            defaults.set(true, forKey: key)
            askPermission(name, prompt: prompt)
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            open(url)
        }
    }

    /// macOS's own prompt for a permission, e.g. Screen Recording.
    static func askPermission(_ name: String, prompt: () -> Void) {
        if isRecording {
            recorded.append("ask \(name)")
            return
        }
        prompt()
    }

    /// Opening at login; throws when macOS refuses (an app outside /Applications).
    static func setOpenAtLogin(_ enabled: Bool) throws {
        if isRecording {
            recorded.append("login \(enabled)")
            return
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// The folder chooser; nil when cancelled.
    static func chooseFolder(startingAt folder: URL, prompt: String? = nil) -> URL? {
        if isRecording {
            recorded.append("choose folder \(folder.path)")
            return nil
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        if let text = prompt {
            panel.prompt = text
        }
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }

    /// Where to save a new file; nil when cancelled. While recording, the first of `chosenFiles`.
    static func chooseSaveLocation(name: String, type: UTType, startingAt folder: URL? = nil) -> URL? {
        if isRecording {
            recorded.append("choose save \(name)")
            return chosenFiles.first
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.directoryURL = folder
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }

    /// Pictures from the file chooser; empty when cancelled. While recording, `chosenFiles`.
    static func chooseImages(message: String, multiple: Bool, startingAt folder: URL?, types: [UTType] = [.image]) -> [URL] {
        if isRecording {
            recorded.append("choose images")
            if multiple {
                return chosenFiles
            }
            return Array(chosenFiles.prefix(1))
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = multiple
        panel.message = message
        panel.directoryURL = folder
        if panel.runModal() == .OK {
            return panel.urls
        }
        return []
    }
}
