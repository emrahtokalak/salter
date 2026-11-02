import Foundation

/// `go.mod` at the repo root: every `cmd/<name>` main package, plus a root main package.
public enum GoDetector: ManifestDetector {
    public static let ecosystem = Ecosystem.go

    public static func detect(repo: URL) -> TranslationResult {
        guard ProjectFiles.exists(repo.appendingPathComponent("go.mod")) else {
            return TranslationResult(services: [], skipped: [])
        }
        var services: [DiscoveredService] = []
        if isMainPackage(repo) {
            services.append(ProjectFiles.service(
                repo: repo, name: repo.lastPathComponent, target: "go:.", command: ["go", "run", "."]
            ))
        }
        for dir in ProjectFiles.children(of: repo.appendingPathComponent("cmd"))
        where ProjectFiles.isDirectory(dir) && isMainPackage(dir) {
            let name = dir.lastPathComponent
            services.append(ProjectFiles.service(
                repo: repo, name: name, target: "go:cmd/\(name)", command: ["go", "run", "./cmd/\(name)"]
            ))
        }
        return TranslationResult(services: services, skipped: [], ecosystems: services.isEmpty ? [] : [.go])
    }

    /// Whether `dir` holds a non-test `.go` file declaring `package main`.
    static func isMainPackage(_ dir: URL) -> Bool {
        ProjectFiles.children(of: dir).contains { file in
            file.pathExtension == "go" && !file.lastPathComponent.hasSuffix("_test.go")
                && ProjectFiles.read(file).flatMap(packageClause) == "main"
        }
    }

    /// The package name from a Go source file's `package` clause, skipping comments and build tags.
    static func packageClause(_ source: String) -> String? {
        var inBlock = false
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if inBlock {
                guard let end = line.range(of: "*/") else { continue }
                inBlock = false
                line = line[end.upperBound...].trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("/*") {
                if let end = line.range(of: "*/", range: line.index(line.startIndex, offsetBy: 2)..<line.endIndex) {
                    line = line[end.upperBound...].trimmingCharacters(in: .whitespaces)
                } else {
                    inBlock = true
                    continue
                }
            }
            if line.isEmpty || line.hasPrefix("//") { continue }
            let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard words.first == "package", words.count >= 2 else { return nil }
            return String(words[1])
        }
        return nil
    }
}
