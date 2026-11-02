import Foundation

/// The subset of a VS Code launch configuration that Şalter understands.
public struct LaunchConfig: Equatable, Sendable {
    public var name: String
    public var type: String?
    public var request: String?
    public var module: String?
    public var program: String?
    public var python: String?
    public var args: [String]
    public var cwd: String?
    public var env: [String: String]
    public var envFile: String?
    public var purpose: [String]
    /// Names of every `${...}` variable referenced anywhere in the configuration.
    public var variables: Set<String>
}

public enum LaunchJsonParser {
    public static func parse(_ data: Data) throws -> [LaunchConfig] {
        let root = try JSONCReader.object(from: data)
        let configurations = root["configurations"] as? [[String: Any]] ?? []
        return configurations.compactMap(config(from:))
    }

    static func config(from dict: [String: Any]) -> LaunchConfig? {
        guard let name = dict["name"] as? String else { return nil }
        return LaunchConfig(
            name: name,
            type: dict["type"] as? String,
            request: dict["request"] as? String,
            module: dict["module"] as? String,
            program: dict["program"] as? String,
            python: dict["python"] as? String,
            args: stringList(dict["args"]),
            cwd: dict["cwd"] as? String,
            env: stringMap(dict["env"]),
            envFile: dict["envFile"] as? String,
            purpose: stringList(dict["purpose"]),
            variables: variables(in: dict)
        )
    }

    static func stringList(_ value: Any?) -> [String] {
        if let list = value as? [Any] { return list.compactMap { $0 as? String } }
        if let text = value as? String { return ShellWords.split(text) }
        return []
    }

    static func stringMap(_ value: Any?) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (key, raw) in dict {
            if let text = raw as? String {
                out[key] = text
            } else if let number = raw as? NSNumber {
                out[key] = number.stringValue
            }
        }
        return out
    }

    static func variables(in value: Any) -> Set<String> {
        switch value {
        case let text as String:
            return variableNames(in: text)
        case let list as [Any]:
            return list.reduce(into: Set<String>()) { $0.formUnion(variables(in: $1)) }
        case let dict as [String: Any]:
            return dict.values.reduce(into: Set<String>()) { $0.formUnion(variables(in: $1)) }
        default:
            return []
        }
    }

    static func variableNames(in text: String) -> Set<String> {
        var names = Set<String>()
        var rest = Substring(text)
        while let start = rest.range(of: "${") {
            guard let end = rest[start.upperBound...].firstIndex(of: "}") else { break }
            names.insert(String(rest[start.upperBound..<end]))
            rest = rest[rest.index(after: end)...]
        }
        return names
    }
}
