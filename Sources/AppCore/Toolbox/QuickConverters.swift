import Foundation

// MARK: - Number base

public struct NumberBases {
    public var decimal: String
    public var hex: String
    public var binary: String
    public var octal: String
}

public enum NumberBaseConverter {
    /// Accepts 255, 0xFF, 0b1111_1111, 0o377, or a plain hex string with letters.
    public static func parse(_ input: String) -> Int64? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        text = text.replacingOccurrences(of: "_", with: "")
        text = text.replacingOccurrences(of: " ", with: "")
        var negative = false
        if text.hasPrefix("-") {
            negative = true
            text = String(text.dropFirst())
        }
        var value: Int64? = nil
        if text.hasPrefix("0x") {
            value = Int64(text.dropFirst(2), radix: 16)
        } else if text.hasPrefix("#") {
            value = Int64(text.dropFirst(1), radix: 16)
        } else if text.hasPrefix("0b") {
            value = Int64(text.dropFirst(2), radix: 2)
        } else if text.hasPrefix("0o") {
            value = Int64(text.dropFirst(2), radix: 8)
        } else if let decimal = Int64(text) {
            value = decimal
        } else {
            value = Int64(text, radix: 16)
        }
        guard let result = value else { return nil }
        return negative ? -result : result
    }

    public static func convert(_ input: String) -> NumberBases? {
        guard let value = parse(input) else { return nil }
        let magnitude = value.magnitude
        let sign = value < 0 ? "-" : ""
        let binaryDigits = String(magnitude, radix: 2)
        return NumberBases(
            decimal: String(value),
            hex: sign + "0x" + String(magnitude, radix: 16).uppercased(),
            binary: sign + groupBinary(binaryDigits),
            octal: sign + "0o" + String(magnitude, radix: 8)
        )
    }

    static func groupBinary(_ digits: String) -> String {
        var padded = digits
        let remainder = padded.count % 4
        if remainder != 0 {
            padded = String(repeating: "0", count: 4 - remainder) + padded
        }
        var groups: [String] = []
        var current = ""
        for character in padded {
            current.append(character)
            if current.count == 4 {
                groups.append(current)
                current = ""
            }
        }
        return groups.joined(separator: " ")
    }
}

// MARK: - Color

public struct RGBAColor: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct ColorFormats {
    public var hex: String
    public var rgb: String
    public var hsl: String
    public var swiftUI: String
    public var uiKit: String
    public var android: String
}

public enum ColorConverter {
    public static func parse(_ input: String) -> RGBAColor? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") || isHexColor(text) {
            return parseHex(text.replacingOccurrences(of: "#", with: ""))
        }
        if text.hasPrefix("0x") {
            return parseHex(String(text.dropFirst(2)))
        }
        if text.hasPrefix("rgb") {
            let numbers = extractNumbers(text)
            if numbers.count >= 3 {
                var alpha = 1.0
                if numbers.count >= 4 { alpha = numbers[3] }
                return RGBAColor(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, alpha: alpha)
            }
        }
        if text.hasPrefix("hsl") {
            let numbers = extractNumbers(text)
            if numbers.count >= 3 {
                var alpha = 1.0
                if numbers.count >= 4 { alpha = numbers[3] }
                var color = hslToRGB(hue: numbers[0], saturation: numbers[1] / 100, lightness: numbers[2] / 100)
                color.alpha = alpha
                return color
            }
        }
        // "255 107 74"
        let numbers = extractNumbers(text)
        if numbers.count == 3 && !text.contains(".") {
            return RGBAColor(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255)
        }
        return nil
    }

    static func isHexColor(_ text: String) -> Bool {
        let lengths = [3, 4, 6, 8]
        if !lengths.contains(text.count) { return false }
        for character in text {
            if !character.isHexDigit { return false }
        }
        return true
    }

    static func extractNumbers(_ text: String) -> [Double] {
        var numbers: [Double] = []
        var current = ""
        for character in text {
            if character.isNumber || character == "." || character == "-" {
                current.append(character)
            } else {
                if let value = Double(current) { numbers.append(value) }
                current = ""
            }
        }
        if let value = Double(current) { numbers.append(value) }
        return numbers
    }

    static func parseHex(_ hex: String) -> RGBAColor? {
        var text = hex
        if text.count == 3 || text.count == 4 {
            var expanded = ""
            for character in text {
                expanded.append(character)
                expanded.append(character)
            }
            text = expanded
        }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        if text.count == 6 {
            let red = Double((value >> 16) & 0xFF) / 255
            let green = Double((value >> 8) & 0xFF) / 255
            let blue = Double(value & 0xFF) / 255
            return RGBAColor(red: red, green: green, blue: blue)
        }
        let red = Double((value >> 24) & 0xFF) / 255
        let green = Double((value >> 16) & 0xFF) / 255
        let blue = Double((value >> 8) & 0xFF) / 255
        let alpha = Double(value & 0xFF) / 255
        return RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public static func hslToRGB(hue: Double, saturation: Double, lightness: Double) -> RGBAColor {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let huePrime = (hue.truncatingRemainder(dividingBy: 360)) / 60
        let secondary = chroma * (1 - abs(huePrime.truncatingRemainder(dividingBy: 2) - 1))
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        if huePrime < 1 {
            red = chroma; green = secondary
        } else if huePrime < 2 {
            red = secondary; green = chroma
        } else if huePrime < 3 {
            green = chroma; blue = secondary
        } else if huePrime < 4 {
            green = secondary; blue = chroma
        } else if huePrime < 5 {
            red = secondary; blue = chroma
        } else {
            red = chroma; blue = secondary
        }
        let match = lightness - chroma / 2
        return RGBAColor(red: red + match, green: green + match, blue: blue + match)
    }

    public static func rgbToHSL(_ color: RGBAColor) -> (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(color.red, color.green, color.blue)
        let minimum = min(color.red, color.green, color.blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum
        if delta == 0 {
            return (hue: 0, saturation: 0, lightness: lightness)
        }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue = 0.0
        if maximum == color.red {
            hue = 60 * ((color.green - color.blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == color.green {
            hue = 60 * ((color.blue - color.red) / delta + 2)
        } else {
            hue = 60 * ((color.red - color.green) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        return (hue: hue, saturation: saturation, lightness: lightness)
    }

    public static func formats(_ color: RGBAColor) -> ColorFormats {
        let red = Int((color.red * 255).rounded())
        let green = Int((color.green * 255).rounded())
        let blue = Int((color.blue * 255).rounded())
        var hex = String(format: "#%02X%02X%02X", red, green, blue)
        if color.alpha < 1 {
            hex += String(format: "%02X", Int((color.alpha * 255).rounded()))
        }
        let hsl = rgbToHSL(color)
        var rgbText = "rgb(\(red), \(green), \(blue))"
        var hslText = String(format: "hsl(%.0f, %.0f%%, %.0f%%)", hsl.hue, hsl.saturation * 100, hsl.lightness * 100)
        if color.alpha < 1 {
            rgbText = String(format: "rgba(\(red), \(green), \(blue), %.2f)", color.alpha)
            hslText = String(format: "hsla(%.0f, %.0f%%, %.0f%%, %.2f)", hsl.hue, hsl.saturation * 100, hsl.lightness * 100, color.alpha)
        }
        let swiftUI = String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", color.red, color.green, color.blue)
        let uiKit = String(format: "UIColor(red: %.3f, green: %.3f, blue: %.3f, alpha: %.2f)", color.red, color.green, color.blue, color.alpha)
        let android = String(format: "0x%02X%02X%02X%02X", Int((color.alpha * 255).rounded()), red, green, blue)
        return ColorFormats(hex: hex, rgb: rgbText, hsl: hslText, swiftUI: swiftUI, uiKit: uiKit, android: android)
    }
}

// MARK: - Case

public struct CaseVariants {
    public var camel: String
    public var pascal: String
    public var snake: String
    public var kebab: String
    public var constant: String
    public var title: String
    public var lower: String
    public var upper: String
}

public enum CaseConverter {
    /// Splits "orderTotalAmount", "order_total-amount", "Order Total" into words.
    public static func words(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        let characters = Array(input)
        for index in 0..<characters.count {
            let character = characters[index]
            if !character.isLetter && !character.isNumber {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            if character.isUppercase && !current.isEmpty {
                let previous = characters[index - 1]
                var nextIsLower = false
                if index + 1 < characters.count {
                    nextIsLower = characters[index + 1].isLowercase
                }
                // Boundary: "orderTotal" or the "S" in "HTTPServer".
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLower) {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        var lowered: [String] = []
        for word in words {
            lowered.append(word.lowercased())
        }
        return lowered
    }

    public static func variants(_ input: String) -> CaseVariants {
        let parts = words(input)
        var capitalized: [String] = []
        for part in parts {
            capitalized.append(part.prefix(1).uppercased() + part.dropFirst())
        }
        var camel = ""
        for (index, part) in parts.enumerated() {
            if index == 0 {
                camel += part
            } else {
                camel += capitalized[index]
            }
        }
        return CaseVariants(
            camel: camel,
            pascal: capitalized.joined(),
            snake: parts.joined(separator: "_"),
            kebab: parts.joined(separator: "-"),
            constant: parts.joined(separator: "_").uppercased(),
            title: capitalized.joined(separator: " "),
            lower: parts.joined(separator: " "),
            upper: parts.joined(separator: " ").uppercased()
        )
    }
}

// MARK: - Data size

public enum DataSizeConverter {
    /// Parses "5242880", "5 MB", "5MiB", "1.5 GB" into bytes.
    public static func parseBytes(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "")
        var digits = ""
        var unit = ""
        for character in text {
            if character.isNumber || character == "." {
                if !unit.isEmpty { return nil }
                digits.append(character)
            } else {
                unit.append(character)
            }
        }
        guard let value = Double(digits) else { return nil }
        let units: [(names: [String], multiplier: Double)] = [
            (["", "b", "byte", "bytes"], 1),
            (["kb", "k"], 1e3), (["mb", "m"], 1e6), (["gb", "g"], 1e9), (["tb", "t"], 1e12),
            (["kib"], 1024), (["mib"], 1_048_576), (["gib"], 1_073_741_824), (["tib"], 1_099_511_627_776),
        ]
        for entry in units {
            if entry.names.contains(unit) { return value * entry.multiplier }
        }
        return nil
    }

    public static func describe(_ bytes: Double) -> (binary: String, decimal: String, bytes: String) {
        let binaryUnits = ["B", "KiB", "MiB", "GiB", "TiB"]
        let decimalUnits = ["B", "KB", "MB", "GB", "TB"]
        return (
            binary: scaled(bytes, base: 1024, units: binaryUnits),
            decimal: scaled(bytes, base: 1000, units: decimalUnits),
            bytes: String(format: "%.0f B", bytes)
        )
    }

    static func scaled(_ bytes: Double, base: Double, units: [String]) -> String {
        var value = bytes
        var index = 0
        while value >= base && index < units.count - 1 {
            value /= base
            index += 1
        }
        if value == value.rounded() {
            return String(format: "%.0f %@", value, units[index])
        }
        return String(format: "%.2f %@", value, units[index])
    }
}

// MARK: - Duration

public enum DurationConverter {
    /// Parses seconds ("93784"), ISO 8601 ("PT26H3M4S", "P1DT2H") or "1d 2h 3m 4s".
    public static func parseSeconds(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let seconds = Double(text) { return seconds }
        if text.hasPrefix("P") { return parseISO(text) }
        return parseComponents(text.lowercased())
    }

    static func parseISO(_ text: String) -> Double? {
        var total = 0.0
        var number = ""
        var inTime = false
        for character in text.dropFirst() {
            if character == "T" {
                inTime = true
                continue
            }
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            guard let value = Double(number) else { return nil }
            number = ""
            switch character {
            case "W": total += value * 604_800
            case "D": total += value * 86400
            case "H": total += value * 3600
            case "M": total += inTime ? value * 60 : value * 2_592_000
            case "S": total += value
            case "Y": total += value * 31_536_000
            default: return nil
            }
        }
        if !number.isEmpty { return nil }
        return total
    }

    static func parseComponents(_ text: String) -> Double? {
        var total = 0.0
        var number = ""
        var unit = ""
        var found = false
        func commit() -> Bool {
            if number.isEmpty { return true }
            guard let value = Double(number), let seconds = TimeConverter.unitSeconds(unit) else { return false }
            total += value * seconds
            found = true
            number = ""
            unit = ""
            return true
        }
        for character in text {
            if character == " " { continue }
            if character.isNumber || character == "." {
                if !unit.isEmpty {
                    if !commit() { return nil }
                }
                number.append(character)
            } else {
                unit.append(character)
            }
        }
        if !commit() { return nil }
        return found ? total : nil
    }

    public static func describe(_ seconds: Double) -> (components: String, iso: String, milliseconds: String) {
        var remaining = Int(seconds.rounded())
        let days = remaining / 86400
        remaining %= 86400
        let hours = remaining / 3600
        remaining %= 3600
        let minutes = remaining / 60
        let secs = remaining % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if secs > 0 || parts.isEmpty { parts.append("\(secs)s") }

        var iso = "PT"
        let totalHours = days * 24 + hours
        if totalHours > 0 { iso += "\(totalHours)H" }
        if minutes > 0 { iso += "\(minutes)M" }
        if secs > 0 || iso == "PT" { iso += "\(secs)S" }

        return (components: parts.joined(separator: " "), iso: iso, milliseconds: String(format: "%.0f ms", seconds * 1000))
    }
}
