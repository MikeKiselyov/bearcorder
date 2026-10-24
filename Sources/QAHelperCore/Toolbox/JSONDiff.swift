import Foundation

/// Structural difference of two JSON documents: which paths were added, removed or changed.
/// Key order does not matter; numbers compare by value (1.0 equals 1).
public enum JSONDiff {
    public enum Kind: String {
        case added
        case removed
        case changed
    }

    public struct Change: Equatable {
        public var path: String
        public var kind: Kind
        /// Compact JSON of the value before / after; nil when there is none.
        public var old: String?
        public var new: String?
    }

    public static let valueLimit = 200

    public static func compare(_ left: JSONValue, _ right: JSONValue) -> [Change] {
        var changes: [Change] = []
        walk(left, right, path: "$", into: &changes)
        return changes
    }

    private static func walk(_ left: JSONValue, _ right: JSONValue, path: String, into changes: inout [Change]) {
        switch (left, right) {
        case (.object(let leftPairs), .object(let rightPairs)):
            for pair in leftPairs {
                let childPath = JSONPath.childPath(path, key: pair.key)
                if let other = value(for: pair.key, in: rightPairs) {
                    walk(pair.value, other, path: childPath, into: &changes)
                } else {
                    changes.append(Change(path: childPath, kind: .removed, old: compact(pair.value), new: nil))
                }
            }
            for pair in rightPairs where value(for: pair.key, in: leftPairs) == nil {
                changes.append(Change(path: JSONPath.childPath(path, key: pair.key), kind: .added, old: nil, new: compact(pair.value)))
            }
        case (.array(let leftItems), .array(let rightItems)):
            let shared = min(leftItems.count, rightItems.count)
            for index in 0..<shared {
                walk(leftItems[index], rightItems[index], path: "\(path)[\(index)]", into: &changes)
            }
            if leftItems.count > shared {
                for index in shared..<leftItems.count {
                    changes.append(Change(path: "\(path)[\(index)]", kind: .removed, old: compact(leftItems[index]), new: nil))
                }
            }
            if rightItems.count > shared {
                for index in shared..<rightItems.count {
                    changes.append(Change(path: "\(path)[\(index)]", kind: .added, old: nil, new: compact(rightItems[index])))
                }
            }
        case (.number(let leftText), .number(let rightText)):
            if leftText != rightText && Double(leftText) != Double(rightText) {
                changes.append(Change(path: path, kind: .changed, old: leftText, new: rightText))
            }
        default:
            if left != right {
                changes.append(Change(path: path, kind: .changed, old: compact(left), new: compact(right)))
            }
        }
    }

    private static func value(for key: String, in pairs: [(key: String, value: JSONValue)]) -> JSONValue? {
        for pair in pairs where pair.key == key {
            return pair.value
        }
        return nil
    }

    static func compact(_ value: JSONValue) -> String {
        let text = JSONPrinter().minified(value)
        if text.count > valueLimit {
            return String(text.prefix(valueLimit)) + "…"
        }
        return text
    }
}
