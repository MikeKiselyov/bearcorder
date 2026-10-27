import AVFoundation
import AppKit
import BugbearCore

/// Gathers what a report about Bugbear needs: version, Mac, permissions, settings and logs.
/// Everything goes through `FeedbackReport.redact`, so the home folder and user name stay private.
@MainActor
enum Feedback {
    nonisolated static let logLineCount = 80
    /// Bugbear's own crash reports newer than this go into the zip.
    nonisolated static let crashReportDays: Double = 14
    nonisolated static let lastCrashCheckKey = "feedbackLastCrashCheck"

    nonisolated static var homePath: String {
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    nonisolated static func redact(_ text: String) -> String {
        return FeedbackReport.redact(text, homePath: homePath, userName: NSUserName())
    }

    static func environment(kind: FeedbackReport.Kind) -> [EnvironmentSnapshot.Field] {
        var fields: [EnvironmentSnapshot.Field] = []
        fields.append(EnvironmentSnapshot.Field(name: AppInfo.name, value: Updater.shared.versionText))
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let build = EnvironmentCollector.sysctlString("kern.osversion")
        fields.append(EnvironmentSnapshot.Field(name: "macOS", value: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) (\(build))"))
        fields.append(EnvironmentSnapshot.Field(name: "Mac", value: EnvironmentCollector.sysctlString("hw.model")))
        if kind == .idea {
            return fields
        }
        var displays: [String] = []
        for screen in NSScreen.screens {
            let scale = screen.backingScaleFactor
            displays.append("\(Int(screen.frame.width * scale))×\(Int(screen.frame.height * scale)) @\(Int(scale))x")
        }
        fields.append(EnvironmentSnapshot.Field(name: "Displays", value: displays.joined(separator: ", ")))
        fields.append(EnvironmentSnapshot.Field(name: "Locale", value: Locale.current.identifier))
        fields.append(EnvironmentSnapshot.Field(name: "Screen recording", value: allowedText(ScreenBuffer.hasScreenRecordingAccess)))
        fields.append(EnvironmentSnapshot.Field(name: "Accessibility", value: allowedText(InputEventRecorder.hasAccessibilityAccess)))
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        fields.append(EnvironmentSnapshot.Field(name: "Microphone", value: allowedText(microphone)))
        let settings = AppSettings.shared
        let buffer = "\(bufferText(AppState.shared.bufferState)), \(settings.bufferMinutes) min, \(settings.framesPerSecond) fps, all displays: \(settings.captureAllDisplays ? "yes" : "no")"
        fields.append(EnvironmentSnapshot.Field(name: "Buffer", value: buffer))
        return fields
    }

    private static func allowedText(_ allowed: Bool) -> String {
        if allowed {
            return "allowed"
        }
        return "not allowed"
    }

    private static func bufferText(_ state: AppState.BufferState) -> String {
        switch state {
        case .off:
            return "off"
        case .starting:
            return "starting"
        case .running:
            return "running"
        case .paused:
            return "paused"
        case .needsPermission:
            return "needs permission"
        case .failed(let message):
            return "failed: \(redact(message))"
        }
    }

    /// The newest lines of bugbear.log, redacted. Reads only the end of the file.
    nonisolated static func logTail(lineCount: Int = logLineCount, from url: URL = Log.fileURL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let chunk: UInt64 = 64 * 1024
        var start: UInt64 = 0
        if size > chunk {
            start = size - chunk
        }
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            lines.append(redact(String(line)))
        }
        if start > 0 && !lines.isEmpty {
            // The first line was cut in the middle.
            lines.removeFirst()
        }
        if lines.count > lineCount {
            lines.removeFirst(lines.count - lineCount)
        }
        return lines
    }

    /// Bugbear's crash reports newer than `oldest` (two weeks back by default), newest first.
    nonisolated static func recentCrashReports(in folder: URL = CrashWatcher.defaultFolder, since oldest: Date? = nil) -> [URL] {
        var after = Date().addingTimeInterval(-crashReportDays * 24 * 3600)
        if let given = oldest {
            after = given
        }
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return [] }
        var found: [(url: URL, date: Date)] = []
        for file in files {
            if !file.lastPathComponent.hasPrefix("Bugbear") {
                continue
            }
            let date = (try? file.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            if date > after {
                found.append((url: file, date: date))
            }
        }
        found.sort { first, second in first.date > second.date }
        var result: [URL] = []
        for item in found.prefix(5) {
            result.append(item.url)
        }
        return result
    }

    enum ArchiveError: Error {
        case failed(String)
    }

    /// A zip with the redacted log, crash reports and the environment, in `folder`.
    nonisolated static func makeLogArchive(environmentText: String, in folder: URL, crashFolder: URL = CrashWatcher.defaultFolder) -> Result<URL, ArchiveError> {
        let files = FileManager.default
        let staging = files.temporaryDirectory.appendingPathComponent("bugbear-report-\(UUID().uuidString)", isDirectory: true)
        let contents = staging.appendingPathComponent("\(AppInfo.name) logs", isDirectory: true)
        defer { try? files.removeItem(at: staging) }
        do {
            try files.createDirectory(at: contents, withIntermediateDirectories: true)
            try Data((redact(environmentText) + "\n").utf8).write(to: contents.appendingPathComponent("environment.txt"))
            if let log = try? String(contentsOf: Log.fileURL, encoding: .utf8) {
                try Data(redact(log).utf8).write(to: contents.appendingPathComponent("bugbear.log"))
            }
            for crash in recentCrashReports(in: crashFolder) {
                if let text = try? String(contentsOf: crash, encoding: .utf8) {
                    try Data(scrubIdentifiers(redact(text)).utf8).write(to: contents.appendingPathComponent(crash.lastPathComponent))
                }
            }
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Log.error("Feedback: could not prepare logs: \(error.localizedDescription)")
            return .failure(.failed(error.localizedDescription))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        var archive = folder.appendingPathComponent("\(AppInfo.name) logs \(formatter.string(from: Date())).zip")
        if files.fileExists(atPath: archive.path) {
            archive = folder.appendingPathComponent("\(AppInfo.name) logs \(UUID().uuidString.prefix(8)).zip")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // No resource forks or extended attributes: they turn into ._ files outside a Mac.
        task.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", contents.path, archive.path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Log.error("Feedback: could not zip logs: \(error.localizedDescription)")
            return .failure(.failed(error.localizedDescription))
        }
        if task.terminationStatus != 0 {
            Log.error("Feedback: ditto failed with status \(task.terminationStatus)")
            try? files.removeItem(at: archive)
            return .failure(.failed("ditto status \(task.terminationStatus)"))
        }
        return .success(archive)
    }

    /// Opens the filled GitHub form; for a problem with logs, shows the zip in Finder first.
    /// Returns a warning when the form opened without the zip.
    static func send(_ report: FeedbackReport, includeLogs: Bool) async -> (opened: Bool, warning: String?) {
        guard let url = report.issueURL() else { return (opened: false, warning: nil) }
        var warning: String?
        if report.kind == .problem && includeLogs {
            let environmentText = report.environmentText
            let folder = URL(fileURLWithPath: AppSettings.shared.outputFolderPath, isDirectory: true)
            let result = await Task.detached(priority: .userInitiated) {
                return Feedback.makeLogArchive(environmentText: environmentText, in: folder)
            }.value
            switch result {
            case .success(let archive):
                SystemActions.reveal([archive])
            case .failure:
                warning = "The logs zip could not be saved to \(redact(folder.path)), so the issue opened without it."
            }
        }
        Log.info("Feedback: opening the \(report.kind.rawValue) form on GitHub")
        SystemActions.open(url)
        return (opened: true, warning: warning)
    }

    // MARK: After a crash

    /// This Bugbear's newest crash report since the last check, or nil. Reports of other Bugbear
    /// builds, hangs and kills from outside (an update, Force Quit) do not count. The first check
    /// only remembers the time, so crashes from before this feature never pop up.
    nonisolated static func crashSinceLastCheck(in folder: URL = CrashWatcher.defaultFolder, defaults: UserDefaults = .standard, bundleId: String = Bundle.main.bundleIdentifier ?? "") -> URL? {
        let now = Date()
        defer { defaults.set(now, forKey: lastCrashCheckKey) }
        guard let last = defaults.object(forKey: lastCrashCheckKey) as? Date else { return nil }
        if bundleId.isEmpty {
            return nil
        }
        for file in recentCrashReports(in: folder, since: last) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var header = text
            if let newline = text.firstIndex(of: "\n") {
                header = String(text[..<newline])
            }
            guard let crash = CrashReport.parse(headerLine: header) else { continue }
            if crash.bundleId != bundleId {
                continue
            }
            if let summary = CrashSummary.parse(reportText: text), summary.isExternalKill {
                continue
            }
            return file
        }
        return nil
    }

    /// The crash part of a report, redacted and short enough for the issue link.
    nonisolated static func crashText(from file: URL) -> String {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "" }
        var lines = ["Report: \(file.lastPathComponent)"]
        if let summary = CrashSummary.parse(reportText: text) {
            lines.append(summary.text)
        }
        return FeedbackReport.shorten(redact(lines.joined(separator: "\n")), to: 1500)
    }

    /// Ids in a crash report that tell this Mac apart; blanked in the zip.
    nonisolated static func scrubIdentifiers(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "\"(crashReporterKey|bootSessionUUID|sessionID|deviceIdentifierForVendor|userID)\"\\s*:\\s*(\"[^\"]*\"|[0-9]+)") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "\"$1\":\"<hidden>\"")
    }

    /// On launch: if Bugbear crashed last time, open a report about it with the crash filled in.
    /// Looks right away (a crash early in launch still gets offered) and off the main thread;
    /// only the window waits a moment for the menu bar. Returns whether the window opened.
    @discardableResult
    static func offerReportAfterCrash(folder: URL = CrashWatcher.defaultFolder, defaults: UserDefaults = .standard, enabled: Bool, windowDelay: Double = 2) async -> Bool {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let found = await Task.detached(priority: .utility) {
            guard let file = Feedback.crashSinceLastCheck(in: folder, defaults: defaults, bundleId: bundleId) else { return nil as (file: URL, text: String)? }
            return (file: file, text: Feedback.crashText(from: file))
        }.value
        guard let crash = found, enabled else { return false }
        Log.info("Feedback: Bugbear crashed last time (\(crash.file.lastPathComponent)), offering a report")
        try? await Task.sleep(nanoseconds: UInt64(windowDelay * 1_000_000_000))
        openCrashReport(crashText: crash.text)
        return true
    }

    /// Something failed while Bugbear kept running: a report about that error.
    static func openErrorReport(title: String, message: String) {
        let model = FeedbackModel(kind: .problem)
        model.title = title
        model.details = "\(title). "
        model.crash = redact(message)
        model.notice = "\(AppInfo.name) ran into an error. A report helps fix it. Add what you were doing when it happened."
        WindowManager.shared.openFeedback(model: model)
    }

    static func openCrashReport(crashText: String) {
        let model = FeedbackModel(kind: .problem)
        model.title = "\(AppInfo.name) quit unexpectedly"
        // The form needs a description; this is a start the person can add to.
        model.details = "\(AppInfo.name) quit unexpectedly. "
        model.crash = crashText
        model.notice = "\(AppInfo.name) quit unexpectedly last time. Sending a report with the crash details helps fix it. Add what you were doing, if you remember."
        WindowManager.shared.openFeedback(model: model)
    }
}
