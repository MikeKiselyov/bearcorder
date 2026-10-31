import Foundation

/// Saves an editor's project file off the main thread. Edits that come quickly one after another
/// are written once, a short `delay` after the first of them, with the newest data. Every write is
/// atomic, so a half-written file never replaces a good one, and a failed write goes to `onFailure`
/// instead of being lost. `flush()` writes what is still waiting right away (on close), and
/// `flushAll()` does it for every editor (on quit).
public final class ProjectFileWriter: @unchecked Sendable {
    public let url: URL
    private let delay: Double
    private let onFailure: @Sendable (Error) -> Void
    private let onSuccess: @Sendable () -> Void
    private let queue = DispatchQueue(label: "app.project-file-writer")
    /// Guards `pending`: edits arrive on the main thread, writes happen on `queue`.
    private let lock = NSLock()
    private var pending: Data?

    /// `onFailure` and `onSuccess` run on the writer's queue after each write that was tried.
    public init(url: URL, delay: Double = 0.3, onFailure: @escaping @Sendable (Error) -> Void, onSuccess: @escaping @Sendable () -> Void = {}) {
        self.url = url
        self.delay = delay
        self.onFailure = onFailure
        self.onSuccess = onSuccess
        ProjectFileWriter.register(self)
    }

    /// Keeps `data` to be written soon; data scheduled before it and not written yet is dropped.
    public func schedule(_ data: Data) {
        lock.lock()
        let writeIsWaiting = pending != nil
        pending = data
        lock.unlock()
        if writeIsWaiting { return }
        // Holds the writer until the write, so an editor closed in between still gets its file.
        queue.asyncAfter(deadline: .now() + delay) {
            self.writePending()
        }
    }

    /// Writes the waiting data now and returns when it is on disk (or failed). Nothing waiting:
    /// the file is left as it is.
    public func flush() {
        queue.sync {
            writePending()
        }
    }

    /// Runs on `queue` only.
    private func writePending() {
        lock.lock()
        let data = pending
        pending = nil
        lock.unlock()
        guard let data = data else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            onFailure(error)
            return
        }
        onSuccess()
    }

    // MARK: Live writers

    private final class WeakWriter {
        weak var writer: ProjectFileWriter?

        init(_ writer: ProjectFileWriter) {
            self.writer = writer
        }
    }

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [WeakWriter] = []

    private static func register(_ writer: ProjectFileWriter) {
        registryLock.lock()
        var alive: [WeakWriter] = []
        for entry in registry where entry.writer != nil {
            alive.append(entry)
        }
        alive.append(WeakWriter(writer))
        registry = alive
        registryLock.unlock()
    }

    /// Writes what every live writer still has waiting, for when the app quits.
    public static func flushAll() {
        registryLock.lock()
        var writers: [ProjectFileWriter] = []
        var alive: [WeakWriter] = []
        for entry in registry {
            if let writer = entry.writer {
                writers.append(writer)
                alive.append(entry)
            }
        }
        registry = alive
        registryLock.unlock()
        for writer in writers {
            writer.flush()
        }
    }
}
