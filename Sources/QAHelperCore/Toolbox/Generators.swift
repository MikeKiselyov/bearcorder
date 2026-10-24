import CryptoKit
import Foundation

public enum UUIDGenerator {
    public static func v4() -> String {
        return UUID().uuidString.lowercased()
    }

    /// UUID v7: 48-bit Unix milliseconds, then random bits with version and variant set.
    public static func v7(date: Date = Date()) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let milliseconds = UInt64(date.timeIntervalSince1970 * 1000)
        for index in 0..<6 {
            let shift = UInt64(8 * (5 - index))
            bytes[index] = UInt8((milliseconds >> shift) & 0xFF)
        }
        for index in 6..<16 {
            bytes[index] = UInt8.random(in: 0...255)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        var hex = ""
        for byte in bytes {
            hex += String(format: "%02x", byte)
        }
        let characters = Array(hex)
        let first = String(characters[0..<8])
        let second = String(characters[8..<12])
        let third = String(characters[12..<16])
        let fourth = String(characters[16..<20])
        let fifth = String(characters[20..<32])
        return "\(first)-\(second)-\(third)-\(fourth)-\(fifth)"
    }
}

public struct HashResult: Identifiable {
    public var id: String { name }
    public var name: String
    public var value: String
}

public enum HashGenerator {
    public static func hashes(of text: String) -> [HashResult] {
        let data = Data(text.utf8)
        return [
            HashResult(name: "MD5", value: hex(Insecure.MD5.hash(data: data))),
            HashResult(name: "SHA-1", value: hex(Insecure.SHA1.hash(data: data))),
            HashResult(name: "SHA-256", value: hex(SHA256.hash(data: data))),
            HashResult(name: "SHA-512", value: hex(SHA512.hash(data: data))),
        ]
    }

    static func hex<Digest: Sequence>(_ digest: Digest) -> String where Digest.Element == UInt8 {
        var result = ""
        for byte in digest {
            result += String(format: "%02x", byte)
        }
        return result
    }
}
