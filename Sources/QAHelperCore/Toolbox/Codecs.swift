import Foundation

public enum CodecError: Error, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

// MARK: - Base64

public enum Base64Codec {
    public static func encode(_ text: String, urlSafe: Bool) -> String {
        let encoded = Data(text.utf8).base64EncodedString()
        if !urlSafe { return encoded }
        return toURLSafe(encoded)
    }

    public static func decode(_ text: String) throws -> String {
        guard let data = decodeData(text) else {
            throw CodecError.invalid("Not valid Base64")
        }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw CodecError.invalid("Decoded bytes are not UTF-8 text (\(data.count) bytes)")
        }
        return decoded
    }

    /// Accepts standard and URL-safe alphabets, with or without padding.
    public static func decodeData(_ text: String) -> Data? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\n", with: "")
        cleaned = cleaned.replacingOccurrences(of: "-", with: "+")
        cleaned = cleaned.replacingOccurrences(of: "_", with: "/")
        let remainder = cleaned.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 {
            cleaned += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: cleaned)
    }

    static func toURLSafe(_ base64: String) -> String {
        var result = base64.replacingOccurrences(of: "+", with: "-")
        result = result.replacingOccurrences(of: "/", with: "_")
        result = result.replacingOccurrences(of: "=", with: "")
        return result
    }
}

// MARK: - URL encoding

public enum URLCodec {
    public static func encode(_ text: String, componentOnly: Bool) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        if !componentOnly {
            allowed.insert(charactersIn: ":/?#[]@!$&'()*+,;=%")
        }
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    public static func decode(_ text: String) -> String {
        let withSpaces = text.replacingOccurrences(of: "+", with: " ")
        return withSpaces.removingPercentEncoding ?? withSpaces
    }

    /// Splits a URL or query string into decoded name/value pairs.
    public static func queryItems(_ text: String) -> [(name: String, value: String)] {
        var query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let questionMark = query.firstIndex(of: "?") {
            query = String(query[query.index(after: questionMark)...])
        }
        if let hash = query.firstIndex(of: "#") {
            query = String(query[..<hash])
        }
        var items: [(name: String, value: String)] = []
        for part in query.split(separator: "&") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            let name = decode(pieces[0])
            var value = ""
            if pieces.count > 1 {
                value = decode(pieces[1])
            }
            items.append((name: name, value: value))
        }
        return items
    }
}

// MARK: - HTML entities

public enum HTMLEntityCodec {
    static let named: [(entity: String, character: String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
        ("&apos;", "'"), ("&nbsp;", "\u{00A0}"), ("&copy;", "©"), ("&reg;", "®"),
        ("&trade;", "™"), ("&euro;", "€"), ("&pound;", "£"), ("&yen;", "¥"), ("&cent;", "¢"),
        ("&sect;", "§"), ("&deg;", "°"), ("&plusmn;", "±"), ("&times;", "×"), ("&divide;", "÷"),
        ("&middot;", "·"), ("&hellip;", "…"), ("&ndash;", "–"), ("&mdash;", "—"),
        ("&lsquo;", "‘"), ("&rsquo;", "’"), ("&ldquo;", "“"), ("&rdquo;", "”"),
        ("&laquo;", "«"), ("&raquo;", "»"), ("&bull;", "•"), ("&larr;", "←"), ("&rarr;", "→"),
    ]

    public static func encode(_ text: String, nonASCII: Bool) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default:
                if nonASCII && scalar.value > 127 {
                    result += "&#\(scalar.value);"
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    public static func decode(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "&", let semicolon = text[index...].firstIndex(of: ";"), text.distance(from: index, to: semicolon) <= 10 {
                let entity = String(text[index...semicolon])
                if let decoded = decodeEntity(entity) {
                    result += decoded
                    index = text.index(after: semicolon)
                    continue
                }
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result
    }

    private static func decodeEntity(_ entity: String) -> String? {
        for pair in named {
            if pair.entity == entity { return pair.character }
        }
        if entity.hasPrefix("&#x") || entity.hasPrefix("&#X") {
            let hex = entity.dropFirst(3).dropLast()
            if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
                return String(Character(scalar))
            }
        } else if entity.hasPrefix("&#") {
            let decimal = entity.dropFirst(2).dropLast()
            if let value = UInt32(decimal), let scalar = Unicode.Scalar(value) {
                return String(Character(scalar))
            }
        }
        return nil
    }
}

// MARK: - JWT

public struct DecodedJWT {
    public var header: String
    public var payload: String
    public var signature: String
    public var algorithm: String
    /// Human readable notes for registered time claims (exp, iat, nbf).
    public var claims: [(name: String, value: String)]
    public var isExpired: Bool?
}

public enum JWTDecoder {
    public static func decode(_ token: String, now: Date = Date(), timeZone: TimeZone = .current) throws -> DecodedJWT {
        var cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("bearer ") {
            cleaned = String(cleaned.dropFirst(7))
        }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count < 2 {
            throw CodecError.invalid("A JWT has 3 parts separated by dots")
        }
        let header = try decodePart(parts[0], name: "header")
        let payload = try decodePart(parts[1], name: "payload")
        var signature = ""
        if parts.count > 2 {
            signature = parts[2]
        }

        let printer = JSONPrinter()
        var headerText = header
        var payloadText = payload
        var algorithm = "unknown"
        if let headerValue = try? JSONParser.parse(header) {
            headerText = printer.pretty(headerValue)
            if case .object(let pairs) = headerValue {
                for pair in pairs where pair.key == "alg" {
                    if case .string(let alg) = pair.value { algorithm = alg }
                }
            }
        }

        var claims: [(name: String, value: String)] = []
        var isExpired: Bool? = nil
        if let payloadValue = try? JSONParser.parse(payload) {
            payloadText = printer.pretty(payloadValue)
            if case .object(let pairs) = payloadValue {
                for pair in pairs {
                    let timeClaims = ["exp", "iat", "nbf", "auth_time"]
                    if !timeClaims.contains(pair.key) { continue }
                    guard case .number(let text) = pair.value, let seconds = Double(text) else { continue }
                    let date = Date(timeIntervalSince1970: seconds)
                    let formatted = TimeConverter.isoString(date, timeZone: timeZone)
                    let relative = TimeConverter.relativeString(from: now, to: date)
                    claims.append((name: pair.key, value: "\(formatted) · \(relative)"))
                    if pair.key == "exp" {
                        isExpired = date < now
                    }
                }
            }
        }
        return DecodedJWT(header: headerText, payload: payloadText, signature: signature, algorithm: algorithm, claims: claims, isExpired: isExpired)
    }

    private static func decodePart(_ part: String, name: String) throws -> String {
        guard let data = Base64Codec.decodeData(part), let text = String(data: data, encoding: .utf8) else {
            throw CodecError.invalid("JWT \(name) is not valid base64url JSON")
        }
        return text
    }
}
