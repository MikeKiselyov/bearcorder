import Foundation

/// A raw HTTP request or response pasted from devtools, Charles or logs, taken apart:
/// start line, query, headers, cookies and body.
public struct HTTPMessage {
    public enum Kind: Equatable {
        case request
        case response
        /// Only header lines, no start line (for example "Copy request headers" in Chrome).
        case headers
    }

    public struct Field: Equatable {
        public var name: String
        public var value: String
    }

    public struct Cookie: Equatable {
        public var name: String
        public var value: String
        /// Set-Cookie attributes like "Path=/", "HttpOnly", "Max-Age=3600".
        public var attributes: [String]
    }

    public var kind: Kind
    public var method = ""
    public var target = ""
    public var path = ""
    public var version = ""
    public var statusCode = 0
    public var reason = ""
    public var query: [Field] = []
    public var headers: [Field] = []
    public var cookies: [Cookie] = []
    public var body = ""
    /// Pretty JSON when the body is JSON, otherwise nil.
    public var prettyBody: String?
    /// Fields of an application/x-www-form-urlencoded body.
    public var formFields: [Field] = []

    public static func parse(_ text: String) -> HTTPMessage {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
        var headPart = normalized
        var bodyPart = ""
        if let blank = normalized.range(of: "\n\n") {
            headPart = String(normalized[..<blank.lowerBound])
            bodyPart = String(normalized[blank.upperBound...])
        }
        var lines = pieces(headPart, separator: "\n", maxSplits: Int.max)
        var message = HTTPMessage(kind: .headers)

        if let first = lines.first {
            let words = pieces(first, separator: " ", maxSplits: 2)
            if words.count >= 2 && words[0].uppercased().hasPrefix("HTTP/") {
                message.kind = .response
                message.version = words[0]
                message.statusCode = Int(words[1]) ?? 0
                if words.count > 2 {
                    message.reason = words[2]
                }
                lines.removeFirst()
            } else if words.count >= 2 && isMethod(words[0]) {
                message.kind = .request
                message.method = words[0].uppercased()
                message.target = words[1]
                if words.count > 2 {
                    message.version = words[2]
                }
                lines.removeFirst()
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // HTTP/2 pseudo headers copied from devtools start with ":".
            var searchStart = trimmed.startIndex
            if trimmed.hasPrefix(":") {
                searchStart = trimmed.index(after: searchStart)
            }
            guard let colon = trimmed[searchStart...].firstIndex(of: ":") else { continue }
            let name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            message.headers.append(Field(name: name, value: value))
        }

        // Pseudo headers fill in the request line when there was none.
        if message.kind == .headers {
            if let method = message.header(":method") {
                message.kind = .request
                message.method = method.uppercased()
                message.target = message.header(":path") ?? ""
            } else if let status = message.header(":status") {
                message.kind = .response
                message.statusCode = Int(status) ?? 0
            }
        }

        message.splitTarget()
        message.readCookies()
        message.body = bodyPart
        message.readBody()
        return message
    }

    static func isMethod(_ word: String) -> Bool {
        let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "CONNECT"]
        return methods.contains(word.uppercased())
    }

    /// First header with this name, ignoring case.
    public func header(_ name: String) -> String? {
        for field in headers where field.name.lowercased() == name.lowercased() {
            return field.value
        }
        return nil
    }

    private mutating func splitTarget() {
        path = target
        guard let question = target.firstIndex(of: "?") else { return }
        path = String(target[..<question])
        let queryText = String(target[target.index(after: question)...])
        query = HTTPMessage.formPairs(queryText)
    }

    private mutating func readCookies() {
        for field in headers {
            let name = field.name.lowercased()
            if name == "cookie" {
                for piece in field.value.split(separator: ";") {
                    let pair = piece.trimmingCharacters(in: .whitespaces)
                    if pair.isEmpty { continue }
                    let parts = HTTPMessage.pieces(pair, separator: "=", maxSplits: 1)
                    var value = ""
                    if parts.count > 1 {
                        value = parts[1]
                    }
                    cookies.append(Cookie(name: parts[0], value: value, attributes: []))
                }
            } else if name == "set-cookie" {
                var attributes: [String] = []
                for piece in field.value.split(separator: ";") {
                    attributes.append(piece.trimmingCharacters(in: .whitespaces))
                }
                if attributes.isEmpty { continue }
                let first = attributes.removeFirst()
                let parts = HTTPMessage.pieces(first, separator: "=", maxSplits: 1)
                var value = ""
                if parts.count > 1 {
                    value = parts[1]
                }
                cookies.append(Cookie(name: parts.first ?? "", value: value, attributes: attributes))
            }
        }
    }

    private mutating func readBody() {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let value = try? JSONParser.parse(trimmed) {
                prettyBody = JSONPrinter().pretty(value)
                return
            }
        }
        let contentType = (header("content-type") ?? "").lowercased()
        if contentType.contains("application/x-www-form-urlencoded") {
            formFields = HTTPMessage.formPairs(trimmed)
        }
    }

    /// "a=1&b=two%20words" → [a: 1, b: two words]
    static func formPairs(_ text: String) -> [Field] {
        var fields: [Field] = []
        for piece in text.split(separator: "&") {
            let parts = pieces(String(piece), separator: "=", maxSplits: 1)
            let name = decode(parts[0])
            var value = ""
            if parts.count > 1 {
                value = decode(parts[1])
            }
            fields.append(Field(name: name, value: value))
        }
        return fields
    }

    /// Like split, but keeps empty pieces and returns plain strings.
    static func pieces(_ text: String, separator: Character, maxSplits: Int) -> [String] {
        var result: [String] = []
        for piece in text.split(separator: separator, maxSplits: maxSplits, omittingEmptySubsequences: false) {
            result.append(String(piece))
        }
        return result
    }

    private static func decode(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}
