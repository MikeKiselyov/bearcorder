import AppKit
import BugbearCore

/// Watches the crash reports folder and reports crashes of apps the user worked with recently.
/// Uses a file system event source, so it costs nothing while nothing crashes.
@MainActor
final class CrashWatcher {
    nonisolated static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    /// An app counts as "worked with" if it was in front this recently.
    static let recentSeconds: Double = 600
    /// One clip per app in this window: a crash loop should not flood the history.
    static let repeatSeconds: Double = 30

    var onCrash: ((CrashReport, URL) -> Void)?
    /// Automation: accept crashes from any app.
    var acceptsAnyApp = false

    private var source: DispatchSourceFileSystemObject?
    private var folder = CrashWatcher.defaultFolder
    private var seenFiles: Set<String> = []
    private var recentApps: [(name: String, bundleId: String, time: Double)] = []
    private var lastClipTimes: [String: Double] = [:]
    private var activationObserver: NSObjectProtocol?

    func start(folder watchedFolder: URL = CrashWatcher.defaultFolder) {
        stop()
        folder = watchedFolder
        // macOS makes this folder with the first crash report; after a clean-up it can be missing.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        seenFiles = Set(listReports())
        let descriptor = open(folder.path, O_EVTONLY)
        if descriptor < 0 {
            Log.error("crash watcher cannot open \(folder.path)")
            return
        }
        let newSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        newSource.setEventHandler {
            MainActor.assumeIsolated {
                self.folderChanged()
            }
        }
        newSource.setCancelHandler {
            close(descriptor)
        }
        newSource.resume()
        source = newSource

        if let front = NSWorkspace.shared.frontmostApplication {
            noteActive(front)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let activated = app {
                    self.noteActive(activated)
                }
            }
        }
        Log.info("crash watcher started on \(folder.path)")
    }

    func stop() {
        source?.cancel()
        source = nil
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        activationObserver = nil
    }

    private func noteActive(_ app: NSRunningApplication) {
        let name = app.localizedName ?? ""
        let bundleId = app.bundleIdentifier ?? ""
        if bundleId == Bundle.main.bundleIdentifier { return }
        let now = CACurrentMediaTime()
        recentApps.removeAll { entry in entry.bundleId == bundleId && entry.name == name }
        recentApps.append((name: name, bundleId: bundleId, time: now))
        recentApps.removeAll { entry in now - entry.time > CrashWatcher.recentSeconds }
    }

    private func listReports() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var reports: [String] = []
        for name in names where name.hasSuffix(".ips") {
            reports.append(name)
        }
        return reports
    }

    private func folderChanged() {
        for name in listReports() where !seenFiles.contains(name) {
            seenFiles.insert(name)
            let file = folder.appendingPathComponent(name)
            // ReportCrash may still be writing; the header line comes first, so a short wait is enough.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.inspect(file)
            }
        }
    }

    private func inspect(_ file: URL) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        let text = String(decoding: head, as: UTF8.self)
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        guard let report = CrashReport.parse(headerLine: firstLine) else { return }
        guard isRelevant(report) else {
            Log.info("crash ignored: \(report.appName) was not used recently")
            return
        }
        let now = CACurrentMediaTime()
        if let last = lastClipTimes[report.appName], now - last < CrashWatcher.repeatSeconds {
            Log.info("crash ignored: another \(report.appName) crash within \(Int(CrashWatcher.repeatSeconds))s")
            return
        }
        lastClipTimes[report.appName] = now
        Log.info("crash detected: \(report.appName) at \(report.date)")
        onCrash?(report, file)
    }

    private func isRelevant(_ report: CrashReport) -> Bool {
        if acceptsAnyApp { return true }
        if report.appName == ProcessInfo.processInfo.processName { return false }
        let now = CACurrentMediaTime()
        for entry in recentApps where now - entry.time <= CrashWatcher.recentSeconds {
            if report.belongs(toAppNamed: entry.name, bundleId: entry.bundleId) {
                return true
            }
        }
        // The app in front right now counts too, even if it was activated before we started.
        if let front = NSWorkspace.shared.frontmostApplication {
            return report.belongs(toAppNamed: front.localizedName ?? "", bundleId: front.bundleIdentifier ?? "")
        }
        return false
    }
}
