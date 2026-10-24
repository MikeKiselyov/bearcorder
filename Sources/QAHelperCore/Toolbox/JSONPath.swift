import Foundation

/// A practical JSONPath subset: `$`, `.key`, `['key']`, `[0]`, `[-1]`, `[*]`, `.*`, `[1:3]`, `[0,2]`,
/// and recursive `..key` / `..*`. Filters (`[?(...)]`) are not supported.
public enum JSONPath {
    public struct Match {
        public var path: String
        public var value: JSONValue
    }

    public struct ParseError: Error, Equatable {
        public var message: String
    }

    enum Step: Equatable {
        case child(String)
        case index(Int)
        case wildcard
        case slice(Int?, Int?)
        case union([Int])
        /// `..key`, or `..*` when nil.
        case recursive(String?)
    }

    public static func query(_ expression: String, in root: JSONValue) throws -> [Match] {
        let steps = try parse(expression)
        var current = [Match(path: "$", value: root)]
        for step in steps {
            var next: [Match] = []
            for match in current {
                apply(step, to: match, into: &next)
            }
            current = next
        }
        return current
    }

    static func parse(_ expression: String) throws -> [Step] {
        let characters = Array(expression.trimmingCharacters(in: .whitespaces))
        var index = 0
        var steps: [Step] = []
        if index < characters.count && characters[index] == "$" {
            index += 1
        }
        while index < characters.count {
            let character = characters[index]
            if character == "." {
                let recursive = index + 1 < characters.count && characters[index + 1] == "."
                index += recursive ? 2 : 1
                if index < characters.count && characters[index] == "*" {
                    index += 1
                    steps.append(recursive ? .recursive(nil) : .wildcard)
                    continue
                }
                if index < characters.count && characters[index] == "[" && recursive {
                    steps.append(.recursive(nil))
                    continue
                }
                var name = ""
                while index < characters.count && characters[index] != "." && characters[index] != "[" {
                    name.append(characters[index])
                    index += 1
                }
                if name.isEmpty {
                    throw ParseError(message: "Expected a name after the dot")
                }
                steps.append(recursive ? .recursive(name) : .child(name))
            } else if character == "[" {
                guard let close = closingBracket(in: characters, from: index) else {
                    throw ParseError(message: "Missing ]")
                }
                let inside = String(characters[(index + 1)..<close]).trimmingCharacters(in: .whitespaces)
                steps.append(try bracketStep(inside))
                index = close + 1
            } else {
                throw ParseError(message: "Unexpected \"\(character)\"")
            }
        }
        return steps
    }

    private static func closingBracket(in characters: [Character], from start: Int) -> Int? {
        var quote: Character? = nil
        var index = start + 1
        while index < characters.count {
            let character = characters[index]
            if let open = quote {
                if character == open {
                    quote = nil
                }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "]" {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func bracketStep(_ inside: String) throws -> Step {
        if inside == "*" {
            return .wildcard
        }
        if inside.hasPrefix("?") {
            throw ParseError(message: "Filters [?(...)] are not supported")
        }
        if (inside.hasPrefix("'") && inside.hasSuffix("'")) || (inside.hasPrefix("\"") && inside.hasSuffix("\"")) {
            if inside.count < 2 {
                throw ParseError(message: "Empty key")
            }
            return .child(String(inside.dropFirst().dropLast()))
        }
        if inside.contains(":") {
            let parts = inside.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count != 2 {
                throw ParseError(message: "Use [start:end]")
            }
            let start = Int(parts[0].trimmingCharacters(in: .whitespaces))
            let end = Int(parts[1].trimmingCharacters(in: .whitespaces))
            return .slice(start, end)
        }
        if inside.contains(",") {
            var indices: [Int] = []
            for part in inside.split(separator: ",") {
                guard let number = Int(part.trimmingCharacters(in: .whitespaces)) else {
                    throw ParseError(message: "Use numbers in [a,b]")
                }
                indices.append(number)
            }
            return .union(indices)
        }
        guard let number = Int(inside) else {
            throw ParseError(message: "Use [number], ['key'] or [*]")
        }
        return .index(number)
    }

    private static func apply(_ step: Step, to match: Match, into results: inout [Match]) {
        switch step {
        case .child(let name):
            if case .object(let pairs) = match.value {
                for pair in pairs where pair.key == name {
                    results.append(Match(path: childPath(match.path, key: name), value: pair.value))
                }
            }
        case .index(let number):
            if case .array(let items) = match.value {
                var position = number
                if position < 0 {
                    position += items.count
                }
                if position >= 0 && position < items.count {
                    results.append(Match(path: "\(match.path)[\(position)]", value: items[position]))
                }
            }
        case .union(let numbers):
            for number in numbers {
                apply(.index(number), to: match, into: &results)
            }
        case .slice(let start, let end):
            if case .array(let items) = match.value {
                var from = start ?? 0
                var to = end ?? items.count
                if from < 0 { from += items.count }
                if to < 0 { to += items.count }
                from = max(0, min(items.count, from))
                to = max(0, min(items.count, to))
                if from < to {
                    for position in from..<to {
                        results.append(Match(path: "\(match.path)[\(position)]", value: items[position]))
                    }
                }
            }
        case .wildcard:
            appendChildren(of: match, into: &results)
        case .recursive(let name):
            var all: [Match] = [match]
            collectDescendants(of: match, into: &all)
            for candidate in all {
                if let key = name {
                    apply(.child(key), to: candidate, into: &results)
                } else if candidate.path != match.path {
                    results.append(candidate)
                }
            }
        }
    }

    private static func appendChildren(of match: Match, into results: inout [Match]) {
        switch match.value {
        case .object(let pairs):
            for pair in pairs {
                results.append(Match(path: childPath(match.path, key: pair.key), value: pair.value))
            }
        case .array(let items):
            for (position, item) in items.enumerated() {
                results.append(Match(path: "\(match.path)[\(position)]", value: item))
            }
        default:
            break
        }
    }

    private static func collectDescendants(of match: Match, into results: inout [Match]) {
        var children: [Match] = []
        appendChildren(of: match, into: &children)
        for child in children {
            results.append(child)
            collectDescendants(of: child, into: &results)
        }
    }

    /// `$.name` for plain keys, `$['odd key']` otherwise.
    static func childPath(_ parent: String, key: String) -> String {
        var plain = !key.isEmpty
        for character in key where !(character.isLetter || character.isNumber || character == "_") {
            plain = false
        }
        if let first = key.first, first.isNumber {
            plain = false
        }
        if plain {
            return "\(parent).\(key)"
        }
        let escaped = key.replacingOccurrences(of: "'", with: "\\'")
        return "\(parent)['\(escaped)']"
    }
}
