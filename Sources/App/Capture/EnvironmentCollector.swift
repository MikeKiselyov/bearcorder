import AppKit
import AppCore

/// Builds an `EnvironmentSnapshot` for the app the user was looking at.
enum EnvironmentCollector {
    private static let scriptQueue = DispatchQueue(label: "app.applescript")

    /// The field settings from Settings → Bug reports: compared to update open editors when they change.
    struct FieldSettings: Equatable {
        var extras: [EnvironmentSnapshot.Field]
        var hidden: [String]
        var renamed: [String: String]
    }

    @MainActor
    static var fieldSettings: FieldSettings {
        let settings = AppSettings.shared
        return FieldSettings(extras: settings.reportFields, hidden: settings.hiddenEnvironmentFields, renamed: settings.renamedEnvironmentFields)
    }

    /// Your fields, the fields turned off and the names given to them, as set in Settings → Bug
    /// reports now. On a capture already taken, `includingYourFields` false keeps the values your
    /// fields had then (Build 1.42 stays 1.42) and only applies which fields show and their names.
    @MainActor
    static func applyFieldSettings(to snapshot: inout EnvironmentSnapshot, includingYourFields: Bool = true) {
        applyFieldSettings(fieldSettings, to: &snapshot, includingYourFields: includingYourFields)
    }

    static func applyFieldSettings(_ settings: FieldSettings, to snapshot: inout EnvironmentSnapshot, includingYourFields: Bool) {
        applyShownFields(settings, to: &snapshot)
        if !includingYourFields { return }
        var extras: [EnvironmentSnapshot.Field] = []
        for field in settings.extras {
            let name = field.name.trimmingCharacters(in: .whitespaces)
            let value = field.value.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !value.isEmpty {
                extras.append(EnvironmentSnapshot.Field(name: name, value: value))
            }
        }
        snapshot.extras = nil
        if !extras.isEmpty {
            snapshot.extras = extras
        }
    }

    /// Which fields filled in by the app show, and under what names.
    private static func applyShownFields(_ settings: FieldSettings, to snapshot: inout EnvironmentSnapshot) {
        snapshot.hiddenFields = nil
        if !settings.hidden.isEmpty {
            snapshot.hiddenFields = settings.hidden
        }
        var renamed: [String: String] = [:]
        for (key, name) in settings.renamed {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                renamed[key] = trimmed
            }
        }
        snapshot.renamedFields = nil
        if !renamed.isEmpty {
            snapshot.renamedFields = renamed
        }
    }

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
        applyFieldSettings(to: &snapshot)

        if let app = app {
            snapshot.appName = app.localizedName ?? ""
            snapshot.appBundleId = app.bundleIdentifier ?? ""
            if let url = app.bundleURL, let bundle = Bundle(url: url) {
                let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                snapshot.appVersion = short
            }
            if readURL, let bundleId = app.bundleIdentifier {
                snapshot.url = await browserURL(bundleId: bundleId, pid: app.processIdentifier)
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

    /// Whether macOS lets the app read a browser's tab address (Privacy & Security → Automation).
    enum BrowserAccess {
        case allowed
        case denied
        case notAsked
        case notRunning
    }

    /// The browsers the app can read the address from that are open now, by bundle id.
    @MainActor
    static var runningBrowsers: [String] {
        var found: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            if let bundleId = app.bundleIdentifier, browserScripts[bundleId] != nil, !found.contains(bundleId) {
                found.append(bundleId)
            }
        }
        return found.sorted()
    }

    /// Asks macOS; with `ask` it shows the "allow <app name> to control …" question when there was none
    /// yet, and waits for the answer, so never on the main thread then.
    static func browserAccess(bundleId: String, ask: Bool) -> BrowserAccess {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        guard let descriptor = target.aeDesc else { return .notAsked }
        let status = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, ask)
        if status == noErr {
            return .allowed
        }
        if status == OSStatus(errAEEventNotPermitted) {
            return .denied
        }
        if status == OSStatus(procNotFound) {
            return .notRunning
        }
        return .notAsked
    }

    /// All open browsers together: denied when one is, allowed when every one is.
    static func browsersAccess(_ bundleIds: [String], ask: Bool) -> BrowserAccess {
        if bundleIds.isEmpty {
            return .notRunning
        }
        var allAllowed = true
        for bundleId in bundleIds {
            let access = browserAccess(bundleId: bundleId, ask: ask)
            if access == .denied {
                return .denied
            }
            if access != .allowed {
                allAllowed = false
            }
        }
        if allAllowed {
            return .allowed
        }
        return .notAsked
    }

    /// Reads the active tab URL via AppleScript. macOS asks for Automation permission once per browser.
    /// Gives up after this long: the first time, macOS asks "allow <app name> to control the browser?"
    /// and a capture must not wait for that answer.
    static let urlTimeout: Double = 2

    static func browserURL(bundleId: String, pid: pid_t) async -> String {
        guard let source = browserScripts[bundleId] else { return "" }
        return await withCheckedContinuation { continuation in
            let answer = OnceAnswer(continuation)
            scriptQueue.async {
                // Chromium browsers are asked by process: with a second copy of the same browser open
                // (a test browser started by Playwright or Selenium), a script by bundle id went to
                // that one, which has no windows, and the URL came back empty.
                if source.contains("active tab of front window") {
                    let url = chromiumURL(pid: pid)
                    if !url.isEmpty {
                        answer.resume(url)
                        return
                    }
                }
                var errorInfo: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&errorInfo)
                if let error = errorInfo {
                    // -1743: Automation for this browser is off in System Settings.
                    let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                    Log.info("url: \(bundleId) did not answer (\(number))")
                }
                answer.resume(result?.stringValue ?? "")
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + urlTimeout) {
                answer.resume("")
            }
        }
    }
}

extension EnvironmentCollector {
    /// `URL of active tab of window 1` as a raw Apple event sent to one process. The codes are the
    /// ones in every Chromium browser's scripting dictionary: window cwin, active tab acTa, URL "URL ".
    static func chromiumURL(pid: pid_t) -> String {
        let window = objectSpecifier(wantedClass: "cwin", container: NSAppleEventDescriptor.null(), form: "indx", data: NSAppleEventDescriptor(int32: 1))
        let tab = objectSpecifier(wantedClass: "prop", container: window, form: "prop", data: NSAppleEventDescriptor(typeCode: fourCharCode("acTa")))
        let url = objectSpecifier(wantedClass: "prop", container: tab, form: "prop", data: NSAppleEventDescriptor(typeCode: fourCharCode("URL ")))
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let event = NSAppleEventDescriptor(eventClass: fourCharCode("core"), eventID: fourCharCode("getd"), targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(url, forKeyword: keyDirectObject)
        do {
            let reply = try event.sendEvent(options: [.waitForReply], timeout: urlTimeout)
            return reply.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? ""
        } catch {
            Log.info("url: process \(pid) did not answer (\((error as NSError).code))")
            return ""
        }
    }

    private static func objectSpecifier(wantedClass: String, container: NSAppleEventDescriptor, form: String, data: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: typeObjectSpecifier) ?? NSAppleEventDescriptor.record()
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharCode(wantedClass)), forKeyword: AEKeyword(keyAEDesiredClass))
        specifier.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: fourCharCode(form)), forKeyword: AEKeyword(keyAEKeyForm))
        specifier.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        return specifier
    }

    /// "cwin" → its four-character code.
    static func fourCharCode(_ text: String) -> FourCharCode {
        var code: FourCharCode = 0
        for byte in text.utf8 {
            code = (code << 8) + FourCharCode(byte)
        }
        return code
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
