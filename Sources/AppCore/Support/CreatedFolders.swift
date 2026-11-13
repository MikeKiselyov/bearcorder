import Foundation

/// Remembers which folders were already made, so a path asked for many times a second (every
/// history row asks for the captures folder) costs one system call, not one per ask.
public final class CreatedFolders: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []

    public init() {}

    /// Calls `create` the first time a path is asked for. A create that throws is tried again on
    /// the next ask.
    public func ensure(_ url: URL, create: (URL) throws -> Void) rethrows {
        lock.lock()
        defer { lock.unlock() }
        if paths.contains(url.path) {
            return
        }
        try create(url)
        paths.insert(url.path)
    }
}
