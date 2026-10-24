import Foundation

/// The toolbox screens. Kept in Core so detection can point at them.
public enum ToolKind: String, CaseIterable, Identifiable {
    case json = "JSON"
    case xml = "XML"
    case yaml = "YAML"
    case html = "HTML"
    case sql = "SQL"
    case graphql = "GraphQL"
    case jwt = "JWT"
    case base64 = "Base64"
    case url = "URL encode"
    case htmlEntities = "HTML entities"
    case time = "Time & dates"
    case timeZones = "Time zones"
    case dataConvert = "JSON ↔ YAML ↔ XML ↔ CSV"
    case quick = "Numbers, colors, case"
    case generate = "UUID · hash"
    case testData = "Test data"
    case qr = "QR code"
    case regex = "Regex"
    case jsonDiff = "JSON diff"
    case jsonPath = "JSONPath"
    case http = "HTTP message"
    case cron = "Cron"
    case length = "String length"
    case contrast = "Color & contrast"

    public var id: String { rawValue }

    public var formatter: FormatterKind? {
        switch self {
        case .json: return .json
        case .xml: return .xml
        case .yaml: return .yaml
        case .html: return .html
        case .sql: return .sql
        case .graphql: return .graphql
        default: return nil
        }
    }
}

public enum ContentDetector {
    /// Best guess of which tool fits the clipboard text. Nil when nothing fits.
    public static func detect(_ input: String) -> ToolKind? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.count > 2_000_000 { return nil }

        if (text.hasPrefix("{") || text.hasPrefix("[")), (try? JSONParser.parse(text)) != nil {
            return .json
        }
        if looksLikeJWT(text) {
            return .jwt
        }
        if looksLikeHTTP(text) {
            return .http
        }
        if !text.contains("\n") && (try? CronExpression.parse(text)) != nil && text.contains("*") {
            return .cron
        }
        if text.hasPrefix("<") {
            let lower = text.lowercased()
            if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") || lower.contains("<body") || lower.contains("<div") {
                return .html
            }
            return .xml
        }
        if !text.contains("\n") && TimeConverter.parse(text) != nil && isTimeLike(text) {
            return .time
        }
        let upper = text.uppercased()
        let sqlStarts = ["SELECT ", "INSERT ", "UPDATE ", "DELETE ", "WITH ", "CREATE "]
        for start in sqlStarts where upper.hasPrefix(start) {
            return .sql
        }
        if upper.hasPrefix("QUERY ") || upper.hasPrefix("MUTATION ") || upper.hasPrefix("FRAGMENT ") {
            return .graphql
        }
        if !text.contains(" ") && text.contains("%") && URLCodec.decode(text) != text {
            return .url
        }
        if text.contains("&") && text.contains(";") && HTMLEntityCodec.decode(text) != text {
            return .htmlEntities
        }
        if looksLikeBase64(text) {
            return .base64
        }
        if text.contains(":\n") || text.hasPrefix("---") || (text.contains(": ") && text.contains("\n")) {
            return .yaml
        }
        if ColorConverter.parse(text) != nil && (text.hasPrefix("#") || text.lowercased().hasPrefix("rgb") || text.lowercased().hasPrefix("hsl")) {
            return .quick
        }
        return nil
    }

    static func isTimeLike(_ text: String) -> Bool {
        if let value = Double(text) {
            // Plausible timestamps between 2000 and 2100 in s, ms, µs or ns.
            let candidates = [value, value / 1e3, value / 1e6, value / 1e9]
            for seconds in candidates where seconds > 946_684_800 && seconds < 4_102_444_800 {
                return true
            }
            return false
        }
        return true
    }

    /// "GET /path HTTP/1.1", "HTTP/2 200" or devtools ":method:" headers.
    static func looksLikeHTTP(_ text: String) -> Bool {
        let firstLine = String(text.split(separator: "\n", maxSplits: 1).first ?? "")
        if firstLine.uppercased().hasPrefix("HTTP/") {
            return true
        }
        if firstLine.hasPrefix(":method:") || firstLine.hasPrefix(":authority:") {
            return true
        }
        let words = firstLine.split(separator: " ")
        return words.count == 3 && HTTPMessage.isMethod(String(words[0])) && words[2].uppercased().hasPrefix("HTTP/")
    }

    static func looksLikeJWT(_ text: String) -> Bool {
        var token = text
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7))
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count != 3 { return false }
        if !token.hasPrefix("eyJ") { return false }
        return (try? JWTDecoder.decode(token)) != nil
    }

    static func looksLikeBase64(_ text: String) -> Bool {
        if text.count < 8 || text.contains(" ") || text.contains("\n") { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_")
        if text.unicodeScalars.contains(where: { scalar in !allowed.contains(scalar) }) { return false }
        guard let decoded = try? Base64Codec.decode(text) else { return false }
        // Only claim it when the decoded text is mostly printable.
        var printable = 0
        for scalar in decoded.unicodeScalars where scalar.value >= 32 || scalar == "\n" || scalar == "\t" {
            printable += 1
        }
        return Double(printable) / Double(max(1, decoded.unicodeScalars.count)) > 0.9
    }
}
