import AppKit
import Observation
import BugbearCore

/// Tells when the GitHub repository this copy was built from has new commits,
/// and rebuilds the app from its source folder with scripts/update.sh.
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
    let branch: String
    let repository: String
    let sourcePath: String

    @ObservationIgnored private var timer: Timer?

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        commit = info["BugbearCommit"] as? String ?? ""
        branch = info["BugbearBranch"] as? String ?? ""
        repository = info["BugbearRepository"] as? String ?? ""
        sourcePath = info["BugbearSourcePath"] as? String ?? ""
    }

    static var logURL: URL {
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Bugbear/update.log")
    }

    /// False for builds outside a git checkout of a GitHub repository, or before the first commit.
    var canCheck: Bool {
        return compareURL != nil
    }

    var canUpdate: Bool {
        return FileManager.default.isExecutableFile(atPath: updateScript.path)
    }

    var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
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
        return UpdateInfo.compareURL(repository: repository, commit: commit, branch: branch)
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
    func check(userInitiated: Bool) async {
        guard let url = compareURL else { return }
        if state == .updating || state == .checking { return }
        state = .checking
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastChecked = Date()
            if status == 404 {
                state = userInitiated ? .failed("This build's commit is not on GitHub yet.") : .idle
                return
            }
            guard let info = UpdateInfo.parse(compareJSON: data) else {
                state = userInitiated ? .failed("GitHub did not answer (HTTP \(status)). Try again later.") : .idle
                return
            }
            if info.isAvailable {
                Log.info("update available: \(info.newCommitCount) new commits")
                state = .available(info)
            } else {
                state = .upToDate
            }
        } catch {
            state = userInitiated ? .failed("Could not reach GitHub: \(error.localizedDescription)") : .idle
        }
    }

    /// Runs scripts/update.sh: git pull, build, replace this app and relaunch it.
    /// On success the script quits this process; on failure the reason is shown and logged.
    func update() {
        guard canUpdate else {
            state = .failed("The source folder \(sourcePath) is missing. Reinstall with scripts/install.sh.")
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
        } catch {
            UserDefaults.standard.removeObject(forKey: WhatsNewTracker.updatedFromKey)
            state = .failed("Could not start the update: \(error.localizedDescription)")
        }
    }

    /// Exit code of scripts/update.sh when the source folder has uncommitted changes.
    static let localChangesStatus: Int32 = 2

    private func updateFinished(status: Int32) {
        if status == 0 { return }
        UserDefaults.standard.removeObject(forKey: WhatsNewTracker.updatedFromKey)
        if status == Updater.localChangesStatus {
            Log.info("update skipped: local changes in \(sourcePath)")
            state = .failed("The source folder has uncommitted changes, so it was not updated. Commit or stash them in \(sourcePath), then try again.")
            return
        }
        let log = (try? String(contentsOf: Updater.logURL, encoding: .utf8)) ?? ""
        var lastLines: [String] = []
        for line in log.split(separator: "\n").suffix(3) {
            lastLines.append(String(line))
        }
        Log.error("update failed with status \(status)")
        state = .failed("Update failed: \(lastLines.joined(separator: " "))")
    }

    func showLog() {
        NSWorkspace.shared.open(Updater.logURL)
    }
}
