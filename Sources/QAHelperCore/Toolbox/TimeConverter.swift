import Foundation

public struct ParsedTime {
    public var date: Date
    /// What the input was recognised as, for example "Unix seconds".
    public var format: String
}

public struct TimeRepresentation: Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String
}

public enum TimeConverter {
    static let posix = Locale(identifier: "en_US_POSIX")

    // MARK: Parsing

    public static func parse(_ input: String, now: Date = Date(), timeZone: TimeZone = .current) -> ParsedTime? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        if let parsed = parseNumeric(text) { return parsed }
        if let parsed = parseObjectId(text) { return parsed }
        if let parsed = parseUUID(text) { return parsed }
        if let parsed = parseISO(text) { return parsed }
        if let parsed = parsePatterns(text, timeZone: timeZone) { return parsed }
        if let parsed = parseRelative(text, now: now, timeZone: timeZone) { return parsed }
        return nil
    }

    static func parseNumeric(_ text: String) -> ParsedTime? {
        guard let value = Double(text), !text.contains("e"), !text.contains("E") else { return nil }
        let magnitude = abs(value)
        if magnitude >= 1e17 {
            return ParsedTime(date: Date(timeIntervalSince1970: value / 1e9), format: "Unix nanoseconds")
        }
        if magnitude >= 1e14 {
            return ParsedTime(date: Date(timeIntervalSince1970: value / 1e6), format: "Unix microseconds")
        }
        if magnitude >= 1e11 {
            return ParsedTime(date: Date(timeIntervalSince1970: value / 1e3), format: "Unix milliseconds")
        }
        return ParsedTime(date: Date(timeIntervalSince1970: value), format: "Unix seconds")
    }

    static func isHex(_ text: String) -> Bool {
        for character in text {
            if !character.isHexDigit { return false }
        }
        return !text.isEmpty
    }

    static func parseObjectId(_ text: String) -> ParsedTime? {
        guard text.count == 24, isHex(text) else { return nil }
        let prefix = String(text.prefix(8))
        guard let seconds = UInt32(prefix, radix: 16) else { return nil }
        return ParsedTime(date: Date(timeIntervalSince1970: Double(seconds)), format: "MongoDB ObjectId")
    }

    static func parseUUID(_ text: String) -> ParsedTime? {
        let lower = text.lowercased()
        guard lower.count == 36, UUID(uuidString: lower) != nil else { return nil }
        let hex = lower.replacingOccurrences(of: "-", with: "")
        let characters = Array(hex)
        let version = characters[12]
        if version == "7" {
            guard let milliseconds = UInt64(String(characters[0..<12]), radix: 16) else { return nil }
            return ParsedTime(date: Date(timeIntervalSince1970: Double(milliseconds) / 1000), format: "UUID v7")
        }
        if version == "1" {
            let timeLow = String(characters[0..<8])
            let timeMid = String(characters[8..<12])
            let timeHigh = String(characters[13..<16])
            guard let ticks = UInt64(timeHigh + timeMid + timeLow, radix: 16) else { return nil }
            // UUID v1 counts 100 ns intervals since 1582-10-15.
            let seconds = Double(ticks) / 1e7 - 12_219_292_800
            return ParsedTime(date: Date(timeIntervalSince1970: seconds), format: "UUID v1")
        }
        return nil
    }

    static func parseISO(_ text: String) -> ParsedTime? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) {
            return ParsedTime(date: date, format: "ISO 8601")
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) {
            return ParsedTime(date: date, format: "ISO 8601")
        }
        return nil
    }

    static func parsePatterns(_ text: String, timeZone: TimeZone) -> ParsedTime? {
        let patterns: [(pattern: String, label: String, zoneInText: Bool)] = [
            ("EEE, dd MMM yyyy HH:mm:ss Z", "RFC 2822", true),
            ("EEE, d MMM yyyy HH:mm:ss Z", "RFC 2822", true),
            ("EEE, dd MMM yyyy HH:mm:ss zzz", "HTTP date", true),
            ("dd MMM yyyy HH:mm:ss Z", "RFC 2822", true),
            ("yyyy-MM-dd'T'HH:mm:ss.SSS", "ISO 8601 (local)", false),
            ("yyyy-MM-dd'T'HH:mm:ss", "ISO 8601 (local)", false),
            ("yyyy-MM-dd HH:mm:ss.SSS", "Date time (local)", false),
            ("yyyy-MM-dd HH:mm:ss", "Date time (local)", false),
            ("yyyy-MM-dd HH:mm", "Date time (local)", false),
            ("yyyy-MM-dd", "Date (local)", false),
            ("dd.MM.yyyy HH:mm:ss", "Date time (local)", false),
            ("dd.MM.yyyy HH:mm", "Date time (local)", false),
            ("dd.MM.yyyy", "Date (local)", false),
            ("MM/dd/yyyy HH:mm:ss", "US date time (local)", false),
            ("MM/dd/yyyy", "US date (local)", false),
            ("HH:mm:ss", "Time today (local)", false),
            ("HH:mm", "Time today (local)", false),
        ]
        for entry in patterns {
            let formatter = DateFormatter()
            formatter.locale = posix
            formatter.dateFormat = entry.pattern
            formatter.timeZone = timeZone
            formatter.isLenient = false
            guard let date = formatter.date(from: text) else { continue }
            if entry.pattern.hasPrefix("HH") {
                // Time-only input means "today at this time".
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
                if let today = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0, of: Date()) {
                    return ParsedTime(date: today, format: entry.label)
                }
            }
            return ParsedTime(date: date, format: entry.label)
        }
        return nil
    }

    static func unitSeconds(_ unit: String) -> Double? {
        let units: [(names: [String], seconds: Double)] = [
            (["s", "sec", "secs", "second", "seconds"], 1),
            (["m", "min", "mins", "minute", "minutes"], 60),
            (["h", "hr", "hrs", "hour", "hours"], 3600),
            (["d", "day", "days"], 86400),
            (["w", "week", "weeks"], 604_800),
        ]
        for entry in units {
            if entry.names.contains(unit) { return entry.seconds }
        }
        return nil
    }

    static func parseRelative(_ text: String, now: Date, timeZone: TimeZone) -> ParsedTime? {
        let lower = text.lowercased()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if lower == "now" {
            return ParsedTime(date: now, format: "Relative")
        }
        if lower == "today" {
            return ParsedTime(date: calendar.startOfDay(for: now), format: "Relative")
        }
        if lower == "yesterday" {
            let start = calendar.startOfDay(for: now)
            return ParsedTime(date: start.addingTimeInterval(-86400), format: "Relative")
        }
        if lower == "tomorrow" {
            let start = calendar.startOfDay(for: now)
            return ParsedTime(date: start.addingTimeInterval(86400), format: "Relative")
        }

        let words = lower.split(separator: " ").map(String.init)
        // "in 3 days"
        if words.count == 3 && words[0] == "in", let amount = Double(words[1]), let seconds = unitSeconds(words[2]) {
            return ParsedTime(date: now.addingTimeInterval(amount * seconds), format: "Relative")
        }
        // "3 days ago"
        if words.count == 3 && words[2] == "ago", let amount = Double(words[0]), let seconds = unitSeconds(words[1]) {
            return ParsedTime(date: now.addingTimeInterval(-amount * seconds), format: "Relative")
        }
        // "+3d" or "-90m"
        if let first = lower.first, first == "+" || first == "-" {
            let body = String(lower.dropFirst())
            var digits = ""
            var unit = ""
            for character in body {
                if character.isNumber || character == "." {
                    digits.append(character)
                } else {
                    unit.append(character)
                }
            }
            if let amount = Double(digits), let seconds = unitSeconds(unit) {
                let sign: Double = first == "-" ? -1 : 1
                return ParsedTime(date: now.addingTimeInterval(sign * amount * seconds), format: "Relative")
            }
        }
        return nil
    }

    // MARK: Formatting

    public static func isoString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        let hasFraction = date.timeIntervalSince1970 != date.timeIntervalSince1970.rounded()
        if hasFraction {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        } else {
            formatter.formatOptions = [.withInternetDateTime]
        }
        return formatter.string(from: date)
    }

    public static func format(_ date: Date, pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    public static func relativeString(from now: Date, to date: Date) -> String {
        let difference = date.timeIntervalSince(now)
        let absolute = abs(difference)
        if absolute < 45 { return "just now" }
        let steps: [(limit: Double, divisor: Double, unit: String)] = [
            (3600, 60, "minute"),
            (86400, 3600, "hour"),
            (86400 * 30, 86400, "day"),
            (86400 * 365, 86400 * 30, "month"),
            (Double.greatestFiniteMagnitude, 86400 * 365, "year"),
        ]
        for step in steps {
            if absolute < step.limit {
                let count = Int((absolute / step.divisor).rounded())
                let unit = count == 1 ? step.unit : step.unit + "s"
                if difference > 0 {
                    return "in \(count) \(unit)"
                }
                return "\(count) \(unit) ago"
            }
        }
        return ""
    }

    public static func representations(of date: Date, now: Date = Date(), localTimeZone: TimeZone = .current) -> [TimeRepresentation] {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = localTimeZone
        let week = calendar.component(.weekOfYear, from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let seconds = date.timeIntervalSince1970
        var unixSeconds = String(Int64(seconds.rounded(.down)))
        if seconds != seconds.rounded() {
            unixSeconds = String(format: "%.3f", seconds)
        }
        let milliseconds = String(Int64((seconds * 1000).rounded()))
        let human = format(date, pattern: "EEEE, d MMMM yyyy · HH:mm:ss", timeZone: localTimeZone)
        return [
            TimeRepresentation(label: "ISO 8601 · UTC", value: isoString(date, timeZone: utc)),
            TimeRepresentation(label: "Local · \(localTimeZone.identifier)", value: isoString(date, timeZone: localTimeZone)),
            TimeRepresentation(label: "Unix seconds", value: unixSeconds),
            TimeRepresentation(label: "Unix milliseconds", value: milliseconds),
            TimeRepresentation(label: "RFC 2822", value: format(date, pattern: "EEE, dd MMM yyyy HH:mm:ss Z", timeZone: utc)),
            TimeRepresentation(label: "Human", value: "\(human) · week \(week) · day \(dayOfYear)"),
            TimeRepresentation(label: "Relative", value: relativeString(from: now, to: date)),
            TimeRepresentation(label: "SQL", value: format(date, pattern: "yyyy-MM-dd HH:mm:ss", timeZone: utc)),
        ]
    }

    /// "HH:mm" in the zone plus a day hint like "+1 day" when the date differs from local.
    public static func zoneTime(_ date: Date, zone: TimeZone, localZone: TimeZone = .current) -> (time: String, dayHint: String) {
        let time = format(date, pattern: "HH:mm", timeZone: zone)
        let zoneDay = format(date, pattern: "yyyyMMdd", timeZone: zone)
        let localDay = format(date, pattern: "yyyyMMdd", timeZone: localZone)
        var hint = ""
        if zoneDay > localDay { hint = "+1 day" }
        if zoneDay < localDay { hint = "−1 day" }
        return (time: time, dayHint: hint)
    }
}
