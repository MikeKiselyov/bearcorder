import Foundation

/// Repeatable random numbers for tests (SplitMix64).
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Fake but well-formed data for filling forms: people, cards, IBANs, passwords and tricky strings.
public enum TestData {
    public struct Person: Equatable {
        public var firstName: String
        public var lastName: String
        public var email: String
        public var phone: String
    }

    public enum CardBrand: String, CaseIterable, Identifiable {
        case visa = "Visa"
        case mastercard = "Mastercard"
        case amex = "Amex"
        case mir = "Mir"

        public var id: String { rawValue }

        var prefixes: [String] {
            switch self {
            case .visa: return ["4"]
            case .mastercard: return ["51", "52", "53", "54", "55", "2221", "2720"]
            case .amex: return ["34", "37"]
            case .mir: return ["2200", "2204"]
            }
        }

        var length: Int {
            if self == .amex { return 15 }
            return 16
        }
    }

    public enum PhoneCountry: String, CaseIterable, Identifiable {
        case us = "US"
        case uk = "UK"
        case germany = "DE"
        case belarus = "BY"
        case poland = "PL"

        public var id: String { rawValue }
    }

    public enum IBANCountry: String, CaseIterable, Identifiable {
        case germany = "DE"
        case uk = "GB"
        case netherlands = "NL"
        case poland = "PL"

        public var id: String { rawValue }
    }

    static let firstNames = ["Anna", "Ivan", "Maria", "John", "Olga", "Peter", "Emma", "Liam", "Sofia", "Noah", "Elena", "Max", "Chloe", "Artem", "Lucas", "Mia"]
    static let lastNames = ["Smith", "Ivanova", "Kowalski", "Müller", "Johnson", "Petrov", "Garcia", "Brown", "Novak", "Taylor", "Schmidt", "O'Brien", "Lee", "Fischer"]
    /// Reserved for documentation and tests (RFC 2606): mail never reaches a real person.
    static let emailDomains = ["example.com", "example.org", "test.example"]

    public static func person<Generator: RandomNumberGenerator>(country: PhoneCountry, using generator: inout Generator) -> Person {
        let first = firstNames.randomElement(using: &generator) ?? "Anna"
        let last = lastNames.randomElement(using: &generator) ?? "Smith"
        let domain = emailDomains.randomElement(using: &generator) ?? "example.com"
        let number = Int.random(in: 10...999, using: &generator)
        let local = asciiLower(first) + "." + asciiLower(last) + String(number)
        return Person(firstName: first, lastName: last, email: local + "@" + domain, phone: phone(country: country, using: &generator))
    }

    static func asciiLower(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
        var result = ""
        for character in folded.lowercased() where character.isLetter && character.isASCII {
            result.append(character)
        }
        return result
    }

    /// Numbers from ranges set aside for fiction and testing where a country has one.
    public static func phone<Generator: RandomNumberGenerator>(country: PhoneCountry, using generator: inout Generator) -> String {
        switch country {
        case .us:
            // 555-0100…0199 is reserved for fictional use.
            let area = [201, 312, 415, 512, 617, 718].randomElement(using: &generator) ?? 415
            return "+1 \(area) 555 01\(digits(2, using: &generator))"
        case .uk:
            // Ofcom drama range 07700 900000…900999.
            return "+44 7700 900\(digits(3, using: &generator))"
        case .germany:
            return "+49 151 \(digits(4, using: &generator)) \(digits(4, using: &generator))"
        case .belarus:
            let operatorCode = ["25", "29", "33", "44"].randomElement(using: &generator) ?? "29"
            return "+375 \(operatorCode) \(digits(3, using: &generator))-\(digits(2, using: &generator))-\(digits(2, using: &generator))"
        case .poland:
            return "+48 5\(digits(2, using: &generator)) \(digits(3, using: &generator)) \(digits(3, using: &generator))"
        }
    }

    static func digits<Generator: RandomNumberGenerator>(_ count: Int, using generator: inout Generator) -> String {
        var text = ""
        for _ in 0..<count {
            text += String(Int.random(in: 0...9, using: &generator))
        }
        return text
    }

    // MARK: Cards

    /// A random number with a valid Luhn check digit. Not a real card; payment test gateways accept the format.
    public static func cardNumber<Generator: RandomNumberGenerator>(brand: CardBrand, using generator: inout Generator) -> String {
        let prefix = brand.prefixes.randomElement(using: &generator) ?? "4"
        var number = prefix + digits(brand.length - prefix.count - 1, using: &generator)
        number += String(luhnCheckDigit(for: number))
        return groupCard(number)
    }

    static func groupCard(_ number: String) -> String {
        var groups: [String] = []
        var sizes = [4, 4, 4, 4]
        if number.count == 15 {
            sizes = [4, 6, 5]
        }
        var start = number.startIndex
        for size in sizes {
            let end = number.index(start, offsetBy: size, limitedBy: number.endIndex) ?? number.endIndex
            groups.append(String(number[start..<end]))
            start = end
        }
        return groups.joined(separator: " ")
    }

    static func luhnCheckDigit(for payload: String) -> Int {
        var sum = 0
        var double = true
        for character in payload.reversed() {
            var value = Int(String(character)) ?? 0
            if double {
                value *= 2
                if value > 9 {
                    value -= 9
                }
            }
            sum += value
            double = !double
        }
        return (10 - sum % 10) % 10
    }

    /// True when the digits (spaces and dashes ignored) pass the Luhn check.
    public static func isValidLuhn(_ text: String) -> Bool {
        var digitsOnly = ""
        for character in text where character != " " && character != "-" {
            if !character.isASCII || !character.isNumber { return false }
            digitsOnly.append(character)
        }
        if digitsOnly.count < 12 { return false }
        let payload = String(digitsOnly.dropLast())
        let check = Int(String(digitsOnly.last ?? "0")) ?? -1
        return luhnCheckDigit(for: payload) == check
    }

    /// Expiry in the future, "MM/YY".
    public static func cardExpiry<Generator: RandomNumberGenerator>(now: Date = Date(), using generator: inout Generator) -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: now) % 100
        let month = Int.random(in: 1...12, using: &generator)
        let futureYear = year + Int.random(in: 1...5, using: &generator)
        return String(format: "%02d/%02d", month, futureYear)
    }

    // MARK: IBAN

    public static func iban<Generator: RandomNumberGenerator>(country: IBANCountry, using generator: inout Generator) -> String {
        var basicAccount = ""
        switch country {
        case .germany:
            basicAccount = digits(18, using: &generator)
        case .uk:
            let bank = ["NWBK", "BARC", "HBUK", "LOYD"].randomElement(using: &generator) ?? "NWBK"
            basicAccount = bank + digits(14, using: &generator)
        case .netherlands:
            let bank = ["ABNA", "INGB", "RABO"].randomElement(using: &generator) ?? "INGB"
            basicAccount = bank + digits(10, using: &generator)
        case .poland:
            basicAccount = digits(24, using: &generator)
        }
        let check = ibanCheckDigits(country: country.rawValue, basicAccount: basicAccount)
        return groupIBAN(country.rawValue + check + basicAccount)
    }

    static func ibanCheckDigits(country: String, basicAccount: String) -> String {
        let remainder = mod97(basicAccount + country + "00")
        return String(format: "%02d", 98 - remainder)
    }

    /// Letters become 10…35, then the number is reduced modulo 97 piece by piece.
    static func mod97(_ text: String) -> Int {
        var remainder = 0
        for character in text.uppercased() {
            var piece = ""
            if character.isNumber {
                piece = String(character)
            } else if let ascii = character.asciiValue, character.isLetter {
                piece = String(Int(ascii) - 55)
            } else {
                continue
            }
            for digit in piece {
                remainder = (remainder * 10 + (Int(String(digit)) ?? 0)) % 97
            }
        }
        return remainder
    }

    static func groupIBAN(_ iban: String) -> String {
        var result = ""
        for (index, character) in iban.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result.append(character)
        }
        return result
    }

    public static func isValidIBAN(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").uppercased()
        if compact.count < 15 || compact.count > 34 { return false }
        for character in compact where !(character.isASCII && (character.isLetter || character.isNumber)) {
            return false
        }
        let rearranged = String(compact.dropFirst(4)) + String(compact.prefix(4))
        return mod97(rearranged) == 1
    }

    // MARK: Passwords

    public struct PasswordRules {
        public var length: Int
        public var uppercase: Bool
        public var digits: Bool
        public var symbols: Bool

        public init(length: Int = 16, uppercase: Bool = true, digits: Bool = true, symbols: Bool = true) {
            self.length = length
            self.uppercase = uppercase
            self.digits = digits
            self.symbols = symbols
        }
    }

    static let lowerLetters = Array("abcdefghijkmnopqrstuvwxyz")
    static let upperLetters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let digitCharacters = Array("23456789")
    static let symbolCharacters = Array("!@#$%^&*-_=+?")

    /// At least one character of every enabled kind; look-alikes (l, 1, O, 0) are left out.
    public static func password<Generator: RandomNumberGenerator>(_ rules: PasswordRules, using generator: inout Generator) -> String {
        var groups: [[Character]] = [lowerLetters]
        if rules.uppercase { groups.append(upperLetters) }
        if rules.digits { groups.append(digitCharacters) }
        if rules.symbols { groups.append(symbolCharacters) }
        var all: [Character] = []
        for group in groups {
            all.append(contentsOf: group)
        }
        var characters: [Character] = []
        for group in groups {
            if let character = group.randomElement(using: &generator) {
                characters.append(character)
            }
        }
        let length = max(rules.length, groups.count)
        while characters.count < length {
            if let character = all.randomElement(using: &generator) {
                characters.append(character)
            }
        }
        characters.shuffle(using: &generator)
        return String(characters)
    }

    // MARK: Tricky strings

    public struct EdgeCase: Identifiable {
        public var id: String { name }
        public var name: String
        public var value: String
    }

    /// Inputs that often break forms, layouts and backends.
    public static let edgeCases: [EdgeCase] = [
        EdgeCase(name: "Empty-looking (spaces)", value: "   "),
        EdgeCase(name: "Leading and trailing spaces", value: "  Anna  "),
        EdgeCase(name: "Apostrophe in name", value: "O'Brien"),
        EdgeCase(name: "Hyphen and diacritics", value: "Zoë Müller-Łukasiewicz"),
        EdgeCase(name: "Cyrillic", value: "Ёлка Щукина"),
        EdgeCase(name: "Right-to-left", value: "مرحبا بالعالم"),
        EdgeCase(name: "CJK", value: "测试用户名"),
        EdgeCase(name: "Emoji with joiners", value: "👩🏽‍💻🏳️‍🌈👨‍👩‍👧"),
        EdgeCase(name: "Combining marks", value: "Z̴̡̛a̷l̸g̵o̶"),
        EdgeCase(name: "HTML injection", value: "<b>bold</b><img src=x onerror=alert(1)>"),
        EdgeCase(name: "Script tag", value: "<script>alert('xss')</script>"),
        EdgeCase(name: "SQL quote", value: "Robert'); DROP TABLE students;--"),
        EdgeCase(name: "Template braces", value: "{{7*7}} ${7*7} #{7*7}"),
        EdgeCase(name: "Path traversal", value: "../../etc/passwd"),
        EdgeCase(name: "Email with plus tag", value: "anna+qa1@example.com"),
        EdgeCase(name: "Very long word (300 chars)", value: String(repeating: "W", count: 300)),
        EdgeCase(name: "Number edge: max Int32", value: "2147483647"),
        EdgeCase(name: "Number edge: negative zero", value: "-0"),
        EdgeCase(name: "Decimal comma", value: "1,5"),
        EdgeCase(name: "Zero-width space inside", value: "ad\u{200B}min"),
        EdgeCase(name: "Line break inside", value: "first line\nsecond line"),
    ]
}
