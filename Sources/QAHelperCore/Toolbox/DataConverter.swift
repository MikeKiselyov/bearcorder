import Foundation
import Yams

public enum DataFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case yaml = "YAML"
    case xml = "XML"
    case csv = "CSV"

    public var id: String { rawValue }
}

/// Converts between JSON, YAML, XML and CSV through the shared `JSONValue` model.
public enum DataConverter {
    public static func convert(_ input: String, from source: DataFormat, to target: DataFormat) throws -> String {
        let value = try read(input, format: source)
        return try write(value, format: target)
    }

    public static func read(_ input: String, format: DataFormat) throws -> JSONValue {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch format {
        case .json:
            return try JSONParser.parse(text)
        case .yaml:
            let loaded = try Yams.load(yaml: text)
            return JSONValue.fromFoundation(loaded)
        case .xml:
            let document = try XMLDocument(xmlString: text, options: [])
            guard let root = document.rootElement() else {
                throw CodecError.invalid("XML has no root element")
            }
            let rootName = root.name ?? "root"
            return .object([(key: rootName, value: xmlElementToJSON(root))])
        case .csv:
            return try csvToJSON(text)
        }
    }

    public static func write(_ value: JSONValue, format: DataFormat) throws -> String {
        switch format {
        case .json:
            return JSONPrinter().pretty(value)
        case .yaml:
            return try Yams.dump(object: value.toFoundation(), width: -1, allowUnicode: true, sortKeys: false)
        case .xml:
            return jsonToXML(value)
        case .csv:
            return try jsonToCSV(value)
        }
    }

    // MARK: XML

    static func xmlElementToJSON(_ element: XMLElement) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = []
        for attribute in element.attributes ?? [] {
            pairs.append((key: "@" + (attribute.name ?? ""), value: .string(attribute.stringValue ?? "")))
        }
        var childElements: [XMLElement] = []
        for child in element.children ?? [] {
            if let childElement = child as? XMLElement {
                childElements.append(childElement)
            }
        }
        if childElements.isEmpty {
            let text = element.stringValue ?? ""
            if pairs.isEmpty {
                return .string(text)
            }
            if !text.isEmpty {
                pairs.append((key: "#text", value: .string(text)))
            }
            return .object(pairs)
        }
        // Group repeated child names into arrays, keeping first-seen order.
        var order: [String] = []
        var groups: [String: [JSONValue]] = [:]
        for child in childElements {
            let name = child.name ?? "item"
            if groups[name] == nil {
                order.append(name)
                groups[name] = []
            }
            groups[name]?.append(xmlElementToJSON(child))
        }
        for name in order {
            let values = groups[name] ?? []
            if values.count == 1 {
                pairs.append((key: name, value: values[0]))
            } else {
                pairs.append((key: name, value: .array(values)))
            }
        }
        return .object(pairs)
    }

    static func jsonToXML(_ value: JSONValue) -> String {
        var rootName = "root"
        var rootValue = value
        if case .object(let pairs) = value, pairs.count == 1 {
            rootName = pairs[0].key
            rootValue = pairs[0].value
        }
        let root = XMLElement(name: safeXMLName(rootName))
        fill(root, with: rootValue)
        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        return document.xmlString(options: [.nodePrettyPrint])
    }

    static func fill(_ element: XMLElement, with value: JSONValue) {
        switch value {
        case .object(let pairs):
            for pair in pairs {
                if pair.key.hasPrefix("@") {
                    let attribute = XMLNode.attribute(withName: String(pair.key.dropFirst()), stringValue: scalarText(pair.value)) as! XMLNode
                    element.addAttribute(attribute)
                    continue
                }
                if pair.key == "#text" {
                    element.addChild(XMLNode.text(withStringValue: scalarText(pair.value)) as! XMLNode)
                    continue
                }
                if case .array(let items) = pair.value {
                    for item in items {
                        let child = XMLElement(name: safeXMLName(pair.key))
                        fill(child, with: item)
                        element.addChild(child)
                    }
                } else {
                    let child = XMLElement(name: safeXMLName(pair.key))
                    fill(child, with: pair.value)
                    element.addChild(child)
                }
            }
        case .array(let items):
            for item in items {
                let child = XMLElement(name: "item")
                fill(child, with: item)
                element.addChild(child)
            }
        default:
            element.stringValue = scalarText(value)
        }
    }

    static func scalarText(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): return text
        case .number(let text): return text
        case .bool(let flag): return flag ? "true" : "false"
        case .null: return ""
        default: return JSONPrinter().minified(value)
        }
    }

    static func safeXMLName(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isLetter || character.isNumber || character == "_" || character == "-" || character == "." {
                result.append(character)
            } else {
                result.append("_")
            }
        }
        if let first = result.first, first.isNumber || first == "-" || first == "." {
            result = "_" + result
        }
        return result.isEmpty ? "item" : result
    }

    // MARK: CSV

    static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0
        let delimiter: Character = text.contains("\t") && !text.contains(",") ? "\t" : (text.contains(";") && !text.contains(",") ? ";" : ",")
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r" {
                if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    static func csvToJSON(_ text: String) throws -> JSONValue {
        let rows = parseCSVRows(text)
        guard let header = rows.first else {
            throw CodecError.invalid("CSV is empty")
        }
        var items: [JSONValue] = []
        for row in rows.dropFirst() {
            var pairs: [(key: String, value: JSONValue)] = []
            for (index, name) in header.enumerated() {
                var cell = ""
                if index < row.count { cell = row[index] }
                pairs.append((key: name, value: csvCellValue(cell)))
            }
            items.append(.object(pairs))
        }
        return .array(items)
    }

    static func csvCellValue(_ cell: String) -> JSONValue {
        if cell.isEmpty { return .string("") }
        if cell == "true" { return .bool(true) }
        if cell == "false" { return .bool(false) }
        if cell == "null" { return .null }
        // Keep leading zeros (IDs, phone numbers) as strings.
        if Double(cell) != nil && !(cell.hasPrefix("0") && cell.count > 1 && !cell.hasPrefix("0.")) {
            return .number(cell)
        }
        return .string(cell)
    }

    static func jsonToCSV(_ value: JSONValue) throws -> String {
        var rows: [JSONValue] = []
        switch value {
        case .array(let items):
            rows = items
        case .object(let pairs):
            // A single object, or an object wrapping one array.
            if pairs.count == 1, case .array(let items) = pairs[0].value {
                rows = items
            } else {
                rows = [value]
            }
        default:
            throw CodecError.invalid("CSV needs an array of objects")
        }

        var columns: [String] = []
        var flattenedRows: [[String: String]] = []
        for row in rows {
            var flat: [String: String] = [:]
            var rowColumns: [String] = []
            flatten(row, prefix: "", into: &flat, columns: &rowColumns)
            for column in rowColumns where !columns.contains(column) {
                columns.append(column)
            }
            flattenedRows.append(flat)
        }
        var lines: [String] = []
        var headerCells: [String] = []
        for column in columns {
            headerCells.append(csvEscape(column))
        }
        lines.append(headerCells.joined(separator: ","))
        for flat in flattenedRows {
            var cells: [String] = []
            for column in columns {
                cells.append(csvEscape(flat[column] ?? ""))
            }
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func flatten(_ value: JSONValue, prefix: String, into flat: inout [String: String], columns: inout [String]) {
        switch value {
        case .object(let pairs):
            for pair in pairs {
                let key = prefix.isEmpty ? pair.key : prefix + "." + pair.key
                flatten(pair.value, prefix: key, into: &flat, columns: &columns)
            }
        case .array:
            let key = prefix.isEmpty ? "value" : prefix
            flat[key] = JSONPrinter().minified(value)
            columns.append(key)
        default:
            let key = prefix.isEmpty ? "value" : prefix
            flat[key] = scalarText(value)
            columns.append(key)
        }
    }

    static func csvEscape(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return text
    }
}
