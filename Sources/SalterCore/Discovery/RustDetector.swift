import Foundation

/// `Cargo.toml` at the repo root: every binary target of the root package and of workspace members.
public enum RustDetector: ManifestDetector {
    public static let ecosystem = Ecosystem.rust

    struct Package {
        var name: String
        var bins: [String]
    }

    public static func detect(repo: URL) -> TranslationResult {
        guard let root = manifest(repo) else { return TranslationResult(services: [], skipped: []) }
        var packages: [Package] = []
        if let package = package(at: repo, manifest: root) { packages.append(package) }
        if case .strings(let members)? = root.tables["workspace"]?["members"] {
            for dir in expand(members, in: repo) {
                if let toml = manifest(dir), let package = package(at: dir, manifest: toml) {
                    packages.append(package)
                }
            }
        }
        let total = packages.reduce(0) { $0 + $1.bins.count }
        let isWorkspace = root.tables["workspace"] != nil
        var services: [DiscoveredService] = []
        for package in packages {
            for bin in package.bins {
                var command = ["cargo", "run"]
                if packages.count > 1 || (isWorkspace && package.name != rootPackageName(root)) {
                    command += ["-p", package.name]
                }
                if total > 1 { command += ["--bin", bin] }
                services.append(ProjectFiles.service(
                    repo: repo, name: bin, target: "rust:\(package.name)/\(bin)", command: command
                ))
            }
        }
        return TranslationResult(services: services, skipped: [], ecosystems: services.isEmpty ? [] : [.rust])
    }

    static func manifest(_ dir: URL) -> MiniTOML? {
        ProjectFiles.read(dir.appendingPathComponent("Cargo.toml")).map(MiniTOML.parse)
    }

    static func rootPackageName(_ toml: MiniTOML) -> String? {
        if case .string(let name)? = toml.tables["package"]?["name"] { return name }
        return nil
    }

    /// Binary targets: explicit `[[bin]]`, then (unless `autobins = false`) src/main.rs, src/bin/*.rs, src/bin/<name>/main.rs.
    static func package(at dir: URL, manifest toml: MiniTOML) -> Package? {
        guard let name = rootPackageName(toml) else { return nil }
        var bins: [String] = []
        for entry in toml.arrayTables["bin"] ?? [] {
            if case .string(let bin)? = entry["name"], !bins.contains(bin) { bins.append(bin) }
        }
        if toml.tables["package"]?["autobins"] != .bool(false) {
            var auto: [String] = []
            if ProjectFiles.exists(dir.appendingPathComponent("src/main.rs")) { auto.append(name) }
            for item in ProjectFiles.children(of: dir.appendingPathComponent("src/bin")) {
                if item.pathExtension == "rs" {
                    auto.append(item.deletingPathExtension().lastPathComponent)
                } else if ProjectFiles.exists(item.appendingPathComponent("main.rs")) {
                    auto.append(item.lastPathComponent)
                }
            }
            bins += auto.filter { !bins.contains($0) }
        }
        return Package(name: name, bins: bins)
    }

    /// Workspace member paths; a trailing `*` segment expands to the sorted subdirectories.
    static func expand(_ members: [String], in repo: URL) -> [URL] {
        var dirs: [URL] = []
        for member in members {
            if member.hasSuffix("/*") {
                let parent = repo.appendingPathComponent(String(member.dropLast(2)))
                dirs += ProjectFiles.children(of: parent).filter(ProjectFiles.isDirectory)
            } else if member == "." {
                continue
            } else {
                dirs.append(repo.appendingPathComponent(member))
            }
        }
        return dirs
    }
}
