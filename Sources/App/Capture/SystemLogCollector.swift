import AppKit
import AppCore

/// Saves the app's unified log (`log show`) for the time span of a clip, next to the clip.
enum SystemLogCollector {
    /// Bigger logs keep their last part: the end is where the bug is.
    static let maxBytes = 2_000_000
    /// `log show` takes a few seconds; on a loaded Mac with a long clip it can take far longer.
    static let timeout: Double = 60

    struct Source {
        var name: String
        /// The .app bundle; its helpers (renderers, XPC services) log under the same path.
        var bundlePath: String
    }

    static func source(for app: NSRunningApplication?) -> Source? {
        guard let running = app, running.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let name = running.localizedName ?? ""
        let path = running.bundleURL?.path ?? ""
        if name.isEmpty && path.isEmpty { return nil }
        return Source(name: name, bundlePath: path)
    }

    /// Writes the log to `file`. Returns the number of log lines, 0 when there was nothing to save.
    static func collect(_ source: Source, from start: Date, to end: Date, into file: URL) async -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        // `log show` works in whole seconds: widen by one on each side.
        let from = formatter.string(from: start.addingTimeInterval(-1))
        let to = formatter.string(from: end.addingTimeInterval(1))

        var predicate = "process == \"\(clean(source.name))\""
        if !source.bundlePath.isEmpty {
            predicate = "processImagePath BEGINSWITH \"\(clean(source.bundlePath))/\""
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--style", "compact", "--info", "--start", from, "--end", to, "--predicate", predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // The log is read while the tool runs, and only its end is kept: a chatty app writes far
        // more than fits in the file.
        // A longer clip has more log to go through.
        let limit = max(timeout, end.timeIntervalSince(start))
        let output = await Task.detached(priority: .utility) {
            return run(process, output: pipe, timeout: limit)
        }.value
        guard let output else {
            // What was read so far is the start of the span, without the end where the bug is.
            Log.info("system log for \(source.name): `log show` did not finish in \(Int(limit))s, nothing saved")
            return 0
        }

        var lines = String(decoding: output.tail(), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        // The first line is the column header ("Timestamp Ty Process[PID:TID]").
        if let first = lines.first, first.hasPrefix("Timestamp") {
            lines.removeFirst()
        }
        if lines.isEmpty { return 0 }
        var text = lines.joined(separator: "\n")
        if output.isCut {
            text = "… (older lines cut)\n" + text
        }
        let header = "# \(source.name) log, \(from) - \(to). Collected by \(AppInfo.name) with `log show --info`.\n"
        do {
            try (header + text + "\n").write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return 0
        }
        return lines.count
    }

    /// The end of what the tool wrote, nil when it was stopped for taking too long.
    static func run(_ process: Process, output pipe: Pipe, limit: Int = maxBytes, timeout: Double = timeout) -> StreamTail? {
        var tail = StreamTail(limit: limit)
        let reading = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: reading) {
            while let chunk = try? pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                tail.append(chunk)
            }
        }
        // Not started (no log, as before): nothing else closes the pipe the reader waits on.
        guard let finished = try? ProcessTimeout.run(process, seconds: timeout) else {
            try? pipe.fileHandleForWriting.close()
            reading.wait()
            return tail
        }
        // Stopped for taking too long: a child of the tool may still hold the pipe open, so the
        // reader is left to end by itself.
        if !finished { return nil }
        reading.wait()
        return tail
    }

    private static func clean(_ text: String) -> String {
        return text.replacingOccurrences(of: "\"", with: "")
    }
}
