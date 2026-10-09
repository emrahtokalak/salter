import Foundation

/// Turns a package.json `dev` (or `start`) script into a service definition.
public enum PackageJsonTranslator {
    static let lockFiles: [(file: String, manager: PackageManager)] = [
        ("pnpm-lock.yaml", .pnpm),
        ("package-lock.json", .npm),
        ("yarn.lock", .yarn),
    ]

    public static func translate(
        _ data: Data,
        repo: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> TranslationResult {
        let root = try JSONCReader.object(from: data)
        let scripts = root["scripts"] as? [String: Any] ?? [:]
        guard let scriptName = ["dev", "start"].first(where: { scripts[$0] is String }),
              let script = scripts[scriptName] as? String else {
            return TranslationResult(services: [], skipped: [])
        }
        let manager = packageManager(repo: repo, fileExists: fileExists)
        let definition = ServiceDefinition(
            name: scriptName,
            command: [manager.rawValue, "run", scriptName],
            cwd: repo.path,
            portHint: portHint(script: script)
        )
        let service = DiscoveredService(
            id: "\(repo.lastPathComponent)/\(Slug.make(scriptName))",
            source: .packageJson(scriptName),
            definition: definition
        )
        return TranslationResult(services: [service], skipped: [])
    }

    public static func packageManager(repo: URL, fileExists: (String) -> Bool) -> PackageManager {
        lockFiles.first { fileExists(repo.appendingPathComponent($0.file).path) }?.manager ?? .npm
    }

    static func portHint(script: String) -> Int? {
        let words = ShellWords.split(script)
        for (i, word) in words.enumerated() {
            if word == "--port" || word == "-p", i + 1 < words.count, let port = Int(words[i + 1]) { return port }
            if word.hasPrefix("--port="), let port = Int(word.dropFirst("--port=".count)) { return port }
        }
        if words.contains(where: { $0 == "vite" || $0.hasSuffix("/vite") }) { return 5173 }
        if words.contains("next") { return 3000 }
        return nil
    }
}
