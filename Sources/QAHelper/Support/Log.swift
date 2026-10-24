import Foundation
import os

/// Logs to the unified log and to ~/Library/Logs/QA Helper/qahelper.log,
/// so capture problems can be diagnosed from a bug report.
enum Log {
    private static let logger = Logger(subsystem: "QAHelper", category: "app")
    private static let queue = DispatchQueue(label: "qahelper.log")

    static var fileURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/QA Helper", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("qahelper.log")
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        write("INFO  " + message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        write("ERROR " + message)
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
