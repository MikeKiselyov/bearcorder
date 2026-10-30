import Foundation
import AppCore
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private let home: URL

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
    /// Steps show what was typed into a field ("Type "john@test.com" in "Email" text field").
    /// Off unless the person turns it on: typed text can be personal. Never for password fields.
    var recordTypedText: Bool {
        didSet { defaults.set(recordTypedText, forKey: "recordTypedText") }
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
            do {
                defaults.set(try JSONEncoder().encode(reportFields), forKey: "reportFields")
            } catch {
                Log.error("settings: could not save the report fields: \(error)")
            }
        }
    }
    /// Fields the app collects by itself that the tester turned off (`StandardField` raw values).
    var hiddenEnvironmentFields: [String] {
        didSet { defaults.set(hiddenEnvironmentFields, forKey: "hiddenEnvironmentFields") }
    }
    /// The tester's own names for fields the app collects, by `StandardField` raw value.
    var renamedEnvironmentFields: [String: String] {
        didSet { defaults.set(renamedEnvironmentFields, forKey: "renamedEnvironmentFields") }
    }
    /// Delete captures older than this many days; 0 keeps them forever.
    var keepCapturesDays: Int {
        didSet { defaults.set(keepCapturesDays, forKey: "keepCapturesDays") }
    }
    /// Clips saved by themselves when an app crashed are deleted after this many days; 0 keeps them.
    var keepCrashClipsDays: Int {
        didSet { defaults.set(keepCrashClipsDays, forKey: "keepCrashClipsDays") }
    }
    /// After the app crashes, offer a report about it on the next launch.
    var offerCrashReports: Bool {
        didSet { defaults.set(offerCrashReports, forKey: "offerCrashReports") }
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

    /// Folders (below the home folder, stored relative to it) searched for projects in Space.
    var projectRoots: [String] {
        didSet {
            let cleaned = AppSettings.projectRootsInsideHome(projectRoots, home: home)
            if cleaned != projectRoots {
                projectRoots = cleaned
                return
            }
            defaults.set(projectRoots, forKey: "projectRoots")
        }
    }
    /// A project not touched for this many days counts as old (1 to 365).
    var oldProjectDays: Int {
        didSet {
            let clamped = min(max(oldProjectDays, 1), 365)
            if clamped != oldProjectDays {
                oldProjectDays = clamped
                return
            }
            defaults.set(oldProjectDays, forKey: "oldProjectDays")
        }
    }
    /// Project folders removed from Space go to the Trash instead of being deleted at once.
    var projectFoldersToTrash: Bool {
        didSet { defaults.set(projectFoldersToTrash, forKey: "projectFoldersToTrash") }
    }
    /// The kinds of dependency and build folders Space looks for in projects.
    var dependencyKinds: Set<DependencyKind> {
        didSet { defaults.set(dependencyKinds.map { $0.rawValue }.sorted(), forKey: "dependencyKinds") }
    }
    /// Ids of the extra cache rows hidden in Space; empty shows all of them.
    var hiddenCacheRows: Set<String> {
        didSet { defaults.set(hiddenCacheRows.sorted(), forKey: "hiddenCacheRows") }
    }

    /// The usual project folders that exist in this home folder, relative to it.
    static func defaultProjectRoots(home: URL) -> [String] {
        let names = ["Projects", "Developer", "Cursor", "Code", "src", "Documents", "Desktop"]
        var existing: [String] = []
        for name in names {
            var isFolder: ObjCBool = false
            let path = home.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue {
                existing.append(name)
            }
        }
        return existing
    }

    /// Keeps only folders inside home, as paths relative to it. An absolute path inside home is made
    /// relative; anything outside home, home itself, paths with `..` and anything in ~/Library
    /// (app data, iCloud Drive, cloud storage) are dropped.
    static func projectRootsInsideHome(_ paths: [String], home: URL) -> [String] {
        let homePath = home.standardizedFileURL.path
        var result: [String] = []
        for path in paths {
            var relative = path
            if path.hasPrefix("/") {
                let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
                if !standardized.hasPrefix(homePath + "/") { continue }
                relative = String(standardized.dropFirst(homePath.count + 1))
            }
            let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
            if parts.isEmpty || parts.contains("..") || parts.contains(".") { continue }
            // In any case: ~/library is the same folder on a case-insensitive disk.
            if parts[0].lowercased() == "library" { continue }
            let joined = parts.joined(separator: "/")
            if !result.contains(joined) { result.append(joined) }
        }
        return result
    }

    init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        self.home = home
        defaults.register(defaults: [
            "bufferMinutes": 3,
            "framesPerSecond": 15,
            "recordingFramesPerSecond": 30,
            "maxHeight": 1080,
            "showsCursor": true,
            "recordClicks": true,
            "recordKeys": true,
            "readBrowserURL": true,
            "recordTypedText": false,
            "copyScreenshots": true,
            "startBufferOnLaunch": true,
            "outputFolderPath": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/\(AppInfo.name)").path,
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
            "keepCrashClipsDays": 7,
            "offerCrashReports": true,
            "maxCapturesGB": 0,
            "projectRoots": AppSettings.defaultProjectRoots(home: home),
            "oldProjectDays": 30,
            "projectFoldersToTrash": true,
            "dependencyKinds": DependencyKind.allCases.map { $0.rawValue },
            "hiddenCacheRows": [String](),
        ])
        bufferMinutes = defaults.integer(forKey: "bufferMinutes")
        framesPerSecond = defaults.integer(forKey: "framesPerSecond")
        recordingFramesPerSecond = defaults.integer(forKey: "recordingFramesPerSecond")
        maxHeight = defaults.integer(forKey: "maxHeight")
        showsCursor = defaults.bool(forKey: "showsCursor")
        recordClicks = defaults.bool(forKey: "recordClicks")
        recordKeys = defaults.bool(forKey: "recordKeys")
        readBrowserURL = defaults.bool(forKey: "readBrowserURL")
        recordTypedText = defaults.bool(forKey: "recordTypedText")
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
        AppSettings.keepCrashClipsForEarlierUsers(defaults, domain: Bundle.main.bundleIdentifier ?? "")
        keepCrashClipsDays = defaults.integer(forKey: "keepCrashClipsDays")
        offerCrashReports = defaults.bool(forKey: "offerCrashReports")
        projectRoots = AppSettings.projectRootsInsideHome(defaults.stringArray(forKey: "projectRoots") ?? [], home: home)
        oldProjectDays = min(max(defaults.integer(forKey: "oldProjectDays"), 1), 365)
        projectFoldersToTrash = defaults.bool(forKey: "projectFoldersToTrash")
        var savedKinds: Set<DependencyKind> = []
        for rawValue in defaults.stringArray(forKey: "dependencyKinds") ?? [] {
            if let kind = DependencyKind(rawValue: rawValue) { savedKinds.insert(kind) }
        }
        dependencyKinds = savedKinds
        hiddenCacheRows = Set(defaults.stringArray(forKey: "hiddenCacheRows") ?? [])
        reportFields = []
        if let data = defaults.data(forKey: "reportFields") {
            do {
                reportFields = try JSONDecoder().decode([EnvironmentSnapshot.Field].self, from: data)
            } catch {
                Log.error("settings: could not read the report fields, using none: \(error)")
            }
        }
        hiddenEnvironmentFields = defaults.stringArray(forKey: "hiddenEnvironmentFields") ?? []
        renamedEnvironmentFields = defaults.dictionary(forKey: "renamedEnvironmentFields") as? [String: String] ?? [:]
    }

    /// The release that added the crash clip setting (0.9.0).
    static let crashClipSettingReleaseID = 14

    /// People who used the app before the crash clip setting existed keep all their crash clips until
    /// they choose otherwise; everyone else keeps the time picked in the welcome guide (7 days by
    /// default). An earlier user is one whose last seen release is older than the setting: a value
    /// the person never changed is not saved, so "not saved" alone also matches everyone who left
    /// the guide's 7 days as they were. `object(forKey:)` would also return the registered default.
    static func keepCrashClipsForEarlierUsers(_ defaults: UserDefaults, domain: String) {
        if domain.isEmpty { return }
        let saved = defaults.persistentDomain(forName: domain) ?? [:]
        if saved["keepCrashClipsDays"] != nil { return }
        let lastSeenRelease = defaults.integer(forKey: "whatsNewLastSeenID")
        if lastSeenRelease == 0 || lastSeenRelease >= crashClipSettingReleaseID { return }
        if defaults.bool(forKey: "onboardingCompleted") {
            defaults.set(0, forKey: "keepCrashClipsDays")
        }
    }

    /// Where saved files go. The default Desktop/<app name> folder is made on first use.
    var outputFolder: URL {
        let folder = URL(fileURLWithPath: outputFolderPath, isDirectory: true)
        AppPaths.ensureFolder(folder)
        return folder
    }

    var bufferSeconds: Double {
        return Double(bufferMinutes * 60)
    }

    var qualityLabel: String {
        if maxHeight == 0 { return L("settings.buffer.resolution.native") }
        return "\(maxHeight)p"
    }
}

enum AppPaths {
    /// Makes the folder when it is missing; a failure is logged, the caller goes on.
    static func ensureFolder(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            Log.error("paths: could not create \(url.path): \(error)")
        }
    }

    /// Set by `--readme-media` so the demo captures never mix with real ones.
    nonisolated(unsafe) static var supportOverride: URL?

    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var folder = base.appendingPathComponent(AppInfo.name, isDirectory: true)
        if let override = supportOverride {
            folder = override
        }
        AppPaths.ensureFolder(folder)
        return folder
    }

    static var buffer: URL {
        let folder = support.appendingPathComponent("Buffer", isDirectory: true)
        AppPaths.ensureFolder(folder)
        return folder
    }

    static var captures: URL {
        let folder = support.appendingPathComponent("Captures", isDirectory: true)
        AppPaths.ensureFolder(folder)
        return folder
    }

    static var temporary: URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(AppInfo.name, isDirectory: true)
        AppPaths.ensureFolder(folder)
        return folder
    }

    /// "<app name> 2026-10-24 at 13.58.12"
    static func exportName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(AppInfo.name) \(formatter.string(from: date))"
    }

    /// Returns a URL in `folder` that does not exist yet.
    static func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        AppPaths.ensureFolder(folder)
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
