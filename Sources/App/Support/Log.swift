import Foundation
import os
import AppCore

/// Logs to the unified log and to ~/Library/Logs/<app name>/<app name>.log,
/// so capture problems can be diagnosed from a bug report.
enum Log {
    private static let logger = Logger(subsystem: AppInfo.name, category: "app")
    private static let queue = DispatchQueue(label: "app.log")

    /// The log file's name, also in the zip a problem report makes.
    static let fileName = "\(AppInfo.name).log"

    static var fileURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(AppInfo.name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        write("INFO  " + message)
    }

    /// Self-tests set this to see the error lines without reading the log file. Returning true keeps
    /// the line out of the log file: a test's made-up error, with its temporary paths, is not the
    /// person's log.
    nonisolated(unsafe) static var errorObserver: ((String) -> Bool)?

    static func error(_ message: String) {
        var keptOut = false
        if let observer = errorObserver {
            keptOut = observer(message)
        }
        logger.error("\(message, privacy: .public)")
        if keptOut { return }
        write("ERROR " + message)
    }

    /// Waits until the lines logged so far are in the file.
    static func waitForWrites() {
        queue.sync {}
    }

    private static func write(_ line: String) {
        let stamp = TimeFormatStamp.now()
        queue.async {
            let url = fileURL
            let data = Data("\(stamp) \(line)\n".utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
            // Keep the file small: start over past 2 MB.
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 2_000_000 {
                try? Data().write(to: url)
            }
        }
    }
}

private enum TimeFormatStamp {
    static func now() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
