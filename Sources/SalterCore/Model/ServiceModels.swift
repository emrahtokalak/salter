import Foundation

public enum PackageManager: String, Codable, CaseIterable, Sendable {
    case npm, yarn, pnpm
}

/// Where a service definition came from; used to match services across rescans.
public struct ServiceSource: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case launchJson, packageJson, manifest, manual

        /// Unknown kinds (written by a newer Şalter) decode as `.manual` instead of failing the whole config.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .manual
        }
    }

    public var kind: Kind
    /// launch.json configuration name or package.json script name.
    public var name: String?

    public init(kind: Kind, name: String? = nil) {
        self.kind = kind
        self.name = name
    }

    public static func launchJson(_ configName: String) -> ServiceSource {
        ServiceSource(kind: .launchJson, name: configName)
    }

    public static func packageJson(_ script: String) -> ServiceSource {
        ServiceSource(kind: .packageJson, name: script)
    }

    /// Detected from a project manifest; `target` is "<ecosystem>:<relative target>", e.g. "go:cmd/api".
    public static func manifest(_ target: String) -> ServiceSource {
        ServiceSource(kind: .manifest, name: target)
    }

    public static let manual = ServiceSource(kind: .manual)
}

/// Everything needed to run a service.
public struct ServiceDefinition: Codable, Equatable, Sendable {
    public var name: String
    /// Executable and arguments, without reload arguments.
    public var command: [String]
    public var cwd: String
    /// Absolute path of the env file to load; nil when the service has none.
    public var envFile: String?
    public var env: [String: String]
    public var supportsReload: Bool
    public var reloadEnabled: Bool
    /// Appended to `command` when reload is enabled, e.g. ["--reload", "--reload-dir", "src"].
    public var reloadArgs: [String]
    public var portHint: Int?

    public init(
        name: String,
        command: [String],
        cwd: String,
        envFile: String? = nil,
        env: [String: String] = [:],
        supportsReload: Bool = false,
        reloadEnabled: Bool = false,
        reloadArgs: [String] = [],
        portHint: Int? = nil
    ) {
        self.name = name
        self.command = command
        self.cwd = cwd
        self.envFile = envFile
        self.env = env
        self.supportsReload = supportsReload
        self.reloadEnabled = reloadEnabled
        self.reloadArgs = reloadArgs
        self.portHint = portHint
    }

    public var launchCommand: [String] {
        supportsReload && reloadEnabled ? command + reloadArgs : command
    }
}

/// User edits layered over a discovered definition; nil means "use discovered".
public struct ServiceOverrides: Codable, Equatable, Sendable {
    public var name: String?
    public var command: [String]?
    public var cwd: String?
    /// Empty string disables the env file.
    public var envFile: String?
    /// Merged over the discovered env.
    public var env: [String: String]?
    public var reloadEnabled: Bool?
    public var portHint: Int?

    public init() {}

    public var isEmpty: Bool { self == ServiceOverrides() }
}

public struct ServiceConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var source: ServiceSource
    public var discovered: ServiceDefinition
    public var overrides: ServiceOverrides
    public var sourceMissing: Bool

    public init(
        id: String,
        source: ServiceSource,
        discovered: ServiceDefinition,
        overrides: ServiceOverrides = ServiceOverrides(),
        sourceMissing: Bool = false
    ) {
        self.id = id
        self.source = source
        self.discovered = discovered
        self.overrides = overrides
        self.sourceMissing = sourceMissing
    }

    public var effective: ServiceDefinition {
        var d = discovered
        if let v = overrides.name { d.name = v }
        if let v = overrides.command { d.command = v }
        if let v = overrides.cwd { d.cwd = v }
        if let v = overrides.envFile { d.envFile = v.isEmpty ? nil : v }
        if let v = overrides.env { d.env.merge(v) { _, new in new } }
        if let v = overrides.reloadEnabled { d.reloadEnabled = v }
        if let v = overrides.portHint { d.portHint = v }
        return d
    }
}

public struct DiscoveredService: Equatable, Sendable {
    public var id: String
    public var source: ServiceSource
    public var definition: ServiceDefinition

    public init(id: String, source: ServiceSource, definition: ServiceDefinition) {
        self.id = id
        self.source = source
        self.definition = definition
    }
}

public struct SkippedConfig: Equatable, Sendable {
    public var name: String
    public var reason: String

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

public struct TranslationResult: Equatable, Sendable {
    public var services: [DiscoveredService]
    public var skipped: [SkippedConfig]

    public init(services: [DiscoveredService], skipped: [SkippedConfig]) {
        self.services = services
        self.skipped = skipped
    }
}
