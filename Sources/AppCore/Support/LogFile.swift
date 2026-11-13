import Foundation

/// A log file that stays open between lines: a line costs one write, not an open, a close and a
/// size check. Past `limit` bytes it starts over through `LogRotation`.
/// Not safe from several threads at once: the owner calls it from one serial queue.
public final class LogFile: @unchecked Sendable {
    private let url: URL
    private let limit: Int
    private var handle: FileHandle?
    private var size = 0

    public init(url: URL, limit: Int) {
        self.url = url
        self.limit = limit
    }

    /// Adds the line and a line break. The line is in the file when this returns.
    public func append(_ line: String) {
        if handle == nil || fileIsGone() {
            open()
        }
        guard let handle = handle else { return }
        let data = Data((line + "\n").utf8)
        do {
            try handle.write(contentsOf: data)
        } catch {
            close()
            return
        }
        size += data.count
        if size > limit {
            close()
            LogRotation.rotateIfNeeded(url, limit: limit)
        }
    }

    private func open() {
        close()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // O_APPEND: every write goes to the end, also when another copy of the app writes the same file.
        let descriptor = Darwin.open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        if descriptor < 0 {
            return
        }
        var info = stat()
        if fstat(descriptor, &info) == 0 {
            size = Int(info.st_size)
        }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func close() {
        try? handle?.close()
        handle = nil
        size = 0
    }

    /// An open file that someone deleted or renamed keeps taking writes nobody reads under the
    /// log's name. Another copy of the app renames it when it starts the log over.
    private func fileIsGone() -> Bool {
        guard let handle = handle else { return false }
        var open = stat()
        if fstat(handle.fileDescriptor, &open) != 0 {
            return true
        }
        var named = stat()
        if stat(url.path, &named) != 0 {
            return true
        }
        return open.st_ino != named.st_ino || open.st_dev != named.st_dev
    }
}
