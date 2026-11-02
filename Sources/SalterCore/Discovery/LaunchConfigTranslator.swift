import Foundation

/// Turns VS Code launch configurations (Python, Go, Node, CodeLLDB) into runnable service definitions.
public enum LaunchConfigTranslator {
    static let reloadValueFlags: Set<String> = ["--reload-dir", "--reload-include", "--reload-exclude", "--reload-delay"]

    struct SkipReason: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    struct Candidate {
        var definition: ServiceDefinition
        var hadReload: Bool
        var ecosystem: Ecosystem
    }

    struct MergeKey: Hashable {
        var command: [String]
        var cwd: String
        var envFile: String?
        var env: [String: String]
    }

    public static func translate(_ configs: [LaunchConfig], repo: URL) -> TranslationResult {
        var candidates: [Candidate] = []
        var skipped: [SkippedConfig] = []
        var warnings: [String] = []
        for config in configs {
            switch candidate(from: config, repo: repo) {
            case .success(let candidate):
                candidates.append(candidate)
                if let task = config.preLaunchTask {
                    warnings.append("\(config.name): preLaunchTask '\(task)' çalıştırılmıyor")
                }
            case .failure(let reason):
                skipped.append(SkippedConfig(name: config.name, reason: reason.message))
            }
        }
        var taken = Set<String>()
        let merged = merge(candidates)
        let services = merged.map { candidate -> DiscoveredService in
            let slug = Slug.unique(Slug.make(candidate.definition.name), taken: taken)
            taken.insert(slug)
            return DiscoveredService(
                id: "\(repo.lastPathComponent)/\(slug)",
                source: .launchJson(candidate.definition.name),
                definition: candidate.definition
            )
        }
        return TranslationResult(
            services: services,
            skipped: skipped,
            warnings: warnings,
            ecosystems: Set(merged.map(\.ecosystem))
        )
    }

    static func candidate(from config: LaunchConfig, repo: URL) -> Result<Candidate, SkipReason> {
        guard config.request == "launch" else {
            return .failure(SkipReason("request 'launch' değil"))
        }
        guard let type = config.type, let ecosystem = Ecosystem.forLaunchType(type) else {
            return .failure(SkipReason("desteklenmeyen tür: \(config.type ?? "-")"))
        }
        // Java needs the extension's classpath; coreclr runs a prebuilt dll. Their manifests are used instead.
        if ecosystem == .java || ecosystem == .dotnet {
            return .failure(SkipReason("proje dosyasından çalıştırılıyor"))
        }
        if config.module == "pytest" || config.purpose.contains("debug-test") || config.mode == "test"
            || config.cargoArgs?.contains("test") == true {
            return .failure(SkipReason("test konfigürasyonu"))
        }
        if config.variables.contains(where: { $0.hasPrefix("file") }) {
            return .failure(SkipReason("aktif dosyaya bağlı (${file})"))
        }
        if let other = config.variables.sorted().first(where: { $0 != "workspaceFolder" }) {
            return .failure(SkipReason("desteklenmeyen değişken: ${\(other)}"))
        }

        switch ecosystem {
        case .go: return goCandidate(from: config, repo: repo)
        case .node: return nodeCandidate(from: config, repo: repo)
        case .rust: return rustCandidate(from: config, repo: repo)
        case .python, .java, .dotnet: return pythonCandidate(from: config, repo: repo)
        }
    }

    static func substitute(_ text: String, repo: URL) -> String {
        text.replacingOccurrences(of: "${workspaceFolder}", with: repo.path)
    }

    static func goCandidate(from config: LaunchConfig, repo: URL) -> Result<Candidate, SkipReason> {
        func substitute(_ text: String) -> String { Self.substitute(text, repo: repo) }
        guard let program = config.program.map(substitute) else {
            return .failure(SkipReason("program tanımlı değil"))
        }
        let cwd = config.cwd.map(substitute) ?? repo.path
        let args = config.args.map(substitute)
        let command: [String]
        if config.mode == "exec" {
            command = [program] + args
        } else {
            command = ["go", "run"] + config.buildFlags.map(substitute) + [goPackagePath(program, cwd: cwd)] + args
        }
        return .success(simpleCandidate(config, repo: repo, command: command, args: args, ecosystem: .go))
    }

    static func nodeCandidate(from config: LaunchConfig, repo: URL) -> Result<Candidate, SkipReason> {
        func substitute(_ text: String) -> String { Self.substitute(text, repo: repo) }
        let program = config.program.map(substitute)
        let runtime = config.runtimeExecutable.map(substitute)
        if runtime == nil {
            guard let program else { return .failure(SkipReason("program tanımlı değil")) }
            if program.hasSuffix(".ts") || program.hasSuffix(".mts") || program.hasSuffix(".tsx") {
                return .failure(SkipReason("TypeScript programı için runtimeExecutable gerekli"))
            }
        }
        let args = config.args.map(substitute)
        let command = [runtime ?? "node"] + config.runtimeArgs.map(substitute) + (program.map { [$0] } ?? []) + args
        return .success(simpleCandidate(config, repo: repo, command: command, args: args, ecosystem: .node))
    }

    static func rustCandidate(from config: LaunchConfig, repo: URL) -> Result<Candidate, SkipReason> {
        guard let cargoArgs = config.cargoArgs else {
            return .failure(SkipReason("cargo bloğu yok; Cargo.toml kullanılıyor"))
        }
        let args = config.args.map { substitute($0, repo: repo) }
        let flags = cargoArgs.filter { $0 != "build" && $0 != "run" }.map { substitute($0, repo: repo) }
        let command = ["cargo", "run"] + flags + (args.isEmpty ? [] : ["--"] + args)
        return .success(simpleCandidate(config, repo: repo, command: command, args: args, ecosystem: .rust))
    }

    /// A non-reloading service with the shared cwd/env/envFile rules.
    static func simpleCandidate(
        _ config: LaunchConfig, repo: URL, command: [String], args: [String], ecosystem: Ecosystem
    ) -> Candidate {
        let env = config.env.mapValues { substitute($0, repo: repo) }
        let definition = ServiceDefinition(
            name: config.name,
            command: command,
            cwd: config.cwd.map { substitute($0, repo: repo) } ?? repo.path,
            envFile: config.envFile.map { substitute($0, repo: repo) } ?? repo.appendingPathComponent(".env").path,
            env: env,
            portHint: portHint(args: args, env: env)
        )
        return Candidate(definition: definition, hadReload: false, ecosystem: ecosystem)
    }

    /// `go run` target for `program`: "." or "./sub" when inside `cwd`, otherwise the path unchanged.
    static func goPackagePath(_ program: String, cwd: String) -> String {
        let trimmed = program.count > 1 && program.hasSuffix("/") ? String(program.dropLast()) : program
        guard trimmed.hasPrefix("/") else { return trimmed }
        if trimmed == cwd { return "." }
        if trimmed.hasPrefix(cwd + "/") { return "./" + trimmed.dropFirst(cwd.count + 1) }
        return trimmed
    }

    static func pythonCandidate(from config: LaunchConfig, repo: URL) -> Result<Candidate, SkipReason> {
        let root = repo.path
        func substitute(_ text: String) -> String { Self.substitute(text, repo: repo) }

        let python = config.python.map(substitute) ?? repo.appendingPathComponent(".venv/bin/python").path
        let base: [String]
        if let module = config.module {
            base = [python, "-m", module]
        } else if let program = config.program {
            base = [python, substitute(program)]
        } else {
            return .failure(SkipReason("module veya program tanımlı değil"))
        }

        var args = config.args.map(substitute)
        let isUvicorn = config.module == "uvicorn"
        var reloadArgs: [String] = []
        var hadReload = false
        if isUvicorn {
            let split = splitReloadArgs(args)
            args = split.args
            hadReload = split.hadReload
            reloadArgs = ["--reload"] + split.extras
        }

        let env = config.env.mapValues(substitute)
        let definition = ServiceDefinition(
            name: config.name,
            command: base + args,
            cwd: config.cwd.map(substitute) ?? root,
            envFile: config.envFile.map(substitute) ?? repo.appendingPathComponent(".env").path,
            env: env,
            supportsReload: isUvicorn,
            reloadEnabled: hadReload,
            reloadArgs: reloadArgs,
            portHint: portHint(args: args, env: env)
        )
        return .success(Candidate(definition: definition, hadReload: hadReload, ecosystem: .python))
    }

    static func splitReloadArgs(_ args: [String]) -> (args: [String], extras: [String], hadReload: Bool) {
        var kept: [String] = []
        var extras: [String] = []
        var hadReload = false
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--reload" {
                hadReload = true
            } else if reloadValueFlags.contains(arg) {
                extras.append(arg)
                if i + 1 < args.count {
                    extras.append(args[i + 1])
                    i += 1
                }
            } else if reloadValueFlags.contains(where: { arg.hasPrefix($0 + "=") }) {
                extras.append(arg)
            } else {
                kept.append(arg)
            }
            i += 1
        }
        return (kept, extras, hadReload)
    }

    static func portHint(args: [String], env: [String: String]) -> Int? {
        for (i, arg) in args.enumerated() {
            for flag in ["--port", "-port"] {
                if arg == flag, i + 1 < args.count, let port = Int(args[i + 1]) { return port }
                if arg.hasPrefix(flag + "="), let port = Int(arg.dropFirst(flag.count + 1)) { return port }
            }
        }
        return env["PORT"].flatMap { Int($0) }
    }

    /// Configs identical except for reload flags collapse into one service with a reload toggle.
    static func merge(_ candidates: [Candidate]) -> [Candidate] {
        var order: [MergeKey] = []
        var groups: [MergeKey: [Candidate]] = [:]
        for candidate in candidates {
            let d = candidate.definition
            let key = MergeKey(command: d.command, cwd: d.cwd, envFile: d.envFile, env: d.env)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(candidate)
        }
        return order.map { key in
            let group = groups[key] ?? []
            var chosen = group.first(where: { !$0.hadReload }) ?? group[0]
            if let withReload = group.first(where: { $0.hadReload }) {
                chosen.definition.reloadEnabled = true
                chosen.definition.reloadArgs = withReload.definition.reloadArgs
                chosen.hadReload = true
            }
            return chosen
        }
    }
}
