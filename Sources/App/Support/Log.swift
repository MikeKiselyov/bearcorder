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

    /// One open file and one formatter for every line; both are used only on `queue`.
    private static let file = LogFile(url: fileURL, limit: 2_000_000)
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func write(_ line: String) {
        let date = Date()
        queue.async {
            // Keeps the file small: past 2 MB it moves to <name>.log.1 and a new one starts.
            file.append("\(stampFormatter.string(from: date)) \(line)")
        }
    }
}
