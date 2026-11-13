import Foundation

/// Image and video work that must stay off the main thread reports here, and the self-test fails
/// when any of it ran on the main thread anyway.
enum HeavyWork {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var mainThreadRuns: [String] = []

    static func ran(_ name: String) {
        if !Thread.isMainThread { return }
        lock.lock()
        mainThreadRuns.append(name)
        lock.unlock()
    }

    /// What ran on the main thread since the last call.
    static func takeMainThreadRuns() -> [String] {
        lock.lock()
        let runs = mainThreadRuns
        mainThreadRuns = []
        lock.unlock()
        return runs
    }
}
