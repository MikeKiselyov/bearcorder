import Foundation

/// Why a process crashed and where, read from a macOS crash report (`.ips`): a JSON header line,
/// then one JSON object with the exception, the crashed thread and the loaded images.
public struct CrashSummary: Equatable {
    public var reason: String
    /// "SIGSEGV", "SIGKILL"...
    public var signal: String
    /// Who ended the process: "SIGNAL", "CODESIGNING"...
    public var namespace: String
    /// Text the app left behind, like a Swift "Fatal error: ..." message.
    public var message: String
    /// The crashed thread, top first: "Bugbear  CaptureStore.selectScreen(_:)".
    public var frames: [String]

    public init(reason: String, signal: String = "", namespace: String = "", message: String = "", frames: [String] = []) {
        self.reason = reason
        self.signal = signal
        self.namespace = namespace
        self.message = message
        self.frames = frames
    }

    public static func parse(reportText: String, maxFrames: Int = 12) -> CrashSummary? {
        guard let newline = reportText.firstIndex(of: "\n") else { return nil }
        let body = String(reportText[reportText.index(after: newline)...])
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let report = object as? [String: Any] else { return nil }

        var reasonParts: [String] = []
        var signal = ""
        var namespace = ""
        if let exception = report["exception"] as? [String: Any] {
            if let type = exception["type"] as? String {
                reasonParts.append(type)
            }
            if let name = exception["signal"] as? String {
                signal = name
                reasonParts.append("(\(name))")
            }
        }
        if let termination = report["termination"] as? [String: Any] {
            namespace = termination["namespace"] as? String ?? ""
            if let indicator = termination["indicator"] as? String, !indicator.isEmpty {
                reasonParts.append("- \(indicator)")
            }
        }
        if reasonParts.isEmpty {
            return nil
        }

        var messages: [String] = []
        if let appSpecific = report["asi"] as? [String: Any] {
            for key in appSpecific.keys.sorted() {
                if let lines = appSpecific[key] as? [String] {
                    for line in lines {
                        messages.append(line)
                    }
                }
            }
        }

        var imageNames: [String] = []
        if let images = report["usedImages"] as? [[String: Any]] {
            for image in images {
                imageNames.append(image["name"] as? String ?? "???")
            }
        }
        var frames: [String] = []
        if let threads = report["threads"] as? [[String: Any]] {
            var crashed: [String: Any]?
            for thread in threads {
                if thread["triggered"] as? Bool == true {
                    crashed = thread
                }
            }
            if crashed == nil, let index = report["faultingThread"] as? Int, index >= 0, index < threads.count {
                crashed = threads[index]
            }
            if let thread = crashed, let threadFrames = thread["frames"] as? [[String: Any]] {
                for frame in threadFrames.prefix(maxFrames) {
                    var image = "???"
                    if let index = frame["imageIndex"] as? Int, index >= 0, index < imageNames.count {
                        image = imageNames[index]
                    }
                    let symbol = frame["symbol"] as? String ?? "?"
                    frames.append("\(image)  \(symbol)")
                }
            }
        }
        return CrashSummary(reason: reasonParts.joined(separator: " "), signal: signal, namespace: namespace, message: messages.joined(separator: "\n"), frames: frames)
    }

    /// The process was ended from outside, not by a bug: killed (an update, Force Quit) or its
    /// code changed on disk while it ran (a rebuild replacing the app).
    public var isExternalKill: Bool {
        return signal == "SIGKILL" || namespace == "CODESIGNING"
    }

    /// For the issue: the reason, the app's message, then the crashed thread.
    public var text: String {
        var lines: [String] = [reason]
        if !message.isEmpty {
            lines.append(message)
        }
        if !frames.isEmpty {
            lines.append("")
            lines.append("Crashed thread:")
            for frame in frames {
                lines.append(frame)
            }
        }
        return lines.joined(separator: "\n")
    }
}
