import Foundation

public enum TOMLValue: Equatable, Sendable {
    case string(String)
    case strings([String])
    case bool(Bool)
    /// Anything this reader does not model (numbers, inline tables, mixed arrays, ...).
    case other
}

/// The subset of TOML needed to read Cargo manifests: tables, arrays of tables, strings,
/// booleans and string arrays. Never throws; unrecognised lines are ignored.
public struct MiniTOML: Equatable, Sendable {
    /// Keyed by table name; top-level keys live under "".
    public var tables: [String: [String: TOMLValue]] = [:]
    public var arrayTables: [String: [[String: TOMLValue]]] = [:]

    public static func parse(_ text: String) -> MiniTOML {
        var doc = MiniTOML()
        var table = ""
        var inArrayTable = false
        var pending: (key: String, value: String)?

        func store(_ key: String, _ raw: String) {
            let value = parseValue(raw)
            if inArrayTable, var list = doc.arrayTables[table], !list.isEmpty {
                list[list.count - 1][key] = value
                doc.arrayTables[table] = list
            } else {
                doc.tables[table, default: [:]][key] = value
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if let open = pending {
                let joined = open.value + " " + line
                if bracketsBalanced(joined) {
                    store(open.key, joined)
                    pending = nil
                } else {
                    pending = (open.key, joined)
                }
                continue
            }
            if line.isEmpty { continue }
            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                table = line.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
                inArrayTable = true
                doc.arrayTables[table, default: []].append([:])
            } else if line.hasPrefix("[") && line.hasSuffix("]") {
                table = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
                inArrayTable = false
                doc.tables[table, default: [:]] = doc.tables[table] ?? [:]
            } else if let eq = line.firstIndex(of: "=") {
                let key = unquote(line[..<eq].trimmingCharacters(in: .whitespaces))
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if bracketsBalanced(value) {
                    store(key, value)
                } else {
                    pending = (key, value)
                }
            }
        }
        return doc
    }

    static func parseValue(_ raw: String) -> TOMLValue {
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        if let string = quoted(raw) { return .string(string) }
        if raw.hasPrefix("["), raw.hasSuffix("]") {
            let items = splitTopLevel(String(raw.dropFirst().dropLast()))
            let strings = items.compactMap(quoted)
            return strings.count == items.count ? .strings(strings) : .other
        }
        return .other
    }

    /// The contents of a single basic ('...' or "...") string literal, or nil.
    static func quoted(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard s.count >= 2, let q = s.first, q == "\"" || q == "'", s.last == q else { return nil }
        let body = String(s.dropFirst().dropLast())
        if q == "'" { return body }
        return body.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    static func unquote(_ key: String) -> String {
        quoted(key) ?? key
    }

    /// Comma-separated items of an array body, ignoring commas inside strings; empty items dropped.
    static func splitTopLevel(_ body: String) -> [String] {
        var items: [String] = []
        var current = ""
        scan(body) { char, inString in
            if char == ",", !inString {
                items.append(current)
                current = ""
            } else {
                current.append(char)
            }
            return true
        }
        items.append(current)
        return items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func stripComment(_ line: String) -> String {
        var out = ""
        scan(line) { char, inString in
            if char == "#", !inString { return false }
            out.append(char)
            return true
        }
        return out
    }

    static func bracketsBalanced(_ text: String) -> Bool {
        var depth = 0
        scan(text) { char, inString in
            if !inString {
                if char == "[" { depth += 1 }
                if char == "]" { depth -= 1 }
            }
            return true
        }
        return depth <= 0
    }

    /// Walks `text`, reporting for each character whether it is inside a string literal; stops when `body` returns false.
    static func scan(_ text: String, _ body: (Character, Bool) -> Bool) {
        var quote: Character?
        var escaped = false
        for char in text {
            let inString = quote != nil
            if let q = quote {
                if escaped {
                    escaped = false
                } else if char == "\\" && q == "\"" {
                    escaped = true
                } else if char == q {
                    quote = nil
                }
            } else if char == "\"" || char == "'" {
                quote = char
            }
            if !body(char, inString || quote != nil) { return }
        }
    }
}
