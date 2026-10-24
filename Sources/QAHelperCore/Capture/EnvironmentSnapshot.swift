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

    /// Rows for the side panel, skipping empty values.
    public func rows(timeZone zone: TimeZone = .current) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        for field in extras ?? [] {
            rows.append((label: field.name, value: field.value))
        }
        rows.append((label: "macOS", value: osBuild.isEmpty ? osVersion : "\(osVersion) (\(osBuild))"))
        if !deviceModel.isEmpty { rows.append((label: "Device", value: deviceModel)) }
        if !display.isEmpty { rows.append((label: "Display", value: display)) }
        if !appName.isEmpty { rows.append((label: "App", value: appLine)) }
        if !url.isEmpty { rows.append((label: "URL", value: url)) }
        if !locale.isEmpty { rows.append((label: "Locale", value: locale)) }
        if !appearance.isEmpty { rows.append((label: "Appearance", value: appearance)) }
        rows.append((label: "Time", value: TimeConverter.format(capturedAt, pattern: "yyyy-MM-dd HH:mm:ss", timeZone: zone)))
        return rows
    }

    /// Short lines drawn as a badge over a screenshot or video.
    public func badgeLines(timeZone zone: TimeZone = .current) -> [String] {
        var lines: [String] = []
        if appName.isEmpty {
            lines.append(osLine)
        } else {
            lines.append("macOS \(osVersion) · \(appLine)")
        }
        if !display.isEmpty { lines.append(display) }
        if !url.isEmpty { lines.append(url) }
        var fieldTexts: [String] = []
        for field in extras ?? [] {
            fieldTexts.append("\(field.name): \(field.value)")
        }
        if !fieldTexts.isEmpty {
            lines.append(fieldTexts.joined(separator: " · "))
        }
        lines.append(TimeConverter.format(capturedAt, pattern: "yyyy-MM-dd HH:mm:ss", timeZone: zone))
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
