import Foundation

public struct EnvResolution: Equatable, Sendable {
    public var environment: [String: String]
    public var warnings: [String]
}

/// Layers, lowest to highest: shell → env file → definition env → constants.
public enum EnvResolver {
    public static let constants = ["PYTHONUNBUFFERED": "1", "FORCE_COLOR": "1"]

    public static func resolve(
        shell: [String: String],
        definition: ServiceDefinition,
        readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) -> EnvResolution {
        var env = shell
        var warnings: [String] = []
        if let path = definition.envFile {
            if let text = readFile(path) {
                env.merge(DotEnvParser.parse(text)) { _, new in new }
            } else {
                warnings.append("Env dosyası bulunamadı: \(path)")
            }
        }
        env.merge(definition.env) { _, new in new }
        env.merge(constants) { _, new in new }
        return EnvResolution(environment: env, warnings: warnings)
    }
}
