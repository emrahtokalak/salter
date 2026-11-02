import Foundation

/// Finds services from a project manifest (go.mod, Cargo.toml, pom.xml, *.csproj, ...).
public protocol ManifestDetector {
    static var ecosystem: Ecosystem { get }
    static func detect(repo: URL) -> TranslationResult
}

/// Filesystem helpers shared by manifest detectors.
enum ProjectFiles {
    static let excludedDirectories: Set<String> = ["vendor", "node_modules", "target", "build", "bin", "obj", "dist", "testdata"]

    /// Files under `repo` (at most `maxDepth` directories deep; hidden and excluded directories skipped),
    /// sorted by relative path.
    static func files(in repo: URL, maxDepth: Int = 4, matching: (URL) -> Bool) -> [URL] {
        var found: [URL] = []
        func walk(_ dir: URL, depth: Int) {
            for item in children(of: dir) {
                if isDirectory(item) {
                    if depth < maxDepth, !excludedDirectories.contains(item.lastPathComponent) {
                        walk(item, depth: depth + 1)
                    }
                } else if matching(item) {
                    found.append(item)
                }
            }
        }
        walk(repo, depth: 0)
        return found.sorted { relativePath($0, to: repo) < relativePath($1, to: repo) }
    }

    /// Non-hidden entries of `dir`, sorted by name. URLs are built from `dir`, so prefixes stay stable.
    static func children(of dir: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { dir.appendingPathComponent($0) }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    static func relativePath(_ url: URL, to repo: URL) -> String {
        let base = repo.path.hasSuffix("/") ? repo.path : repo.path + "/"
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.path
    }

    /// A manifest-derived service: cwd is the repo root and the env file `<repo>/.env`.
    static func service(repo: URL, name: String, target: String, command: [String], portHint: Int? = nil) -> DiscoveredService {
        DiscoveredService(
            id: "\(repo.lastPathComponent)/\(Slug.make(name))",
            source: .manifest(target),
            definition: ServiceDefinition(
                name: name,
                command: command,
                cwd: repo.path,
                envFile: repo.appendingPathComponent(".env").path,
                portHint: portHint
            )
        )
    }
}
