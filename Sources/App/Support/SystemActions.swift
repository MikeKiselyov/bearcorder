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

    /// Allow… for Screen Recording or Accessibility. macOS shows its own window with Open System
    /// Settings only the first time an app asks, so the first press only asks and later presses
    /// open System Settings: both at once put two windows on the screen. `askedBefore` is for what
    /// asked before this button kept count (the buffer asks for the screen once the guide is done),
    /// so that press is not spent on a window macOS no longer shows.
    static func askOnceThenOpenSettings(_ name: String, pane: String, askedBefore: Bool = false, defaults: UserDefaults = .standard, prompt: () -> Void) {
        let key = "askedPermission.\(pane)"
        if !askedBefore && !defaults.bool(forKey: key) {
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
