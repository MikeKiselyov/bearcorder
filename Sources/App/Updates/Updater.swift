import AppKit
import Observation
import AppCore

/// Tells when the GitHub repository this copy was built from has a newer release
/// (the top version in WhatsNewCatalog.swift), and rebuilds the app from its source folder with scripts/update.sh.
/// Each person builds and signs their own copy, so there are no downloads to trust.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    var hasUpdate: Bool {
        if case .available = state { return true }
        return false
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case updating
        case failed(String)
    }

    static let checkInterval: Double = 6 * 3600

    /// Set from outside only by DevChecks snapshots.
    var state: State = .idle
    private(set) var lastChecked: Date?

    let commit: String
    let repository: String
    let sourcePath: String

    @ObservationIgnored private var timer: Timer?

    /// How far a running update is, from its log. Set from outside only by DevChecks snapshots.
    var progress = UpdateProgress(step: .downloading, percent: 0)
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var buildStartedAt: Date?
    /// How long the last update's build took, the time the next one expects.
    static let buildSecondsKey = "lastUpdateBuildSeconds"

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        commit = info["SourceCommit"] as? String ?? ""
        repository = info["SourceRepository"] as? String ?? ""
        sourcePath = info["SourcePath"] as? String ?? ""
    }

    static var logURL: URL {
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(AppInfo.name)/update.log")
    }

    /// False for builds outside a git checkout of a GitHub repository, or before the first commit.
    var canCheck: Bool {
        return compareURL != nil || pretendCanCheck
    }

    /// Snapshots draw Settings → Updates as a copy built from a repository; the debug binary has none.
    @ObservationIgnored var pretendCanCheck = false

    var canUpdate: Bool {
        return FileManager.default.isExecutableFile(atPath: updateScript.path)
    }

    /// The newest release built into this copy.
    var version: String {
        return WhatsNew.latestVersion(WhatsNewCatalog.releases)
    }

    var versionText: String {
        if commit.isEmpty {
            return version
        }
        return "\(version) (\(commit.prefix(7)))"
    }

    private var updateScript: URL {
        return URL(fileURLWithPath: sourcePath).appendingPathComponent("scripts/update.sh")
    }

    private var compareURL: URL? {
        // e2e tests point the check at a local file server.
        if Automation.isEnabled, let override = UserDefaults.standard.string(forKey: "updateCompareURL"), !override.isEmpty {
            return URL(string: override)
        }
        return UpdateInfo.updateCompareURL(repository: repository, builtCommit: commit)
    }

    private var catalogURL: URL? {
        if Automation.isEnabled, let override = UserDefaults.standard.string(forKey: "updateCatalogURL"), !override.isEmpty {
            return URL(string: override)
        }
        return UpdateInfo.updateCatalogURL(repository: repository)
    }

    func start() {
        timer?.invalidate()
        timer = nil
        guard canCheck, AppSettings.shared.checkForUpdates else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Updater.checkInterval, repeats: true) { _ in
            Task { @MainActor in
                await Updater.shared.check(userInitiated: false)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await check(userInitiated: false)
        }
    }

    /// Background checks stay quiet on errors (offline, rate limit); a manual check reports them.
    /// Only a higher release version counts as an update; the commits are fetched to list the changes.
    func check(userInitiated: Bool) async {
        if SystemActions.recordInstead("check for updates") { return }
        guard canCheck, let catalogURL else { return }
        if state == .updating || state == .checking { return }
        state = .checking
        var request = URLRequest(url: catalogURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastChecked = Date()
            guard status == 200, let latest = ReleaseVersion.latest(inCatalogSource: String(decoding: data, as: UTF8.self)) else {
                state = userInitiated ? .failed(L("updates.error.httpStatus", status)) : .idle
                return
            }
            if !ReleaseVersion.isNewer(latest, than: version) {
                state = .upToDate
                return
            }
            var info = await fetchChanges() ?? UpdateInfo(newCommitCount: 0, changes: [])
            info.version = latest
            Log.info("update available: \(version) → \(latest), \(info.newCommitCount) new commits")
            state = .available(info)
        } catch {
            state = userInitiated ? .failed(L("updates.error.unreachable", error.localizedDescription)) : .idle
        }
    }

    /// The commits since this build, for the list under the badge. Nil when GitHub does not say.
    private func fetchChanges() async -> UpdateInfo? {
        guard let url = compareURL else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return UpdateInfo.parse(compareJSON: data)
    }

    /// Runs scripts/update.sh: git pull, build, replace this app and relaunch it.
    /// On success the script quits this process; on failure the reason is shown and logged.
    func update() {
        if SystemActions.recordInstead("update") { return }
        if state == .updating { return }
        guard canUpdate else {
            state = .failed(L("updates.error.sourceMissing", sourcePath))
            return
        }
        state = .updating
        try? FileManager.default.createDirectory(at: Updater.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Updater.logURL.path, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [updateScript.path, Bundle.main.bundlePath]
        process.currentDirectoryURL = URL(fileURLWithPath: sourcePath)
        if let log = try? FileHandle(forWritingTo: Updater.logURL) {
            process.standardOutput = log
            process.standardError = log
        }
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Updater.shared.updateFinished(status: status)
                }
            }
        }
        // The rebuilt app reads this on launch to show "What's new" with the commits since this build.
        UserDefaults.standard.set(commit, forKey: WhatsNewTracker.updatedFromKey)
        do {
            try process.run()
            Log.info("update started from \(sourcePath)")
            startProgress(log: Updater.logURL)
        } catch {
            UserDefaults.standard.removeObject(forKey: WhatsNewTracker.updatedFromKey)
            state = .failed(L("updates.error.startFailed", error.localizedDescription))
        }
    }

    /// Exit code of scripts/update.sh when the source folder has uncommitted changes.
    static let localChangesStatus: Int32 = 2

    /// Reads `log` every 0.5 s from 0% until the update ends (e2e points it at a made-up log).
    func startProgress(log: URL) {
        stopProgress()
        progress = UpdateProgress(step: .downloading, percent: 0)
        buildStartedAt = nil
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                // Decoding never fails: a read can end in the middle of a character being written.
                let data = (try? Data(contentsOf: log)) ?? Data()
                Updater.shared.readProgress(log: String(decoding: data, as: UTF8.self))
            }
        }
    }

    func stopProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Called with the whole log while updating; the build step's time counts from the first call that
    /// sees it, and the percent never goes back.
    func readProgress(log: String, now: Date = Date()) {
        let saved = UserDefaults.standard.double(forKey: Updater.buildSecondsKey)
        var elapsed: Double = 0
        if let buildStartedAt {
            elapsed = now.timeIntervalSince(buildStartedAt)
        }
        let next = UpdateProgress.estimate(log: log, elapsedInBuild: elapsed, expectedBuild: saved > 0 ? saved : nil)
        if next.percent >= progress.percent {
            progress = next
        }
        if next.step == .building && buildStartedAt == nil {
            buildStartedAt = now
        }
        if let seconds = UpdateProgress.buildSeconds(inLog: log) {
            UserDefaults.standard.set(seconds, forKey: Updater.buildSecondsKey)
        }
    }

    /// "Updating 45%" in the menu.
    var progressText: String {
        return L("menubar.update.updatingPercent", progress.percent)
    }

    /// "Building… 45%" in Settings.
    var progressStepText: String {
        switch progress.step {
        case .downloading: return L("menubar.update.step.downloading", progress.percent)
        case .building: return L("menubar.update.step.building", progress.percent)
        case .finishing: return L("menubar.update.step.finishing", progress.percent)
        case .installing: return L("menubar.update.step.installing", progress.percent)
        }
    }

    private func updateFinished(status: Int32) {
        stopProgress()
        // On success the script quits this app.
        if status == 0 { return }
        UserDefaults.standard.removeObject(forKey: WhatsNewTracker.updatedFromKey)
        if status == Updater.localChangesStatus {
            Log.info("update skipped: local changes in \(sourcePath)")
            state = .failed(L("updates.error.uncommittedChanges", sourcePath))
            return
        }
        let log = (try? String(contentsOf: Updater.logURL, encoding: .utf8)) ?? ""
        var lastLines: [String] = []
        for line in log.split(separator: "\n").suffix(3) {
            lastLines.append(String(line))
        }
        Log.error("update failed with status \(status)")
        state = .failed(L("updates.error.failed", lastLines.joined(separator: " ")))
    }

    func showLog() {
        SystemActions.open(Updater.logURL)
    }
}
