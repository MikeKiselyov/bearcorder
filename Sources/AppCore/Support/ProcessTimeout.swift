import Foundation

/// Runs a process and waits for it, but not longer than `seconds` (plus a few seconds to stop it).
public enum ProcessTimeout {
    /// Returns true when the process ended by itself, false when it was stopped for taking too long.
    public static func run(_ process: Process, seconds: Double) throws -> Bool {
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }
        try process.run()
        let result = finished.wait(timeout: .now() + seconds)
        if result == .success {
            return true
        }
        if process.isRunning {
            process.terminate()
        }
        // A process that ignores the signal is killed; the wait stays short either way.
        if finished.wait(timeout: .now() + 2) == .timedOut {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            _ = finished.wait(timeout: .now() + 2)
        }
        return false
    }
}
