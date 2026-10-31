import Foundation

/// Whether git tracks anything in a dependency folder: such a folder belongs to the repository and
/// is not offered.
public enum GitTracking {
    /// What `git ls-files` said about a folder.
    public struct Answer: Sendable {
        /// git printed at least one path.
        public var printedPaths: Bool
        public var exitStatus: Int32
        public var errorText: String
        /// git did not answer in time and was stopped.
        public var timedOut: Bool

        public init(printedPaths: Bool, exitStatus: Int32, errorText: String, timedOut: Bool) {
            self.printedPaths = printedPaths
            self.exitStatus = exitStatus
            self.errorText = errorText
            self.timedOut = timedOut
        }
    }

    /// True when the folder is tracked. `run` asks git about the folder; nil means git could not
    /// be started. `gitIsInstalled` is `isGitInstalled()` outside tests.
    ///
    /// Not tracked only when it is plain: no .git in the folder's parent or above, or git ran and
    /// printed nothing, or git said "not a git repository". Anything else (git missing, the
    /// developer tools missing, dubious ownership, no answer in time) counts as tracked, so a
    /// folder is never offered on a guess.
    public static func isTracked(_ folder: URL, gitIsInstalled: Bool, run: (URL) -> Answer?) -> Bool {
        if !hasRepositoryAbove(folder.deletingLastPathComponent()) {
            return false
        }
        // Without the developer tools /usr/bin/git shows the dialog to install them.
        if !gitIsInstalled {
            return true
        }
        guard let answer = run(folder) else {
            return true
        }
        if answer.printedPaths || answer.timedOut {
            return true
        }
        if answer.exitStatus == 0 {
            return false
        }
        if answer.errorText.contains("not a git repository") {
            return false
        }
        return true
    }

    /// Where /usr/bin/git looks for the real git: the folder `xcode-select` chose (its link) when
    /// there is one, else Xcode and the Command Line Tools.
    public static let developerFolders: [URL] = {
        if let selected = try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link") {
            return [URL(fileURLWithPath: selected)]
        }
        return [
            URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
            URL(fileURLWithPath: "/Library/Developer/CommandLineTools"),
        ]
    }()

    /// True when one of the folders has a git. Only looks at files: without the developer tools,
    /// starting /usr/bin/git shows macOS's dialog to install them.
    public static func isGitInstalled(developerFolders folders: [URL] = developerFolders) -> Bool {
        for folder in folders {
            let git = folder.appendingPathComponent("usr/bin/git")
            if FileManager.default.fileExists(atPath: git.path) {
                return true
            }
        }
        return false
    }

    /// True when the folder or one above it has a .git (a folder, or a file for a worktree or submodule).
    public static func hasRepositoryAbove(_ folder: URL) -> Bool {
        var candidate = folder.standardizedFileURL
        while true {
            let git = candidate.appendingPathComponent(".git")
            var info = stat()
            if lstat(git.path, &info) == 0 {
                return true
            }
            if candidate.path == "/" {
                return false
            }
            candidate = candidate.deletingLastPathComponent().standardizedFileURL
        }
    }

    /// Runs `git ls-files` for the folder in its parent. A git that does not answer in 10 seconds is stopped.
    public static func runLsFiles(_ folder: URL) -> Answer? {
        return runLsFiles(folder, executable: URL(fileURLWithPath: "/usr/bin/git"))
    }

    /// Same, with the program to run (a test passes a script).
    public static func runLsFiles(_ folder: URL, executable: URL) -> Answer? {
        let process = Process()
        process.executableURL = executable
        // No fsmonitor: a repository's hook must not start a daemon or run a program for this question.
        process.arguments = ["-c", "core.fsmonitor=false", "-C", folder.deletingLastPathComponent().path, "ls-files", "-z", "--", folder.lastPathComponent]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        // English messages: "not a git repository" is looked for in them.
        environment["LC_ALL"] = "C"
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return nil
        }
        let stopper = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: stopper)
        // stderr is read at the same time: git blocks on a full pipe, and stdout would never close.
        let errorReader = ErrorReader(handle: errors.fileHandleForReading)
        errorReader.start()
        // The first bytes are enough: one tracked file means tracked.
        let firstBytes = output.fileHandleForReading.availableData
        if !firstBytes.isEmpty {
            stopper.cancel()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            return Answer(printedPaths: true, exitStatus: process.terminationStatus, errorText: "", timedOut: false)
        }
        let errorData = errorReader.waitForData()
        process.waitUntilExit()
        stopper.cancel()
        let errorText = String(decoding: errorData, as: UTF8.self)
        let timedOut = process.terminationReason == .uncaughtSignal
        return Answer(printedPaths: false, exitStatus: process.terminationStatus, errorText: errorText, timedOut: timedOut)
    }

    /// Reads a pipe to its end on another thread.
    private final class ErrorReader: @unchecked Sendable {
        private let handle: FileHandle
        private let finished = DispatchSemaphore(value: 0)
        private var data = Data()

        init(handle: FileHandle) {
            self.handle = handle
        }

        func start() {
            DispatchQueue.global().async {
                self.data = self.handle.readDataToEndOfFile()
                self.finished.signal()
            }
        }

        func waitForData() -> Data {
            finished.wait()
            return data
        }
    }
}
