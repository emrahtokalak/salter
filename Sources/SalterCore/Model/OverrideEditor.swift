import Foundation

/// Turns a settings-form edit into overrides.
public enum OverrideEditor {
    public struct Fields: Equatable, Sendable {
        /// The alias (`overrides.name`); empty means the computed display name is used.
        public var name: String
        public var command: [String]
        public var cwd: String
        /// Empty string means no env file.
        public var envFile: String
        public var extraEnv: [String: String]
        public var reloadEnabled: Bool
        public var portHint: Int?

        public init(
            name: String, command: [String], cwd: String, envFile: String,
            extraEnv: [String: String], reloadEnabled: Bool, portHint: Int?
        ) {
            self.name = name
            self.command = command
            self.cwd = cwd
            self.envFile = envFile
            self.extraEnv = extraEnv
            self.reloadEnabled = reloadEnabled
            self.portHint = portHint
        }
    }

    public static func fields(of service: ServiceConfig) -> Fields {
        let e = service.effective
        return Fields(
            name: service.overrides.name ?? "", command: e.command, cwd: e.cwd, envFile: e.envFile ?? "",
            extraEnv: service.overrides.env ?? [:], reloadEnabled: e.reloadEnabled, portHint: e.portHint
        )
    }

    /// Writes only the fields the user changed since `baseline` (what the form loaded),
    /// so a rescan that changed the discovered definition meanwhile is not frozen into overrides.
    /// A field edited back to the discovered value clears its override.
    public static func apply(edited: Fields, baseline: Fields, to service: ServiceConfig) -> ServiceOverrides {
        let d = service.discovered
        var o = service.overrides
        if edited.name != baseline.name {
            let alias = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
            o.name = alias.isEmpty ? nil : alias
        }
        if edited.command != baseline.command { o.command = edited.command == d.command ? nil : edited.command }
        if edited.cwd != baseline.cwd { o.cwd = edited.cwd == d.cwd ? nil : edited.cwd }
        if edited.envFile != baseline.envFile {
            o.envFile = edited.envFile == (d.envFile ?? "") ? nil : edited.envFile
        }
        if edited.extraEnv != baseline.extraEnv { o.env = edited.extraEnv.isEmpty ? nil : edited.extraEnv }
        if edited.reloadEnabled != baseline.reloadEnabled {
            o.reloadEnabled = edited.reloadEnabled == d.reloadEnabled ? nil : edited.reloadEnabled
        }
        if edited.portHint != baseline.portHint { o.portHint = edited.portHint == d.portHint ? nil : edited.portHint }
        return o
    }
}
