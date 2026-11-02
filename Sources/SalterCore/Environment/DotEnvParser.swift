import Foundation

/// Minimal .env reader: KEY=VALUE lines, `#` comments, optional quotes and `export ` prefix.
/// No variable expansion and no multi-line values.
public enum DotEnvParser {
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let first = value.first, first == "\"" || first == "'" {
                let rest = value.dropFirst()
                if let close = rest.firstIndex(of: first) {
                    value = String(rest[..<close])
                    if first == "\"" { value = value.replacingOccurrences(of: "\\n", with: "\n") }
                }
            } else if let hash = value.range(of: " #") {
                value = value[..<hash.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            result[key] = value
        }
        return result
    }
}
