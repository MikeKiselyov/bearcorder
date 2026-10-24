import AppKit
import QAHelperCore

/// Builds an `EnvironmentSnapshot` for the app the user was looking at.
enum EnvironmentCollector {
    private static let scriptQueue = DispatchQueue(label: "qahelper.applescript")

    @MainActor
    static func snapshot(for app: NSRunningApplication?, readURL: Bool) async -> EnvironmentSnapshot {
        var snapshot = EnvironmentSnapshot()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.patchVersion > 0 {
            snapshot.osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        } else {
            snapshot.osVersion = "\(version.majorVersion).\(version.minorVersion)"
        }
        snapshot.osBuild = sysctlString("kern.osversion")
        snapshot.deviceModel = sysctlString("hw.model")
        snapshot.display = displayDescription()
        snapshot.locale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        snapshot.timeZone = TimeZone.current.identifier
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        snapshot.appearance = isDark ? "Dark" : "Light"
        snapshot.capturedAt = Date()
        let fields = await MainActor.run { AppSettings.shared.reportFields }
        var extras: [EnvironmentSnapshot.Field] = []
        for field in fields {
            let name = field.name.trimmingCharacters(in: .whitespaces)
            let value = field.value.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !value.isEmpty {
                extras.append(EnvironmentSnapshot.Field(name: name, value: value))
            }
        }
        if !extras.isEmpty {
            snapshot.extras = extras
        }

        if let app = app {
            snapshot.appName = app.localizedName ?? ""
            snapshot.appBundleId = app.bundleIdentifier ?? ""
            if let url = app.bundleURL, let bundle = Bundle(url: url) {
                let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                snapshot.appVersion = short
            }
            if readURL, let bundleId = app.bundleIdentifier {
                snapshot.url = await browserURL(bundleId: bundleId)
            }
        }
        return snapshot
    }

    static func displayDescription() -> String {
        guard let screen = NSScreen.main else { return "" }
        let scale = screen.backingScaleFactor
        let width = Int(screen.frame.width * scale)
        let height = Int(screen.frame.height * scale)
        return "\(width)×\(height) @\(Int(scale))x"
    }

    static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        if size == 0 { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static let browserScripts: [String: String] = [
        "com.apple.Safari": "tell application id \"com.apple.Safari\" to return URL of front document",
        "com.apple.SafariTechnologyPreview": "tell application id \"com.apple.SafariTechnologyPreview\" to return URL of front document",
        "com.google.Chrome": "tell application id \"com.google.Chrome\" to return URL of active tab of front window",
        "com.google.Chrome.canary": "tell application id \"com.google.Chrome.canary\" to return URL of active tab of front window",
        "com.brave.Browser": "tell application id \"com.brave.Browser\" to return URL of active tab of front window",
        "com.microsoft.edgemac": "tell application id \"com.microsoft.edgemac\" to return URL of active tab of front window",
        "company.thebrowser.Browser": "tell application id \"company.thebrowser.Browser\" to return URL of active tab of front window",
        "com.vivaldi.Vivaldi": "tell application id \"com.vivaldi.Vivaldi\" to return URL of active tab of front window",
        "org.chromium.Chromium": "tell application id \"org.chromium.Chromium\" to return URL of active tab of front window",
        "com.operasoftware.Opera": "tell application id \"com.operasoftware.Opera\" to return URL of active tab of front window",
    ]

    /// Reads the active tab URL via AppleScript. macOS asks for Automation permission once per browser.
    /// Gives up after this long: the first time, macOS asks "allow QA Helper to control the browser?"
    /// and a capture must not wait for that answer.
    static let urlTimeout: Double = 2

    static func browserURL(bundleId: String) async -> String {
        guard let source = browserScripts[bundleId] else { return "" }
        return await withCheckedContinuation { continuation in
            let answer = OnceAnswer(continuation)
            scriptQueue.async {
                var errorInfo: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&errorInfo)
                answer.resume(result?.stringValue ?? "")
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + urlTimeout) {
                answer.resume("")
            }
        }
    }
}

/// Resumes a continuation once, whichever comes first: the script's answer or the timeout.
private final class OnceAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Never>?

    init(_ continuation: CheckedContinuation<String, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: String) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }
}
