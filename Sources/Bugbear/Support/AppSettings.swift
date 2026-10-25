import Foundation
import BugbearCore
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var bufferMinutes: Int {
        didSet { defaults.set(bufferMinutes, forKey: "bufferMinutes") }
    }
    /// Frames per second of the always-on buffer. 15 is plenty to see a bug and costs half of 30.
    var framesPerSecond: Int {
        didSet { defaults.set(framesPerSecond, forKey: "framesPerSecond") }
    }
    /// Frames per second while recording on purpose (⌥⇧6); the buffer switches up for it.
    var recordingFramesPerSecond: Int {
        didSet { defaults.set(recordingFramesPerSecond, forKey: "recordingFramesPerSecond") }
    }
    /// Maximum output height in pixels; 0 keeps the display's native size.
    var maxHeight: Int {
        didSet { defaults.set(maxHeight, forKey: "maxHeight") }
    }
    var showsCursor: Bool {
        didSet { defaults.set(showsCursor, forKey: "showsCursor") }
    }
    var recordClicks: Bool {
        didSet { defaults.set(recordClicks, forKey: "recordClicks") }
    }
    var recordKeys: Bool {
        didSet { defaults.set(recordKeys, forKey: "recordKeys") }
    }
    var readBrowserURL: Bool {
        didSet { defaults.set(readBrowserURL, forKey: "readBrowserURL") }
    }
    /// A new screenshot goes to the clipboard right away, ready for ⌘V.
    var copyScreenshots: Bool {
        didSet { defaults.set(copyScreenshots, forKey: "copyScreenshots") }
    }
    var startBufferOnLaunch: Bool {
        didSet { defaults.set(startBufferOnLaunch, forKey: "startBufferOnLaunch") }
    }
    var outputFolderPath: String {
        didSet { defaults.set(outputFolderPath, forKey: "outputFolderPath") }
    }
    var timeZones: [String] {
        didSet { defaults.set(timeZones, forKey: "timeZones") }
    }
    /// Record every connected display (clips are placed side by side).
    var captureAllDisplays: Bool {
        didSet { defaults.set(captureAllDisplays, forKey: "captureAllDisplays") }
    }
    var recordSystemAudio: Bool {
        didSet { defaults.set(recordSystemAudio, forKey: "recordSystemAudio") }
    }
    var recordMicrophone: Bool {
        didSet { defaults.set(recordMicrophone, forKey: "recordMicrophone") }
    }
    var cameraBubbleSize: Double {
        didSet { defaults.set(cameraBubbleSize, forKey: "cameraBubbleSize") }
    }
    /// Markdown or Jira wiki for "Copy bug report"; the last one picked.
    var bugReportFormat: String {
        didSet { defaults.set(bugReportFormat, forKey: "bugReportFormat") }
    }
    /// Fields added to every capture's environment, report and badge (Stand, Build, Test account…).
    var reportFields: [EnvironmentSnapshot.Field] {
        didSet {
            if let data = try? JSONEncoder().encode(reportFields) {
                defaults.set(data, forKey: "reportFields")
            }
        }
    }
    /// Delete captures older than this many days; 0 keeps them forever.
    var keepCapturesDays: Int {
        didSet { defaults.set(keepCapturesDays, forKey: "keepCapturesDays") }
    }
    /// Keep all captures under this many GB, deleting the oldest; 0 for no limit.
    var maxCapturesGB: Int {
        didSet { defaults.set(maxCapturesGB, forKey: "maxCapturesGB") }
    }
    /// Look for new commits in the GitHub repository this copy was built from.
    var checkForUpdates: Bool {
        didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") }
    }
    /// Save the recorded app's system log next to each clip.
    var attachSystemLogs: Bool {
        didSet { defaults.set(attachSystemLogs, forKey: "attachSystemLogs") }
    }
    /// Save the last minute automatically when an app you worked with crashes.
    var saveOnCrash: Bool {
        didSet { defaults.set(saveOnCrash, forKey: "saveOnCrash") }
    }

    private init() {
        defaults.register(defaults: [
            "bufferMinutes": 3,
            "framesPerSecond": 15,
            "recordingFramesPerSecond": 30,
            "maxHeight": 1080,
            "showsCursor": true,
            "recordClicks": true,
            "recordKeys": true,
            "readBrowserURL": true,
            "copyScreenshots": true,
            "startBufferOnLaunch": true,
            "outputFolderPath": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Bugbear").path,
            "timeZones": ["UTC", "Europe/Lisbon", "Europe/Minsk", "America/New_York", "Asia/Tokyo"],
            "captureAllDisplays": true,
            "recordSystemAudio": false,
            "recordMicrophone": false,
            "cameraBubbleSize": 200.0,
            "saveOnCrash": true,
            "attachSystemLogs": true,
            "checkForUpdates": true,
            "bugReportFormat": BugReport.Format.markdown.rawValue,
            "keepCapturesDays": 0,
            "maxCapturesGB": 0,
        ])
        bufferMinutes = defaults.integer(forKey: "bufferMinutes")
        framesPerSecond = defaults.integer(forKey: "framesPerSecond")
        recordingFramesPerSecond = defaults.integer(forKey: "recordingFramesPerSecond")
        maxHeight = defaults.integer(forKey: "maxHeight")
        showsCursor = defaults.bool(forKey: "showsCursor")
        recordClicks = defaults.bool(forKey: "recordClicks")
        recordKeys = defaults.bool(forKey: "recordKeys")
        readBrowserURL = defaults.bool(forKey: "readBrowserURL")
        copyScreenshots = defaults.bool(forKey: "copyScreenshots")
        startBufferOnLaunch = defaults.bool(forKey: "startBufferOnLaunch")
        outputFolderPath = defaults.string(forKey: "outputFolderPath") ?? NSHomeDirectory()
        timeZones = defaults.stringArray(forKey: "timeZones") ?? []
        captureAllDisplays = defaults.bool(forKey: "captureAllDisplays")
        recordSystemAudio = defaults.bool(forKey: "recordSystemAudio")
        recordMicrophone = defaults.bool(forKey: "recordMicrophone")
        cameraBubbleSize = defaults.double(forKey: "cameraBubbleSize")
        saveOnCrash = defaults.bool(forKey: "saveOnCrash")
        attachSystemLogs = defaults.bool(forKey: "attachSystemLogs")
        checkForUpdates = defaults.bool(forKey: "checkForUpdates")
        bugReportFormat = defaults.string(forKey: "bugReportFormat") ?? BugReport.Format.markdown.rawValue
        keepCapturesDays = defaults.integer(forKey: "keepCapturesDays")
        maxCapturesGB = defaults.integer(forKey: "maxCapturesGB")
        reportFields = []
        if let data = defaults.data(forKey: "reportFields"), let fields = try? JSONDecoder().decode([EnvironmentSnapshot.Field].self, from: data) {
            reportFields = fields
        }
    }

    /// Where saved files go. The default Desktop/Bugbear folder is made on first use.
    var outputFolder: URL {
        let folder = URL(fileURLWithPath: outputFolderPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    var bufferSeconds: Double {
        return Double(bufferMinutes * 60)
    }

    var qualityLabel: String {
        if maxHeight == 0 { return "Native" }
        return "\(maxHeight)p"
    }
}

enum AppPaths {
    /// Set by `--readme-media` so the demo captures never mix with real ones.
    nonisolated(unsafe) static var supportOverride: URL?

    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var folder = base.appendingPathComponent("Bugbear", isDirectory: true)
        if let override = supportOverride {
            folder = override
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var buffer: URL {
        let folder = support.appendingPathComponent("Buffer", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var captures: URL {
        let folder = support.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var temporary: URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Bugbear", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// "Bugbear 2026-10-24 at 13.58.12"
    static func exportName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Bugbear \(formatter.string(from: date))"
    }

    /// Returns a URL in `folder` that does not exist yet.
    static func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
