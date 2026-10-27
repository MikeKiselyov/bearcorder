import AppKit

/// Quits and opens the app again (after Screen Recording is allowed, macOS needs a restart).
@MainActor
enum Relaunch {
    /// The new copy opens once this one is gone: quitting stops the capture first, which can take
    /// a moment, and opening while it still runs would only bring the old one forward.
    static func now() {
        openAgainAfterQuit()
        NSApp.terminate(nil)
    }

    /// Starts a watcher that opens the app again once this process is gone.
    static func openAgainAfterQuit() {
        let script = "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; open \"$2\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, "relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        try? task.run()
    }
}
