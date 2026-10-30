import Foundation

/// JSON value that keeps object key order and the original number text,
/// so formatting never changes `49.00` into `49`.
public indirect enum JSONValue: Equatable {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.object(let left), .object(let right)):
            if left.count != right.count { return false }
            for index in 0..<left.count {
                if left[index].key != right[index].key { return false }
                if left[index].value != right[index].value { return false }
            }
            return true
        case (.array(let left), .array(let right)):
            return left == right
        case (.string(let left), .string(let right)):
            return left == right
        case (.number(let left), .number(let right)):
            return left == right
        case (.bool(let left), .bool(let right)):
            return left == right
        case (.null, .null):
            return true
        default:
            return false
        }
    }
}

public struct JSONParseError: Error, CustomStringConvertible {
    public let message: String
    public let line: Int
    public let column: Int

    public var description: String {
        return "\(message) at line \(line), column \(column)"
    }
}

public struct JSONParser {
    private let characters: [Character]
    private var position = 0

    public init(_ text: String) {
        self.characters = Array(text)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(text)
        parser.skipWhitespace()
        let value = try parser.parseValue()
        parser.skipWhitespace()
        if parser.position < parser.characters.count {
            throw parser.error("Unexpected content after JSON value")
        }
        return value
    }

    private func error(_ message: String) -> JSONParseError {
        var line = 1
        var column = 1
        var index = 0
        while index < position && index < characters.count {
            if characters[index] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            index += 1
        }
        return JSONParseError(message: message, line: line, column: column)
    }

    private mutating func skipWhitespace() {
        while position < characters.count {
            let character = characters[position]
            if character == " " || character == "\n" || character == "\t" || character == "\r" {
                position += 1
            } else {
                break
            }
        }
    }

    private mutating func parseValue() throws -> JSONValue {
        guard position < characters.count else {
            throw error("Unexpected end of input")
        }
        let character = characters[position]
        if character == "{" { return try parseObject() }
        if character == "[" { return try parseArray() }
        if character == "\"" { return .string(try parseString()) }
        if character == "-" || character.isNumber { return try parseNumber() }
        if matchLiteral("true") { return .bool(true) }
        if matchLiteral("false") { return .bool(false) }
        if matchLiteral("null") { return .null }
        throw error("Unexpected character '\(character)'")
    }

    private mutating func matchLiteral(_ literal: String) -> Bool {
        let literalCharacters = Array(literal)
        if position + literalCharacters.count > characters.count { return false }
        for index in 0..<literalCharacters.count {
            if characters[position + index] != literalCharacters[index] { return false }
        }
        position += literalCharacters.count
        return true
    }

    private mutating func parseObject() throws -> JSONValue {
        position += 1
        var pairs: [(key: String, value: JSONValue)] = []
        skipWhitespace()
        if position < characters.count && characters[position] == "}" {
            position += 1
            return .object(pairs)
        }
        while true {
            skipWhitespace()
            guard position < characters.count, characters[position] == "\"" else {
                throw error("Expected object key in double quotes")
            }
            let key = try parseString()
            skipWhitespace()
            guard position < characters.count, characters[position] == ":" else {
                throw error("Expected ':' after key")
            }
            position += 1
            skipWhitespace()
            let value = try parseValue()
            pairs.append((key: key, value: value))
            skipWhitespace()
            guard position < characters.count else {
                throw error("Unterminated object")
            }
            if characters[position] == "," {
                position += 1
                continue
            }
            if characters[position] == "}" {
                position += 1
                return .object(pairs)
            }
            throw error("Expected ',' or '}' in object")
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        position += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if position < characters.count && characters[position] == "]" {
            position += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try parseValue())
            skipWhitespace()
            guard position < characters.count else {
                throw error("Unterminated array")
            }
            if characters[position] == "," {
                position += 1
                continue
            }
            if characters[position] == "]" {
                position += 1
                return .array(items)
            }
            throw error("Expected ',' or ']' in array")
        }
    }

    private mutating func parseString() throws -> String {
        position += 1
        var result = ""
        while position < characters.count {
            let character = characters[position]
            if character == "\"" {
                position += 1
                return result
            }
            if character == "\\" {
                position += 1
                guard position < characters.count else { break }
                let escaped = characters[position]
                switch escaped {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "u":
                    let scalarValue = try parseHexScalar()
                    if scalarValue >= 0xD800 && scalarValue <= 0xDBFF {
                        // Surrogate pair: expect \uDC00..DFFF next.
                        if position + 2 < characters.count && characters[position + 1] == "\\" && characters[position + 2] == "u" {
                            position += 2
                            let low = try parseHexScalar()
                            let combined = 0x10000 + ((scalarValue - 0xD800) << 10) + (low - 0xDC00)
                            if let scalar = Unicode.Scalar(combined) {
                                result.unicodeScalars.append(scalar)
                            }
                        }
                    } else if let scalar = Unicode.Scalar(scalarValue) {
                        result.unicodeScalars.append(scalar)
                    }
                default:
                    throw error("Invalid escape '\\\(escaped)'")
                }
                position += 1
                continue
            }
            result.append(character)
            position += 1
        }
        throw error("Unterminated string")
    }

    private mutating func parseHexScalar() throws -> UInt32 {
        guard position + 4 < characters.count else {
            throw error("Invalid unicode escape")
        }
        let hex = String(characters[(position + 1)...(position + 4)])
        guard let value = UInt32(hex, radix: 16) else {
            throw error("Invalid unicode escape")
        }
        position += 4
        return value
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = position
        if characters[position] == "-" { position += 1 }
        while position < characters.count {
            let character = characters[position]
            if character.isNumber || character == "." || character == "e" || character == "E" || character == "+" || character == "-" {
                position += 1
            } else {
                break
            }
        }
        let text = String(characters[start..<position])
        if Double(text) == nil {
            throw error("Invalid number '\(text)'")
        }
        return .number(text)
    }
}

public struct JSONPrinter {
    public var indent: String
    public var sortKeys: Bool

    public init(indent: String = "  ", sortKeys: Bool = false) {
        self.indent = indent
        self.sortKeys = sortKeys
    }

    public func pretty(_ value: JSONValue) -> String {
        var output = ""
        write(value, level: 0, into: &output)
        return output
    }

    public func minified(_ value: JSONValue) -> String {
        var output = ""
        writeMinified(value, into: &output)
        return output
    }

    private func orderedPairs(_ pairs: [(key: String, value: JSONValue)]) -> [(key: String, value: JSONValue)] {
        if !sortKeys { return pairs }
        return pairs.sorted { first, second in first.key < second.key }
    }

    private func write(_ value: JSONValue, level: Int, into output: inout String) {
        let currentIndent = String(repeating: indent, count: level)
        let innerIndent = String(repeating: indent, count: level + 1)
        switch value {
        case .object(let pairs):
            if pairs.isEmpty {
                output += "{}"
                return
            }
            output += "{\n"
            let ordered = orderedPairs(pairs)
            for (index, pair) in ordered.enumerated() {
                output += innerIndent + JSONPrinter.quote(pair.key) + ": "
                write(pair.value, level: level + 1, into: &output)
                if index < ordered.count - 1 { output += "," }
                output += "\n"
            }
            output += currentIndent + "}"
        case .array(let items):
            if items.isEmpty {
                output += "[]"
                return
            }
            output += "[\n"
            for (index, item) in items.enumerated() {
                output += innerIndent
                write(item, level: level + 1, into: &output)
                if index < items.count - 1 { output += "," }
                output += "\n"
            }
            output += currentIndent + "]"
        default:
            writeMinified(value, into: &output)
        }
    }

    private func writeMinified(_ value: JSONValue, into output: inout String) {
        switch value {
        case .object(let pairs):
            output += "{"
            let ordered = orderedPairs(pairs)
            for (index, pair) in ordered.enumerated() {
                output += JSONPrinter.quote(pair.key) + ":"
                writeMinified(pair.value, into: &output)
                if index < ordered.count - 1 { output += "," }
            }
            output += "}"
        case .array(let items):
            output += "["
            for (index, item) in items.enumerated() {
                writeMinified(item, into: &output)
                if index < items.count - 1 { output += "," }
            }
            output += "]"
        case .string(let text):
            output += JSONPrinter.quote(text)
        case .number(let text):
            output += text
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    public static func quote(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }
}

public extension JSONValue {
    /// Replaces string values that themselves contain JSON with the parsed JSON.
    func unescapingNestedJSON() -> JSONValue {
        switch self {
        case .object(let pairs):
            var result: [(key: String, value: JSONValue)] = []
            for pair in pairs {
                result.append((key: pair.key, value: pair.value.unescapingNestedJSON()))
            }
            return .object(result)
        case .array(let items):
            var result: [JSONValue] = []
            for item in items {
                result.append(item.unescapingNestedJSON())
            }
            return .array(result)
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let looksLikeJSON = (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
            if looksLikeJSON, let nested = try? JSONParser.parse(trimmed) {
                return nested.unescapingNestedJSON()
            }
            return self
        default:
            return self
        }
    }

    struct Stats {
        public var keys: Int
        public var depth: Int
    }

    func stats() -> Stats {
        switch self {
        case .object(let pairs):
            var keys = pairs.count
            var deepest = 0
            for pair in pairs {
                let child = pair.value.stats()
                keys += child.keys
                deepest = max(deepest, child.depth)
            }
            return Stats(keys: keys, depth: deepest + 1)
        case .array(let items):
            var keys = 0
            var deepest = 0
            for item in items {
                let child = item.stats()
                keys += child.keys
                deepest = max(deepest, child.depth)
            }
            return Stats(keys: keys, depth: deepest + 1)
        default:
            return Stats(keys: 0, depth: 0)
        }
    }

    /// Converts to Foundation types (numbers as Double/Int) for YAML emitting.
    func toFoundation() -> Any {
        switch self {
        case .object(let pairs):
            var dictionary: [String: Any] = [:]
            for pair in pairs {
                dictionary[pair.key] = pair.value.toFoundation()
            }
            return dictionary
        case .array(let items):
            var list: [Any] = []
            for item in items {
                list.append(item.toFoundation())
            }
            return list
        case .string(let text):
            return text
        case .number(let text):
            if let integer = Int(text) { return integer }
            return Double(text) ?? 0
        case .bool(let flag):
            return flag
        case .null:
            return NSNull()
        }
    }

    static func fromFoundation(_ object: Any?) -> JSONValue {
        guard let object = object else { return .null }
        if object is NSNull { return .null }
        if let dictionary = object as? [String: Any] {
            var pairs: [(key: String, value: JSONValue)] = []
            for key in dictionary.keys.sorted() {
                pairs.append((key: key, value: fromFoundation(dictionary[key])))
            }
            return .object(pairs)
        }
        if let dictionary = object as? [AnyHashable: Any] {
            var pairs: [(key: String, value: JSONValue)] = []
            let keys = dictionary.keys.map { key in "\(key)" }.sorted()
            for key in keys {
                let original = dictionary.first { entry in "\(entry.key)" == key }
                pairs.append((key: key, value: fromFoundation(original?.value)))
            }
            return .object(pairs)
        }
        if let list = object as? [Any] {
            var items: [JSONValue] = []
            for item in list {
                items.append(fromFoundation(item))
            }
            return .array(items)
        }
        if let flag = object as? Bool { return .bool(flag) }
        if let integer = object as? Int { return .number(String(integer)) }
        if let number = object as? Double {
            if number == number.rounded() && abs(number) < 1e15 {
                return .number(String(Int(number)))
            }
            return .number(String(number))
        }
        if let text = object as? String { return .string(text) }
        return .string("\(object)")
    }
}
