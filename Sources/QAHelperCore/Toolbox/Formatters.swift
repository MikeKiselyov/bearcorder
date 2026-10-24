import Foundation
import Yams

public enum FormatterKind: String, CaseIterable, Identifiable {
    case json = "JSON"
    case xml = "XML"
    case yaml = "YAML"
    case html = "HTML"
    case sql = "SQL"
    case graphql = "GraphQL"

    public var id: String { rawValue }
}

public enum FormatMode: String, CaseIterable, Identifiable {
    case format = "Format"
    case minify = "Minify"

    public var id: String { rawValue }
}

public struct FormatOptions {
    public var indentWidth: Int = 2
    public var useTabs: Bool = false
    public var sortKeys: Bool = false
    public var unescapeStrings: Bool = false
    public var mode: FormatMode = .format

    public init() {}

    public var indentString: String {
        if useTabs { return "\t" }
        return String(repeating: " ", count: indentWidth)
    }
}

public struct FormatResult {
    public var output: String
    public var isValid: Bool
    public var message: String

    public init(output: String, isValid: Bool, message: String) {
        self.output = output
        self.isValid = isValid
        self.message = message
    }
}

public enum Formatters {
    public static func format(_ input: String, kind: FormatterKind, options: FormatOptions) -> FormatResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FormatResult(output: "", isValid: true, message: "")
        }
        switch kind {
        case .json:
            return formatJSON(trimmed, options: options)
        case .xml:
            return formatXML(trimmed, options: options, html: false)
        case .html:
            return formatXML(trimmed, options: options, html: true)
        case .yaml:
            return formatYAML(trimmed, options: options)
        case .sql:
            return formatSQL(trimmed, options: options)
        case .graphql:
            return formatGraphQL(trimmed, options: options)
        }
    }

    // MARK: JSON

    public static func formatJSON(_ input: String, options: FormatOptions) -> FormatResult {
        do {
            var value = try JSONParser.parse(input)
            if options.unescapeStrings {
                value = value.unescapingNestedJSON()
            }
            let printer = JSONPrinter(indent: options.indentString, sortKeys: options.sortKeys)
            let output: String
            if options.mode == .minify {
                output = printer.minified(value)
            } else {
                output = printer.pretty(value)
            }
            let stats = value.stats()
            let message = "Valid JSON · \(stats.keys) keys · depth \(stats.depth)"
            return FormatResult(output: output, isValid: true, message: message)
        } catch let parseError as JSONParseError {
            return FormatResult(output: "", isValid: false, message: parseError.description)
        } catch {
            return FormatResult(output: "", isValid: false, message: error.localizedDescription)
        }
    }

    // MARK: XML / HTML

    public static func formatXML(_ input: String, options: FormatOptions, html: Bool) -> FormatResult {
        do {
            var parseOptions: XMLNode.Options = []
            if html {
                parseOptions = [.documentTidyHTML]
            }
            let document = try XMLDocument(xmlString: input, options: parseOptions)
            let output: String
            if options.mode == .minify {
                output = minifyXML(document.xmlString(options: []))
            } else {
                let pretty = document.xmlString(options: [.nodePrettyPrint])
                output = reindent(pretty, width: options.indentWidth, useTabs: options.useTabs)
            }
            let label = html ? "Parsed HTML" : "Valid XML"
            return FormatResult(output: output, isValid: true, message: label)
        } catch {
            let label = html ? "Invalid HTML" : "Invalid XML"
            return FormatResult(output: "", isValid: false, message: "\(label): \(error.localizedDescription)")
        }
    }

    private static func minifyXML(_ text: String) -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }
        return lines.joined()
    }

    /// XMLDocument pretty-prints with 4 spaces; convert to the requested indent.
    private static func reindent(_ text: String, width: Int, useTabs: Bool) -> String {
        var result: [String] = []
        for line in text.components(separatedBy: "\n") {
            var leadingSpaces = 0
            for character in line {
                if character == " " {
                    leadingSpaces += 1
                } else {
                    break
                }
            }
            let level = leadingSpaces / 4
            let remainder = leadingSpaces % 4
            let body = String(line.dropFirst(leadingSpaces))
            var indent = ""
            if useTabs {
                indent = String(repeating: "\t", count: level)
            } else {
                indent = String(repeating: " ", count: level * width)
            }
            indent += String(repeating: " ", count: remainder)
            result.append(indent + body)
        }
        return result.joined(separator: "\n")
    }

    // MARK: YAML

    public static func formatYAML(_ input: String, options: FormatOptions) -> FormatResult {
        do {
            guard let loaded = try Yams.load(yaml: input) else {
                return FormatResult(output: "", isValid: true, message: "Empty YAML")
            }
            if options.mode == .minify {
                // Flow style is the closest thing to "minified" YAML.
                let value = JSONValue.fromFoundation(loaded)
                return FormatResult(output: JSONPrinter().minified(value), isValid: true, message: "Valid YAML · shown in flow style")
            }
            let output = try Yams.dump(object: loaded, indent: options.indentWidth, width: -1, allowUnicode: true, sortKeys: options.sortKeys)
            return FormatResult(output: output, isValid: true, message: "Valid YAML")
        } catch {
            return FormatResult(output: "", isValid: false, message: "Invalid YAML: \(error)")
        }
    }

    // MARK: SQL

    private static let sqlNewlineKeywords: [String] = [
        "SELECT", "FROM", "WHERE", "GROUP BY", "ORDER BY", "HAVING", "LIMIT", "OFFSET",
        "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM", "UNION ALL", "UNION",
        "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "FULL JOIN", "CROSS JOIN", "JOIN",
        "RETURNING", "WITH",
    ]

    private static let sqlIndentedKeywords: [String] = ["AND", "OR", "ON"]

    private static let sqlAllKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "INSERT",
        "INTO", "VALUES", "UPDATE", "SET", "DELETE", "UNION", "ALL", "LEFT", "RIGHT", "INNER",
        "FULL", "CROSS", "JOIN", "ON", "AND", "OR", "NOT", "NULL", "IS", "IN", "AS", "DISTINCT",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "CASE", "WHEN", "THEN", "ELSE", "END", "LIKE",
        "BETWEEN", "EXISTS", "ASC", "DESC", "RETURNING", "WITH", "TRUE", "FALSE",
    ]

    /// Splits SQL into tokens: quoted strings, words, and single symbols.
    static func sqlTokens(_ input: String) -> [String] {
        var tokens: [String] = []
        let characters = Array(input)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character == "'" || character == "\"" || character == "`" {
                let quote = character
                var token = String(quote)
                index += 1
                while index < characters.count {
                    token.append(characters[index])
                    if characters[index] == quote {
                        index += 1
                        break
                    }
                    index += 1
                }
                tokens.append(token)
                continue
            }
            if character.isLetter || character.isNumber || character == "_" || character == "." || character == "$" || character == ":" || character == "@" {
                var token = ""
                while index < characters.count {
                    let current = characters[index]
                    if current.isLetter || current.isNumber || current == "_" || current == "." || current == "$" || current == ":" || current == "@" {
                        token.append(current)
                        index += 1
                    } else {
                        break
                    }
                }
                tokens.append(token)
                continue
            }
            // Two-character operators.
            if index + 1 < characters.count {
                let pair = String([character, characters[index + 1]])
                if pair == "<=" || pair == ">=" || pair == "<>" || pair == "!=" || pair == "::" || pair == "||" {
                    tokens.append(pair)
                    index += 2
                    continue
                }
            }
            tokens.append(String(character))
            index += 1
        }
        return tokens
    }

    public static func formatSQL(_ input: String, options: FormatOptions) -> FormatResult {
        let tokens = sqlTokens(input)
        if options.mode == .minify {
            return FormatResult(output: joinSQLTokens(tokens), isValid: true, message: "SQL minified")
        }

        // Each line is an indent level plus its tokens.
        var lines: [(level: Int, tokens: [String])] = []
        var depth = 0
        var currentClause = ""
        var index = 0

        func startLine(level: Int) {
            lines.append((level: level, tokens: []))
        }

        func append(_ token: String) {
            if lines.isEmpty { startLine(level: 0) }
            lines[lines.count - 1].tokens.append(token)
        }

        while index < tokens.count {
            let token = tokens[index]
            let upper = token.uppercased()

            var matchedKeyword: String? = nil
            for keyword in sqlNewlineKeywords {
                let parts = keyword.split(separator: " ").map(String.init)
                if index + parts.count > tokens.count { continue }
                var matches = true
                for offset in 0..<parts.count {
                    if tokens[index + offset].uppercased() != parts[offset] {
                        matches = false
                        break
                    }
                }
                if matches {
                    matchedKeyword = keyword
                    break
                }
            }

            if let keyword = matchedKeyword {
                startLine(level: depth)
                append(keyword)
                currentClause = keyword
                index += keyword.split(separator: " ").count
                if keyword == "SELECT" {
                    startLine(level: depth + 1)
                }
                continue
            }

            if sqlIndentedKeywords.contains(upper) {
                startLine(level: depth + 1)
                append(upper)
                index += 1
                continue
            }

            if token == "(" {
                depth += 1
            } else if token == ")" {
                depth = max(0, depth - 1)
            }

            if token == "," && currentClause == "SELECT" && depth == 0 {
                append(",")
                startLine(level: 1)
                index += 1
                continue
            }

            if sqlAllKeywords.contains(upper) {
                append(upper)
            } else {
                append(token)
            }
            index += 1
        }

        var output: [String] = []
        for line in lines {
            if line.tokens.isEmpty { continue }
            let indent = String(repeating: options.indentString, count: line.level)
            output.append(indent + joinSQLTokens(line.tokens))
        }
        return FormatResult(output: output.joined(separator: "\n"), isValid: true, message: "SQL formatted")
    }

    private static func joinSQLTokens(_ tokens: [String]) -> String {
        var output = ""
        for token in tokens {
            if token == "," || token == ")" || token == ";" {
                output += token
            } else if output.hasSuffix("(") || output.isEmpty {
                output += token
            } else if token == "(" {
                output += token
            } else {
                output += " " + token
            }
        }
        return output
    }

    // MARK: GraphQL

    public static func formatGraphQL(_ input: String, options: FormatOptions) -> FormatResult {
        let characters = Array(input)
        var output = ""
        var depth = 0
        var parenDepth = 0
        var inString = false
        var pendingSpace = false
        let indent = options.indentString
        let minify = options.mode == .minify

        func newline() {
            while output.hasSuffix(" ") { output.removeLast() }
            if minify {
                output += " "
            } else {
                output += "\n" + String(repeating: indent, count: depth)
            }
        }

        for character in characters {
            if inString {
                output.append(character)
                if character == "\"" { inString = false }
                continue
            }
            if character == "\"" {
                if pendingSpace { output += " " }
                pendingSpace = false
                inString = true
                output.append(character)
                continue
            }
            if character == "{" {
                while output.hasSuffix(" ") { output.removeLast() }
                if !output.isEmpty { output += " " }
                output += "{"
                depth += 1
                newline()
                pendingSpace = false
                continue
            }
            if character == "}" {
                depth = max(0, depth - 1)
                newline()
                output += "}"
                pendingSpace = false
                if depth == 0 && !minify {
                    output += "\n"
                }
                continue
            }
            if character == "(" { parenDepth += 1 }
            if character == ")" { parenDepth = max(0, parenDepth - 1) }
            if character == "," {
                if parenDepth > 0 {
                    output += ", "
                } else {
                    newline()
                }
                pendingSpace = false
                continue
            }
            if character.isWhitespace {
                if character.isNewline && parenDepth == 0 && depth > 0 {
                    let trimmedOutput = output.trimmingCharacters(in: .whitespaces)
                    if !trimmedOutput.hasSuffix("{") && !output.hasSuffix("\n" + String(repeating: indent, count: depth)) {
                        newline()
                    }
                    pendingSpace = false
                } else {
                    pendingSpace = true
                }
                continue
            }
            if pendingSpace {
                let last = output.last
                if last != nil && last != " " && last != "\n" && last != "(" && last != "\t" {
                    output += " "
                }
                pendingSpace = false
            }
            output.append(character)
        }
        var cleaned: [String] = []
        for line in output.components(separatedBy: "\n") {
            let trimmedRight = line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            if !trimmedRight.trimmingCharacters(in: .whitespaces).isEmpty {
                cleaned.append(trimmedRight)
            }
        }
        let joined = minify ? cleaned.joined(separator: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) : cleaned.joined(separator: "\n")
        let balanced = depth == 0 && parenDepth == 0
        return FormatResult(output: joined, isValid: balanced, message: balanced ? "GraphQL formatted" : "Unbalanced brackets")
    }
}
