import Foundation

/// Standard 5-field cron (minute hour day-of-month month day-of-week) with `*`, lists, ranges, steps,
/// month and weekday names, and @hourly / @daily / @weekly / @monthly / @yearly.
public struct CronExpression: Equatable {
    public var minutes: Set<Int>
    public var hours: Set<Int>
    public var daysOfMonth: Set<Int>
    public var months: Set<Int>
    /// 0 = Sunday … 6 = Saturday (7 is read as Sunday).
    public var daysOfWeek: Set<Int>
    /// Which fields were `*`: cron matches a day when either day field matches if both are restricted.
    var dayOfMonthIsAny: Bool
    var dayOfWeekIsAny: Bool
    public var source: String

    public struct ParseError: Error, Equatable {
        public var message: String
    }

    static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let dayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    static let fullDayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let fullMonthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    public static func parse(_ text: String) throws -> CronExpression {
        var expression = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch expression.lowercased() {
        case "@yearly", "@annually": expression = "0 0 1 1 *"
        case "@monthly": expression = "0 0 1 * *"
        case "@weekly": expression = "0 0 * * 0"
        case "@daily", "@midnight": expression = "0 0 * * *"
        case "@hourly": expression = "0 * * * *"
        default: break
        }
        let fields = expression.split(whereSeparator: { character in character == " " || character == "\t" })
        if fields.count != 5 {
            throw ParseError(message: "Expected 5 fields (minute hour day month weekday), got \(fields.count)")
        }
        let minutes = try parseField(String(fields[0]), range: 0...59, names: [], nameOffset: 0, label: "minute")
        let hours = try parseField(String(fields[1]), range: 0...23, names: [], nameOffset: 0, label: "hour")
        let days = try parseField(String(fields[2]), range: 1...31, names: [], nameOffset: 0, label: "day of month")
        let months = try parseField(String(fields[3]), range: 1...12, names: monthNames, nameOffset: 1, label: "month")
        var weekdays = try parseField(String(fields[4]), range: 0...7, names: dayNames, nameOffset: 0, label: "weekday")
        if weekdays.contains(7) {
            weekdays.remove(7)
            weekdays.insert(0)
        }
        return CronExpression(minutes: minutes, hours: hours, daysOfMonth: days, months: months, daysOfWeek: weekdays, dayOfMonthIsAny: fields[2] == "*" || fields[2] == "?", dayOfWeekIsAny: fields[4] == "*" || fields[4] == "?", source: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func parseField(_ field: String, range: ClosedRange<Int>, names: [String], nameOffset: Int, label: String) throws -> Set<Int> {
        var values: Set<Int> = []
        for part in field.split(separator: ",") {
            var body = String(part)
            var step = 1
            if let slash = body.firstIndex(of: "/") {
                guard let parsedStep = Int(body[body.index(after: slash)...]), parsedStep > 0 else {
                    throw ParseError(message: "Bad step in \(label): \(part)")
                }
                step = parsedStep
                body = String(body[..<slash])
            }
            var low = range.lowerBound
            var high = range.upperBound
            if body == "*" || body == "?" {
                // whole range
            } else if let dash = body.firstIndex(of: "-") {
                low = try number(String(body[..<dash]), names: names, nameOffset: nameOffset, label: label)
                high = try number(String(body[body.index(after: dash)...]), names: names, nameOffset: nameOffset, label: label)
            } else {
                low = try number(body, names: names, nameOffset: nameOffset, label: label)
                high = low
                if step > 1 {
                    high = range.upperBound
                }
            }
            if !range.contains(low) || !range.contains(high) || low > high {
                throw ParseError(message: "\(label.capitalized) out of range: \(part)")
            }
            var value = low
            while value <= high {
                values.insert(value)
                value += step
            }
        }
        if values.isEmpty {
            throw ParseError(message: "Empty \(label)")
        }
        return values
    }

    private static func number(_ text: String, names: [String], nameOffset: Int, label: String) throws -> Int {
        if let value = Int(text) {
            return value
        }
        if let position = names.firstIndex(of: text.uppercased()) {
            return position + nameOffset
        }
        throw ParseError(message: "Unknown \(label): \(text)")
    }

    func matches(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        guard let minute = parts.minute, let hour = parts.hour, let day = parts.day, let month = parts.month, let weekday = parts.weekday else { return false }
        if !minutes.contains(minute) || !hours.contains(hour) || !months.contains(month) {
            return false
        }
        return dayMatches(day: day, weekday: weekday - 1)
    }

    func dayMatches(day: Int, weekday: Int) -> Bool {
        let dayOfMonthMatch = daysOfMonth.contains(day)
        let dayOfWeekMatch = daysOfWeek.contains(weekday)
        if !dayOfMonthIsAny && !dayOfWeekIsAny {
            return dayOfMonthMatch || dayOfWeekMatch
        }
        return dayOfMonthMatch && dayOfWeekMatch
    }

    /// The next `count` run times after `date`, looking at most about 5 years ahead.
    public func nextRuns(after date: Date, count: Int, timeZone: TimeZone = .current) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var runs: [Date] = []
        guard var current = calendar.date(bySetting: .second, value: 0, of: date.addingTimeInterval(60)) else { return runs }
        if current <= date {
            current = current.addingTimeInterval(60)
        }
        let limit = date.addingTimeInterval(5 * 366 * 24 * 3600)
        while runs.count < count && current < limit {
            let parts = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: current)
            let month = parts.month ?? 1
            let day = parts.day ?? 1
            let weekday = (parts.weekday ?? 1) - 1
            let hour = parts.hour ?? 0
            let minute = parts.minute ?? 0
            // Skip whole months, days and hours that cannot match.
            if !months.contains(month) {
                current = startOfNextMonth(current, calendar: calendar)
            } else if !dayMatches(day: day, weekday: weekday) {
                current = calendar.startOfDay(for: current).addingTimeInterval(24 * 3600)
                current = calendar.startOfDay(for: current)
            } else if !hours.contains(hour) {
                current = calendar.date(byAdding: .hour, value: 1, to: current) ?? limit
                current = calendar.date(bySetting: .minute, value: 0, of: current) ?? limit
            } else if !minutes.contains(minute) {
                current = current.addingTimeInterval(60)
            } else {
                runs.append(current)
                current = current.addingTimeInterval(60)
            }
        }
        return runs
    }

    private func startOfNextMonth(_ date: Date, calendar: Calendar) -> Date {
        var parts = calendar.dateComponents([.year, .month], from: date)
        parts.month = (parts.month ?? 1) + 1
        parts.day = 1
        parts.hour = 0
        parts.minute = 0
        return calendar.date(from: parts) ?? date.addingTimeInterval(31 * 24 * 3600)
    }

    // MARK: Description

    /// Plain English, e.g. "At 09:30, Monday through Friday".
    public var description: String {
        var sentence = timePhrase()
        if !dayOfMonthIsAny {
            sentence += ", on day \(listText(daysOfMonth, full: 1...31)) of the month"
        }
        if !dayOfWeekIsAny {
            var connector = ", "
            if !dayOfMonthIsAny {
                connector = " or "
            }
            sentence += connector + weekdayText()
        }
        if months.count < 12 {
            sentence += ", in " + monthText()
        }
        return sentence
    }

    private func timePhrase() -> String {
        if minutes.count == 1 && hours.count == 1, let minute = minutes.first, let hour = hours.first {
            return String(format: "At %02d:%02d", hour, minute)
        }
        if minutes.count == 60 && hours.count == 24 {
            return "Every minute"
        }
        if hours.count == 24 {
            if let step = stepOf(minutes, from: 0, count: 60) {
                return "Every \(step) minutes"
            }
            if minutes.count == 1, let minute = minutes.first {
                return "At minute \(minute) of every hour"
            }
            return "At minutes \(listText(minutes, full: 0...59)) of every hour"
        }
        if minutes.count == 1, let minute = minutes.first {
            var times: [String] = []
            for hour in hours.sorted() {
                times.append(String(format: "%02d:%02d", hour, minute))
            }
            if times.count <= 6 {
                return "At " + times.joined(separator: ", ")
            }
            return "At minute \(minute) past hours \(listText(hours, full: 0...23))"
        }
        return "At minutes \(listText(minutes, full: 0...59)) past hours \(listText(hours, full: 0...23))"
    }

    private func stepOf(_ values: Set<Int>, from start: Int, count: Int) -> Int? {
        let sorted = values.sorted()
        if sorted.count < 2 || sorted.first != start { return nil }
        let step = sorted[1] - sorted[0]
        for index in 1..<sorted.count where sorted[index] - sorted[index - 1] != step {
            return nil
        }
        if sorted.count != (count + step - 1) / step { return nil }
        return step
    }

    private func weekdayText() -> String {
        let sorted = daysOfWeek.sorted()
        if sorted == [1, 2, 3, 4, 5] {
            return "Monday through Friday"
        }
        if sorted == [0, 6] {
            return "on weekends"
        }
        var names: [String] = []
        for day in sorted {
            names.append(CronExpression.fullDayNames[day])
        }
        return "on " + names.joined(separator: ", ")
    }

    private func monthText() -> String {
        var names: [String] = []
        for month in months.sorted() {
            names.append(CronExpression.fullMonthNames[month - 1])
        }
        return names.joined(separator: ", ")
    }

    /// "1-5", "1, 15", "every 2nd" style lists.
    private func listText(_ values: Set<Int>, full: ClosedRange<Int>) -> String {
        let sorted = values.sorted()
        var parts: [String] = []
        var runStart = sorted[0]
        var previous = sorted[0]
        for value in sorted.dropFirst() {
            if value == previous + 1 {
                previous = value
                continue
            }
            parts.append(rangeText(runStart, previous))
            runStart = value
            previous = value
        }
        parts.append(rangeText(runStart, previous))
        return parts.joined(separator: ", ")
    }

    private func rangeText(_ start: Int, _ end: Int) -> String {
        if start == end {
            return "\(start)"
        }
        return "\(start)-\(end)"
    }
}
