import AppKit
import AppCore

/// Saves the app's unified log (`log show`) for the time span of a clip, next to the clip.
enum SystemLogCollector {
    /// Bigger logs keep their last part: the end is where the bug is.
    static let maxBytes = 2_000_000

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
        do {
            try process.run()
        } catch {
            return 0
        }
        let output = await Task.detached(priority: .utility) { () -> Data in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        }.value

        var text = String(decoding: output, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        // The first line is the column header ("Timestamp Ty Process[PID:TID]").
        if let first = lines.first, first.hasPrefix("Timestamp") {
            lines.removeFirst()
        }
        if lines.isEmpty { return 0 }
        text = lines.joined(separator: "\n")
        if text.utf8.count > maxBytes {
            let tail = Data(text.utf8).suffix(maxBytes)
            text = "… (older lines cut)\n" + String(decoding: tail, as: UTF8.self)
        }
        let header = "# \(source.name) log, \(from) - \(to). Collected by \(AppInfo.name) with `log show --info`.\n"
        do {
            try (header + text + "\n").write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return 0
        }
        return lines.count
    }

    private static func clean(_ text: String) -> String {
        return text.replacingOccurrences(of: "\"", with: "")
    }
}
