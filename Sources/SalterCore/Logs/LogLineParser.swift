import Foundation

public enum LogLevel: String, Sendable {
    case trace, debug, info, warn, error

    public var label: String { rawValue.uppercased() }

    /// Maps level names and pino-style numbers to a level.
    static func from(_ value: Any) -> LogLevel? {
        if let number = value as? NSNumber, !isBool(number) {
            let n = number.intValue
            if n >= 50 { return .error }
            if n >= 40 { return .warn }
            if n >= 30 { return .info }
            if n >= 20 { return .debug }
            return .trace
        }
        guard let text = value as? String else { return nil }
        switch text.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info", "information", "notice": return .info
        case "warn", "warning": return .warn
        case "error", "err", "fatal", "critical", "panic", "severe": return .error
        default: return nil
        }
    }
}

public struct LogField: Equatable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct ParsedLogLine: Equatable, Sendable {
    /// The line's own timestamp (structured lines only).
    public var time: Date?
    public var level: LogLevel?
    /// For plain lines the original text, ANSI codes included.
    public var message: String
    public var fields: [LogField]
    /// True for JSON and logfmt lines.
    public var isStructured: Bool
}

/// Splits a log line into time, level, message and extra fields for display. The raw line is untouched.
public enum LogLineParser {
    static let messageKeys = ["message", "msg"]
    static let levelKeys = ["level", "log_level", "severity", "levelname"]
    static let timeKeys = ["@timestamp", "timestamp", "time", "ts"]

    public static func parse(_ text: String) -> ParsedLogLine {
        let stripped = ANSIParser.strip(text).trimmingCharacters(in: .whitespaces)
        if stripped.hasPrefix("{"), let object = jsonObject(stripped) {
            return structured(object.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 })
        }
        if let pairs = logfmt(stripped), pairs.contains(where: { messageKeys.contains($0.0) }) {
            return structured(pairs)
        }
        return ParsedLogLine(time: nil, level: plainLevel(stripped), message: text, fields: [], isStructured: false)
    }

    // MARK: Structured

    private static func structured(_ pairs: [(String, Any)]) -> ParsedLogLine {
        var remaining = pairs
        func take(_ keys: [String], where accept: (Any) -> Bool = { _ in true }) -> Any? {
            for key in keys {
                if let index = remaining.firstIndex(where: { $0.0 == key && accept($0.1) }) {
                    return remaining.remove(at: index).1
                }
            }
            return nil
        }
        let message = take(messageKeys).map(render) ?? ""
        let level = take(levelKeys, where: { LogLevel.from($0) != nil }).flatMap(LogLevel.from)
        let time = take(timeKeys, where: { date(from: $0) != nil }).flatMap(date(from:))
        let fields = remaining
            .map { LogField(key: $0.0, value: render($0.1)) }
            .filter { message.isEmpty || $0.value != message }
        return ParsedLogLine(time: time, level: level, message: message, fields: fields, isStructured: true)
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func render(_ value: Any) -> String {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            return isBool(number) ? (number.boolValue ? "true" : "false") : number.stringValue
        case is NSNull:
            return ""
        default:
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
            else { return "\(value)" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    private static func date(from value: Any) -> Date? {
        if let number = value as? NSNumber, !isBool(number) {
            let seconds = number.doubleValue
            return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000 : seconds)
        }
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    // MARK: logfmt

    /// `key=value key="quoted value"` tokens, or nil when any token is not a pair.
    static func logfmt(_ text: String) -> [(String, Any)]? {
        var pairs: [(String, Any)] = []
        var chars = Substring(text)
        while true {
            chars = chars.drop(while: { $0 == " " || $0 == "\t" })
            guard !chars.isEmpty else { break }
            guard let equals = chars.firstIndex(of: "=") else { return nil }
            let key = chars[chars.startIndex..<equals]
            guard !key.isEmpty, !key.contains(where: { $0 == " " || $0 == "\"" }) else { return nil }
            chars = chars[chars.index(after: equals)...]
            var value = ""
            if chars.first == "\"" {
                chars = chars.dropFirst()
                var closed = false
                while let c = chars.first {
                    chars = chars.dropFirst()
                    if c == "\\", let next = chars.first {
                        value.append(next)
                        chars = chars.dropFirst()
                    } else if c == "\"" {
                        closed = true
                        break
                    } else {
                        value.append(c)
                    }
                }
                guard closed else { return nil }
            } else {
                let end = chars.firstIndex(where: { $0 == " " || $0 == "\t" }) ?? chars.endIndex
                value = String(chars[chars.startIndex..<end])
                chars = chars[end...]
            }
            pairs.append((String(key), value))
        }
        return pairs.isEmpty ? nil : pairs
    }

    // MARK: Plain text

    private static let levels = "TRACE|DEBUG|INFO|WARNING|WARN|ERROR|FATAL|CRITICAL"
    private static let leading = try! NSRegularExpression(pattern: "^(\(levels)):", options: .caseInsensitive)
    private static let bracketed = try! NSRegularExpression(pattern: "\\[(\(levels))\\]", options: .caseInsensitive)
    private static let assigned = try! NSRegularExpression(pattern: "\\blevel=\"?(\(levels))\\b", options: .caseInsensitive)
    private static let token = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_])(\(levels))(?![A-Za-z0-9_])")

    static func plainLevel(_ text: String) -> LogLevel? {
        let head = String(text.prefix(60))
        for (regex, subject) in [(leading, head), (bracketed, head), (assigned, text), (token, head)] {
            let range = NSRange(subject.startIndex..., in: subject)
            if let match = regex.firstMatch(in: subject, range: range),
               let group = Range(match.range(at: 1), in: subject) {
                return LogLevel.from(String(subject[group]))
            }
        }
        return nil
    }
}

private func isBool(_ number: NSNumber) -> Bool {
    CFGetTypeID(number) == CFBooleanGetTypeID()
}
