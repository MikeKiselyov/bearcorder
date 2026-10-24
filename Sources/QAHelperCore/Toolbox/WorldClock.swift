import Foundation

/// Time zone search and comparison against the user's own zone.
public enum WorldClock {
    public enum DayPart: String {
        case night
        case morning
        case work
        case evening

        public var title: String {
            switch self {
            case .night: return "Night"
            case .morning: return "Morning"
            case .work: return "Working hours"
            case .evening: return "Evening"
            }
        }
    }

    public struct Comparison: Identifiable {
        public var id: String { identifier }
        public var identifier: String
        public var city: String
        public var region: String
        public var abbreviation: String
        public var offsetText: String
        /// Difference to the reference zone, e.g. "+2h", "−5h 30m", "same time".
        public var differenceText: String
        public var differenceSeconds: Int
        public var time: String
        public var date: String
        public var dayHint: String
        public var dayPart: DayPart
        public var isDaylightSaving: Bool
    }

    /// Cities and countries people search for that are not part of a zone identifier.
    static let aliases: [String: String] = [
        "kyiv": "Europe/Kyiv", "kiev": "Europe/Kyiv", "ukraine": "Europe/Kyiv",
        "belarus": "Europe/Minsk", "poland": "Europe/Warsaw", "germany": "Europe/Berlin",
        "france": "Europe/Paris", "spain": "Europe/Madrid", "portugal": "Europe/Lisbon",
        "uk": "Europe/London", "britain": "Europe/London", "england": "Europe/London",
        "ireland": "Europe/Dublin", "netherlands": "Europe/Amsterdam", "italy": "Europe/Rome",
        "turkey": "Europe/Istanbul", "türkiye": "Europe/Istanbul", "russia": "Europe/Moscow",
        "georgia": "Asia/Tbilisi", "armenia": "Asia/Yerevan", "kazakhstan": "Asia/Almaty",
        "uzbekistan": "Asia/Tashkent", "uae": "Asia/Dubai", "emirates": "Asia/Dubai",
        "israel": "Asia/Jerusalem", "india": "Asia/Kolkata", "mumbai": "Asia/Kolkata",
        "delhi": "Asia/Kolkata", "bangalore": "Asia/Kolkata", "bengaluru": "Asia/Kolkata",
        "china": "Asia/Shanghai", "beijing": "Asia/Shanghai", "japan": "Asia/Tokyo",
        "korea": "Asia/Seoul", "vietnam": "Asia/Ho_Chi_Minh", "thailand": "Asia/Bangkok",
        "indonesia": "Asia/Jakarta", "bali": "Asia/Makassar", "philippines": "Asia/Manila",
        "australia": "Australia/Sydney", "new zealand": "Pacific/Auckland",
        "usa": "America/New_York", "us": "America/New_York", "east coast": "America/New_York",
        "west coast": "America/Los_Angeles", "san francisco": "America/Los_Angeles",
        "silicon valley": "America/Los_Angeles", "seattle": "America/Los_Angeles",
        "austin": "America/Chicago", "texas": "America/Chicago", "boston": "America/New_York",
        "canada": "America/Toronto", "mexico": "America/Mexico_City", "brazil": "America/Sao_Paulo",
        "argentina": "America/Argentina/Buenos_Aires", "chile": "America/Santiago",
        "egypt": "Africa/Cairo", "nigeria": "Africa/Lagos", "south africa": "Africa/Johannesburg",
        "kenya": "Africa/Nairobi", "cyprus": "Asia/Nicosia", "serbia": "Europe/Belgrade",
        "montenegro": "Europe/Podgorica", "czech": "Europe/Prague", "lithuania": "Europe/Vilnius",
        "latvia": "Europe/Riga", "estonia": "Europe/Tallinn", "finland": "Europe/Helsinki",
        "sweden": "Europe/Stockholm", "norway": "Europe/Oslo", "switzerland": "Europe/Zurich",
        "greece": "Europe/Athens", "utc": "UTC", "gmt": "GMT",
    ]

    /// macOS still lists some zones under old names; show the current ones.
    static let modernNames: [String: String] = [
        "Asia/Calcutta": "Asia/Kolkata", "Asia/Saigon": "Asia/Ho_Chi_Minh", "Asia/Katmandu": "Asia/Kathmandu",
        "Asia/Rangoon": "Asia/Yangon", "Europe/Kiev": "Europe/Kyiv", "America/Godthab": "America/Nuuk",
        "Atlantic/Faeroe": "Atlantic/Faroe", "Asia/Ulan_Bator": "Asia/Ulaanbaatar",
    ]

    static func modernName(_ identifier: String) -> String {
        if let modern = modernNames[identifier], TimeZone(identifier: modern) != nil {
            return modern
        }
        return identifier
    }

    public static func city(of identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    public static func region(of identifier: String) -> String {
        let parts = identifier.split(separator: "/").map(String.init)
        if parts.count < 2 { return "" }
        return parts[0].replacingOccurrences(of: "_", with: " ")
    }

    public static func offsetText(seconds: Int) -> String {
        if seconds == 0 { return "UTC" }
        let sign = seconds > 0 ? "+" : "−"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        if minutes == 0 { return "UTC\(sign)\(hours)" }
        return String(format: "UTC%@%d:%02d", sign, hours, minutes)
    }

    public static func differenceText(seconds: Int) -> String {
        if seconds == 0 { return "same time" }
        let sign = seconds > 0 ? "+" : "−"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        if minutes == 0 { return "\(sign)\(hours)h" }
        if hours == 0 { return "\(sign)\(minutes)m" }
        return "\(sign)\(hours)h \(minutes)m"
    }

    /// Parses "+3", "-5", "UTC+5:30", "GMT-8", "+0530" into seconds from UTC.
    static func parseOffset(_ query: String) -> Int? {
        var text = query.lowercased().replacingOccurrences(of: " ", with: "")
        for prefix in ["utc", "gmt"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        guard let first = text.first, first == "+" || first == "-" || first == "−" else { return nil }
        let sign = first == "+" ? 1 : -1
        let body = String(text.dropFirst())
        var hours = 0
        var minutes = 0
        if body.contains(":") {
            let pieces = body.split(separator: ":").map(String.init)
            guard pieces.count == 2, let hourValue = Int(pieces[0]), let minuteValue = Int(pieces[1]) else { return nil }
            hours = hourValue
            minutes = minuteValue
        } else if body.count == 4, let value = Int(body) {
            hours = value / 100
            minutes = value % 100
        } else if let value = Int(body) {
            hours = value
        } else {
            return nil
        }
        if hours > 14 || minutes >= 60 { return nil }
        return sign * (hours * 3600 + minutes * 60)
    }

    /// Zone identifiers matching a city, country, region, abbreviation or UTC offset.
    public static func search(_ query: String, at date: Date = Date(), limit: Int = 40) -> [String] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = TimeZone.knownTimeZoneIdentifiers
        if text.isEmpty { return Array(all.prefix(limit)) }

        var results: [String] = []
        func add(_ identifier: String) {
            let name = modernName(identifier)
            if !results.contains(name) && TimeZone(identifier: name) != nil {
                results.append(name)
            }
        }

        if let offset = parseOffset(text) {
            for identifier in all {
                if TimeZone(identifier: identifier)?.secondsFromGMT(for: date) == offset {
                    add(identifier)
                }
            }
            return Array(results.prefix(limit))
        }

        // Exact alias or city first, then prefix matches, then anything containing the text.
        if let alias = aliases[text] {
            add(alias)
        }
        for identifier in all where city(of: identifier).lowercased() == text {
            add(identifier)
        }
        for (name, identifier) in aliases.sorted(by: { first, second in first.key < second.key }) where name.hasPrefix(text) {
            add(identifier)
        }
        for identifier in all where city(of: modernName(identifier)).lowercased().hasPrefix(text) {
            add(identifier)
        }
        let english = Locale(identifier: "en_US")
        for identifier in all {
            guard let zone = TimeZone(identifier: identifier) else { continue }
            let abbreviation = (zone.abbreviation(for: date) ?? "").lowercased()
            let name = (zone.localizedName(for: .generic, locale: english) ?? "").lowercased()
            let standard = (zone.localizedName(for: .standard, locale: english) ?? "").lowercased()
            if abbreviation == text || identifier.lowercased().contains(text) || name.contains(text) || standard.contains(text) {
                add(identifier)
            }
        }
        return Array(results.prefix(limit))
    }

    public static func dayPart(hour: Int) -> DayPart {
        if hour >= 9 && hour < 18 { return .work }
        if hour >= 7 && hour < 9 { return .morning }
        if hour >= 18 && hour < 23 { return .evening }
        return .night
    }

    public static func compare(_ identifier: String, at date: Date, reference: TimeZone) -> Comparison? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        let offset = zone.secondsFromGMT(for: date)
        let difference = offset - reference.secondsFromGMT(for: date)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        let zoneTime = TimeConverter.zoneTime(date, zone: zone, localZone: reference)
        return Comparison(
            identifier: identifier,
            city: city(of: identifier),
            region: region(of: identifier),
            abbreviation: zone.abbreviation(for: date) ?? "",
            offsetText: offsetText(seconds: offset),
            differenceText: differenceText(seconds: difference),
            differenceSeconds: difference,
            time: zoneTime.time,
            date: TimeConverter.format(date, pattern: "EEE d MMM", timeZone: zone),
            dayHint: zoneTime.dayHint,
            dayPart: dayPart(hour: hour),
            isDaylightSaving: zone.isDaylightSavingTime(for: date)
        )
    }

    /// For each hour of the reference day (0…23), the hour in `zone`. Fractional zones round down.
    public static func hourStrip(for zone: TimeZone, on day: Date, reference: TimeZone) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reference
        let start = calendar.startOfDay(for: day)
        var zoneCalendar = Calendar(identifier: .gregorian)
        zoneCalendar.timeZone = zone
        var hours: [Int] = []
        for index in 0..<24 {
            let moment = start.addingTimeInterval(Double(index) * 3600)
            hours.append(zoneCalendar.component(.hour, from: moment))
        }
        return hours
    }

    /// Reference-day hours where every zone is inside working hours: the meeting window.
    public static func sharedWorkingHours(zones: [TimeZone], on day: Date, reference: TimeZone) -> [Int] {
        var shared: [Int] = []
        let strips = zones.map { zone in hourStrip(for: zone, on: day, reference: reference) }
        for hour in 0..<24 {
            var everyoneWorking = true
            for strip in strips where dayPart(hour: strip[hour]) != .work {
                everyoneWorking = false
            }
            if everyoneWorking {
                shared.append(hour)
            }
        }
        return shared
    }
}
