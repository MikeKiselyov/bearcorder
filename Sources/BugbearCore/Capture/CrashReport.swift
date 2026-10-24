import Foundation

/// The first line of a macOS crash report (`~/Library/Logs/DiagnosticReports/*.ips`).
public struct CrashReport: Equatable {
    public var appName: String
    public var bundleId: String
    public var date: Date

    /// `bug_type` of a real crash; hangs, resource reports and analytics use other numbers.
    static let crashBugType = "309"

    /// Parses the JSON header line. Returns nil for anything that is not a crash.
    public static func parse(headerLine: String) -> CrashReport? {
        guard let data = headerLine.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data), let header = object as? [String: Any] else { return nil }
        guard let bugType = header["bug_type"] as? String, bugType == crashBugType else { return nil }
        let name = header["app_name"] as? String ?? header["name"] as? String ?? ""
        if name.isEmpty { return nil }
        guard let timestamp = header["timestamp"] as? String, let date = parseTimestamp(timestamp) else { return nil }
        let bundleId = header["bundleID"] as? String ?? ""
        return CrashReport(appName: name, bundleId: bundleId, date: date)
    }

    /// "2026-10-24 14:13:35.00 +0300"
    static func parseTimestamp(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text)
    }

    /// True when the crashed process is the app or one of its helpers ("Google Chrome Helper (Renderer)").
    public func belongs(toAppNamed name: String, bundleId otherBundleId: String) -> Bool {
        if !bundleId.isEmpty && !otherBundleId.isEmpty {
            if bundleId == otherBundleId || bundleId.hasPrefix(otherBundleId + ".") {
                return true
            }
        }
        if name.isEmpty {
            return false
        }
        return appName == name || appName.hasPrefix(name + " Helper")
    }
}
