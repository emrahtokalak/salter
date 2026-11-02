import Foundation

/// Something that must be fixed before a service can start.
public enum SetupRequirement: Equatable, Sendable {
    case pythonEnvironment(project: String)
    case packageInstall(PackageManager, directory: String)
    case missingExecutable(String)

    public var message: String {
        switch self {
        case .pythonEnvironment(let project):
            return "Python sanal ortamı (.venv) bulunamadı: \(project)"
        case .packageInstall(let manager, _):
            return "node_modules yok; önce \(manager.rawValue) install gerekli."
        case .missingExecutable(let name):
            return "Çalıştırılabilir dosya bulunamadı: \(name)"
        }
    }

    public var fixTitle: String {
        guard let fix else { return "" }
        return "\(fix.command.joined(separator: " ")) çalıştır"
    }

    public var fix: (command: [String], directory: String)? {
        switch self {
        case .pythonEnvironment(let project): return (["uv", "sync"], project)
        case .packageInstall(let manager, let directory): return ([manager.rawValue, "install"], directory)
        case .missingExecutable: return nil
        }
    }
}

public struct LaunchPlan: Equatable, Sendable {
    public var request: SpawnRequest
    public var warnings: [String]

    public init(request: SpawnRequest, warnings: [String]) {
        self.request = request
        self.warnings = warnings
    }
}

public enum LaunchPlanner {
    static let venvSuffixes = ["/.venv/bin/python", "/.venv/bin/python3"]

    public static func setupRequirement(
        for definition: ServiceDefinition,
        searchPath: String?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> SetupRequirement? {
        guard let executable = definition.command.first else { return .missingExecutable("") }
        if executable.contains("/") {
            guard !fileExists(executable) else { return nil }
            if let suffix = venvSuffixes.first(where: { executable.hasSuffix($0) }) {
                return .pythonEnvironment(project: String(executable.dropLast(suffix.count)))
            }
            return .missingExecutable(executable)
        }
        guard ProcessRunner.resolveExecutable(executable, searchPath: searchPath) != nil else {
            return .missingExecutable(executable)
        }
        if let manager = PackageManager(rawValue: executable),
           !fileExists(URL(fileURLWithPath: definition.cwd).appendingPathComponent("node_modules").path) {
            return .packageInstall(manager, directory: definition.cwd)
        }
        return nil
    }

    public static func plan(
        _ definition: ServiceDefinition,
        shell: [String: String],
        readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) throws -> LaunchPlan {
        let command = definition.launchCommand
        guard let executable = command.first else { throw ProcessRunnerError.executableNotFound("") }
        let env = EnvResolver.resolve(shell: shell, definition: definition, readFile: readFile)
        guard let resolved = ProcessRunner.resolveExecutable(executable, searchPath: env.environment["PATH"]) else {
            throw ProcessRunnerError.executableNotFound(executable)
        }
        let request = SpawnRequest(
            executable: resolved,
            arguments: Array(command.dropFirst()),
            environment: env.environment,
            cwd: definition.cwd
        )
        return LaunchPlan(request: request, warnings: env.warnings)
    }

    public static func setupRequest(_ requirement: SetupRequirement, shell: [String: String]) throws -> SpawnRequest? {
        guard let fix = requirement.fix, let name = fix.command.first else { return nil }
        guard let executable = ProcessRunner.resolveExecutable(name, searchPath: shell["PATH"]) else {
            throw ProcessRunnerError.executableNotFound(name)
        }
        var environment = shell
        environment.merge(EnvResolver.constants) { _, new in new }
        return SpawnRequest(
            executable: executable,
            arguments: Array(fix.command.dropFirst()),
            environment: environment,
            cwd: fix.directory
        )
    }
}
