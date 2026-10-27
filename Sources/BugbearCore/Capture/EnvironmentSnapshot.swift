import Foundation

/// What was on screen when a capture was taken. Collected by the app, stored with the capture.
public struct EnvironmentSnapshot: Codable, Equatable {
    /// A field the tester sets in Settings, like "Stand: stage-3" or "Build: 1.42.0".
    public struct Field: Codable, Equatable {
        public var name: String
        public var value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// A field Bugbear fills in by itself. The raw value is its usual name in the report.
    public enum StandardField: String, CaseIterable, Codable {
        case macOS = "macOS"
        case device = "Device"
        case display = "Display"
        case app = "App"
        case url = "URL"
        case locale = "Locale"
        case appearance = "Appearance"
        case time = "Time"
    }

    public var osVersion: String
    public var osBuild: String
    public var deviceModel: String
    public var display: String
    public var appName: String
    public var appVersion: String
    public var appBundleId: String
    public var url: String
    public var locale: String
    public var timeZone: String
    public var appearance: String
    public var capturedAt: Date
    /// Report fields from Settings. Optional so captures saved before them still load.
    public var extras: [Field]?
    /// Fields the tester turned off in Settings (`StandardField` raw values). Optional so older captures load.
    public var hiddenFields: [String]?
    /// Names the tester gave fields in Settings, by `StandardField` raw value.
    public var renamedFields: [String: String]?

    public init(
        osVersion: String = "",
        osBuild: String = "",
        deviceModel: String = "",
        display: String = "",
        appName: String = "",
        appVersion: String = "",
        appBundleId: String = "",
        url: String = "",
        locale: String = "",
        timeZone: String = "",
        appearance: String = "",
        capturedAt: Date = Date()
    ) {
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.deviceModel = deviceModel
        self.display = display
        self.appName = appName
        self.appVersion = appVersion
        self.appBundleId = appBundleId
        self.url = url
        self.locale = locale
        self.timeZone = timeZone
        self.appearance = appearance
        self.capturedAt = capturedAt
    }

    public var appLine: String {
        if appVersion.isEmpty { return appName }
        return "\(appName) \(appVersion)"
    }

    public var osLine: String {
        if osBuild.isEmpty { return "macOS \(osVersion)" }
        return "macOS \(osVersion) (\(osBuild))"
    }

    /// Whether this field goes into the panel, the badge and the report.
    public func shows(_ field: StandardField) -> Bool {
        guard let hidden = hiddenFields else { return true }
        return !hidden.contains(field.rawValue)
    }

    /// The field's name in the panel and the report: the tester's own name, or the usual one.
    public func name(of field: StandardField) -> String {
        guard let names = renamedFields, let renamed = names[field.rawValue] else { return field.rawValue }
        let trimmed = renamed.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return field.rawValue
        }
        return trimmed
    }

    /// What a field holds in this capture, "" when nothing was collected.
    public func value(of field: StandardField, timeZone zone: TimeZone = .current) -> String {
        switch field {
        case .macOS:
            if osBuild.isEmpty { return osVersion }
            return "\(osVersion) (\(osBuild))"
        case .device:
            return deviceModel
        case .display:
            return display
        case .app:
            if appName.isEmpty { return "" }
            return appLine
        case .url:
            return url
        case .locale:
            return locale
        case .appearance:
            return appearance
        case .time:
            return TimeConverter.format(capturedAt, pattern: "yyyy-MM-dd HH:mm:ss", timeZone: zone)
        }
    }

    /// Rows for the side panel, skipping empty values and fields turned off.
    public func rows(timeZone zone: TimeZone = .current) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        for field in extras ?? [] {
            rows.append((label: field.name, value: field.value))
        }
        for field in StandardField.allCases where shows(field) {
            let value = value(of: field, timeZone: zone)
            if !value.isEmpty {
                rows.append((label: name(of: field), value: value))
            }
        }
        return rows
    }

    /// Short lines drawn as a badge over a screenshot or video: every field that is on, values only.
    public func badgeLines(timeZone zone: TimeZone = .current) -> [String] {
        var lines: [String] = []
        var firstLine: [String] = []
        let showsApp = shows(.app) && !appName.isEmpty
        // Next to the app the build is left out to keep the line short.
        if shows(.macOS) && showsApp {
            firstLine.append("macOS \(osVersion)")
        } else if shows(.macOS) {
            firstLine.append(osLine)
        }
        if showsApp {
            firstLine.append(appLine)
        }
        if !firstLine.isEmpty {
            lines.append(firstLine.joined(separator: " · "))
        }
        if shows(.device) && !deviceModel.isEmpty { lines.append(deviceModel) }
        if shows(.display) && !display.isEmpty { lines.append(display) }
        if shows(.url) && !url.isEmpty { lines.append(url) }
        // Locale and appearance are short: one line for both.
        var lookLine: [String] = []
        if shows(.locale) && !locale.isEmpty {
            lookLine.append(locale)
        }
        if shows(.appearance) && !appearance.isEmpty {
            lookLine.append(appearance)
        }
        if !lookLine.isEmpty {
            lines.append(lookLine.joined(separator: " · "))
        }
        var fieldTexts: [String] = []
        for field in extras ?? [] {
            fieldTexts.append("\(field.name): \(field.value)")
        }
        if !fieldTexts.isEmpty {
            lines.append(fieldTexts.joined(separator: " · "))
        }
        if shows(.time) {
            lines.append(TimeConverter.format(capturedAt, pattern: "yyyy-MM-dd HH:mm:ss", timeZone: zone))
        }
        return lines
    }

    /// Plain text block for pasting into a bug report.
    public func markdown(timeZone zone: TimeZone = .current) -> String {
        var lines: [String] = ["**Environment**"]
        for row in rows(timeZone: zone) {
            lines.append("- \(row.label): \(row.value)")
        }
        return lines.joined(separator: "\n")
    }
}
