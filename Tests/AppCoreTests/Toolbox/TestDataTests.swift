import XCTest
@testable import AppCore

final class TestDataTests: XCTestCase {
    func testCardsPassLuhnForEveryBrand() {
        var generator = SeededGenerator(seed: 42)
        for brand in TestData.CardBrand.allCases {
            for _ in 0..<50 {
                let number = TestData.cardNumber(brand: brand, using: &generator)
                XCTAssertTrue(TestData.isValidLuhn(number), "\(brand) \(number)")
                let digitCount = number.replacingOccurrences(of: " ", with: "").count
                XCTAssertEqual(digitCount, brand == .amex ? 15 : 16)
            }
        }
    }

    func testLuhnKnownNumbers() {
        XCTAssertTrue(TestData.isValidLuhn("4242 4242 4242 4242"))
        XCTAssertFalse(TestData.isValidLuhn("4242 4242 4242 4241"))
        XCTAssertFalse(TestData.isValidLuhn("abcd"))
    }

    func testIBANsAreValid() {
        XCTAssertTrue(TestData.isValidIBAN("GB82 WEST 1234 5698 7654 32"))
        XCTAssertTrue(TestData.isValidIBAN("DE89370400440532013000"))
        XCTAssertFalse(TestData.isValidIBAN("DE89370400440532013001"))
        var generator = SeededGenerator(seed: 7)
        for country in TestData.IBANCountry.allCases {
            for _ in 0..<20 {
                let iban = TestData.iban(country: country, using: &generator)
                XCTAssertTrue(TestData.isValidIBAN(iban), iban)
                XCTAssertTrue(iban.hasPrefix(country.rawValue))
            }
        }
    }

    func testPasswordFollowsRules() {
        var generator = SeededGenerator(seed: 1)
        let rules = TestData.PasswordRules(length: 12, uppercase: true, digits: true, symbols: false)
        for _ in 0..<50 {
            let password = TestData.password(rules, using: &generator)
            XCTAssertEqual(password.count, 12)
            XCTAssertTrue(password.contains { character in character.isUppercase })
            XCTAssertTrue(password.contains { character in character.isNumber })
            XCTAssertFalse(password.contains { character in "!@#$%^&*-_=+?".contains(character) })
        }
    }

    func testPersonUsesReservedDomainsAndFictionalPhones() {
        var generator = SeededGenerator(seed: 3)
        let person = TestData.person(country: .us, using: &generator)
        XCTAssertTrue(person.email.hasSuffix("example.com") || person.email.hasSuffix("example.org") || person.email.hasSuffix("test.example"))
        XCTAssertTrue(person.phone.contains(" 555 01"))
        let ukPhone = TestData.phone(country: .uk, using: &generator)
        XCTAssertTrue(ukPhone.hasPrefix("+44 7700 900"))
        XCTAssertEqual(TestData.asciiLower("Müller"), "muller")
    }

    func testSameSeedSameData() {
        var first = SeededGenerator(seed: 9)
        var second = SeededGenerator(seed: 9)
        XCTAssertEqual(TestData.person(country: .germany, using: &first), TestData.person(country: .germany, using: &second))
    }
}

final class RegexTesterTests: XCTestCase {
    func testMatchesWithNamedAndNumberedGroups() {
        let result = RegexTester.run(pattern: #"(?<user>\w+)@(\w+)\.com"#, text: "anna@mail.com, bob@site.com", options: RegexTester.Options())
        XCTAssertEqual(result.matches.count, 2)
        XCTAssertEqual(result.matches[0].value, "anna@mail.com")
        XCTAssertEqual(result.matches[0].groups, [RegexTester.Group(name: "user", value: "anna"), RegexTester.Group(name: "2", value: "mail")])
        XCTAssertEqual(result.matches[1].range, NSRange(location: 15, length: 12))
    }

    func testOptionsAndReplacement() {
        var options = RegexTester.Options()
        options.caseInsensitive = true
        let result = RegexTester.run(pattern: "^error", text: "Error one\nok\nERROR two", options: options, replacement: "WARN")
        XCTAssertEqual(result.matches.count, 2)
        XCTAssertEqual(result.replaced, "WARN one\nok\nWARN two")
    }

    func testInvalidPatternAndOptionalGroup() {
        XCTAssertEqual(RegexTester.run(pattern: "(", text: "x", options: RegexTester.Options()).error, "Invalid pattern")
        let result = RegexTester.run(pattern: "a(b)?(?:c)", text: "ac", options: RegexTester.Options())
        XCTAssertEqual(result.matches.first?.groups, [RegexTester.Group(name: "1", value: nil)])
    }
}
