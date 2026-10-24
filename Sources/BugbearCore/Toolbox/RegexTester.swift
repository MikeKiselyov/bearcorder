import Foundation

/// Runs an ICU regular expression (NSRegularExpression, the same flavour as Swift and Objective-C) over text.
public enum RegexTester {
    public struct Options {
        public var caseInsensitive = false
        /// ^ and $ match at line breaks.
        public var multiline = true
        /// . matches line breaks too.
        public var dotMatchesLineBreaks = false

        public init() {}
    }

    public struct Group: Equatable {
        public var name: String
        /// Nil when the group did not take part in the match.
        public var value: String?
    }

    public struct Match: Equatable {
        /// UTF-16 range in the text, for highlighting.
        public var range: NSRange
        public var value: String
        public var groups: [Group]
    }

    public struct Result {
        public var matches: [Match] = []
        public var error: String?
        /// True when matching stopped at `limit`.
        public var truncated = false
        public var replaced: String?
    }

    public static let limit = 1000

    public static func run(pattern: String, text: String, options: Options, replacement: String? = nil) -> Result {
        var result = Result()
        if pattern.isEmpty { return result }
        var flags: NSRegularExpression.Options = []
        if options.caseInsensitive { flags.insert(.caseInsensitive) }
        if options.multiline { flags.insert(.anchorsMatchLines) }
        if options.dotMatchesLineBreaks { flags.insert(.dotMatchesLineSeparators) }
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(pattern: pattern, options: flags)
        } catch {
            result.error = "Invalid pattern"
            return result
        }
        let names = groupNames(in: pattern)
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
        for found in expression.matches(in: text, range: whole) {
            if result.matches.count >= limit {
                result.truncated = true
                break
            }
            var groups: [Group] = []
            if found.numberOfRanges > 1 {
                for index in 1..<found.numberOfRanges {
                    let range = found.range(at: index)
                    var value: String? = nil
                    if range.location != NSNotFound {
                        value = source.substring(with: range)
                    }
                    var name = "\(index)"
                    if index - 1 < names.count, let groupName = names[index - 1] {
                        name = groupName
                    }
                    groups.append(Group(name: name, value: value))
                }
            }
            result.matches.append(Match(range: found.range, value: source.substring(with: found.range), groups: groups))
        }
        if let template = replacement {
            result.replaced = expression.stringByReplacingMatches(in: text, range: whole, withTemplate: template)
        }
        return result
    }

    /// Names of capture groups in order; nil for unnamed groups. Skips escapes, classes and (?:…) style groups.
    static func groupNames(in pattern: String) -> [String?] {
        var names: [String?] = []
        let characters = Array(pattern)
        var index = 0
        var inClass = false
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if inClass {
                if character == "]" {
                    inClass = false
                }
                index += 1
                continue
            }
            if character == "[" {
                inClass = true
            } else if character == "(" {
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                if next != "?" {
                    names.append(nil)
                } else if index + 2 < characters.count && characters[index + 2] == "<" && index + 3 < characters.count && characters[index + 3] != "=" && characters[index + 3] != "!" {
                    var name = ""
                    var cursor = index + 3
                    while cursor < characters.count && characters[cursor] != ">" {
                        name.append(characters[cursor])
                        cursor += 1
                    }
                    names.append(name)
                }
            }
            index += 1
        }
        return names
    }
}
