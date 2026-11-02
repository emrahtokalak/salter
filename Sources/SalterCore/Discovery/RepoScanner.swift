import Foundation

public struct RepoDiscovery: Equatable, Sendable {
    public var repoPath: String
    public var services: [DiscoveredService]
    public var skipped: [SkippedConfig]
    public var warnings: [String]

    public init(repoPath: String, services: [DiscoveredService], skipped: [SkippedConfig], warnings: [String]) {
        self.repoPath = repoPath
        self.services = services
        self.skipped = skipped
        self.warnings = warnings
    }
}

public enum RepoScanner {
    static let excludedNames: Set<String> = ["node_modules"]

    /// First-level, non-hidden subdirectories of `root`, sorted by name.
    public static func candidateRepos(in root: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return items
            .filter { url in
                !excludedNames.contains(url.lastPathComponent)
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Manifest detectors, run for ecosystems launch.json produced no service for.
    static let detectors: [any ManifestDetector.Type] = [GoDetector.self, RustDetector.self, JavaDetector.self]

    public static func discover(repo: URL) -> RepoDiscovery {
        var services: [DiscoveredService] = []
        var skipped: [SkippedConfig] = []
        var warnings: [String] = []
        var launchEcosystems = Set<Ecosystem>()

        if let data = try? Data(contentsOf: repo.appendingPathComponent(".vscode/launch.json")) {
            do {
                let result = LaunchConfigTranslator.translate(try LaunchJsonParser.parse(data), repo: repo)
                services += result.services
                skipped += result.skipped
                warnings += result.warnings
                launchEcosystems = result.ecosystems
            } catch {
                warnings.append(".vscode/launch.json okunamadı: \(error)")
            }
        }
        if let data = try? Data(contentsOf: repo.appendingPathComponent("package.json")) {
            do {
                let result = try PackageJsonTranslator.translate(data, repo: repo)
                for package in result.services {
                    // A launch config running the same script (e.g. runtimeExecutable npm + run dev) is a duplicate;
                    // the package.json service wins so existing package.json sources stay stable.
                    services.removeAll { launch in
                        guard launch.definition.command == package.definition.command,
                              launch.definition.cwd == package.definition.cwd else { return false }
                        skipped.append(SkippedConfig(
                            name: launch.source.name ?? launch.definition.name,
                            reason: "package.json '\(package.source.name ?? "")' ile aynı"
                        ))
                        return true
                    }
                }
                services += result.services
                skipped += result.skipped
            } catch {
                warnings.append("package.json okunamadı: \(error)")
            }
        }
        for detector in detectors where !launchEcosystems.contains(detector.ecosystem) {
            let result = detector.detect(repo: repo)
            services += result.services
            skipped += result.skipped
            warnings += result.warnings
        }

        var taken = Set<String>()
        for i in services.indices {
            let id = Slug.unique(services[i].id, taken: taken)
            services[i].id = id
            taken.insert(id)
        }
        return RepoDiscovery(repoPath: repo.path, services: services, skipped: skipped, warnings: warnings)
    }
}
