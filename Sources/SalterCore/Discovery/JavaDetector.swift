import Foundation

/// Root `pom.xml` (Maven) or `build.gradle(.kts)` (Gradle) with a run plugin: Spring Boot, exec or application.
public enum JavaDetector: ManifestDetector {
    public static let ecosystem = Ecosystem.java

    public static func detect(repo: URL) -> TranslationResult {
        let pom = repo.appendingPathComponent("pom.xml")
        if let text = ProjectFiles.read(pom) {
            let runner = wrapper("mvnw", in: repo) ?? "mvn"
            if text.contains("spring-boot-maven-plugin") {
                return found(repo, "spring-boot", "java:pom.xml", [runner, "spring-boot:run"], springBoot: true)
            }
            if text.contains("exec-maven-plugin") {
                return found(repo, "exec", "java:pom.xml", [runner, "exec:java"], springBoot: false)
            }
            return skipped("pom.xml", "spring-boot / exec")
        }
        for file in ["build.gradle", "build.gradle.kts"] {
            guard let text = ProjectFiles.read(repo.appendingPathComponent(file)) else { continue }
            let runner = wrapper("gradlew", in: repo) ?? "gradle"
            if text.contains("org.springframework.boot") {
                return found(repo, "bootRun", "java:\(file)", [runner, "bootRun"], springBoot: true)
            }
            if hasApplicationPlugin(text) {
                return found(repo, "run", "java:\(file)", [runner, "run"], springBoot: false)
            }
            return skipped(file, "spring-boot / application")
        }
        return TranslationResult(services: [], skipped: [])
    }

    static func wrapper(_ name: String, in repo: URL) -> String? {
        let url = repo.appendingPathComponent(name)
        return ProjectFiles.exists(url) ? url.path : nil
    }

    static func found(_ repo: URL, _ name: String, _ target: String, _ command: [String], springBoot: Bool) -> TranslationResult {
        let port = configuredPort(repo) ?? (springBoot ? 8080 : nil)
        let service = ProjectFiles.service(repo: repo, name: name, target: target, command: command, portHint: port)
        return TranslationResult(services: [service], skipped: [], ecosystems: [.java])
    }

    static func skipped(_ file: String, _ plugins: String) -> TranslationResult {
        TranslationResult(services: [], skipped: [
            SkippedConfig(name: file, reason: "çalıştırma eklentisi bulunamadı (\(plugins))"),
        ])
    }

    static func hasApplicationPlugin(_ text: String) -> Bool {
        let patterns = [#"id\s*\(?\s*["']application["']"#, #"apply\s+plugin\s*:\s*["']application["']"#, #"(?m)^\s*application\s*$"#]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// `server.port` from src/main/resources/application.properties or `server: port:` from application.yml/.yaml.
    static func configuredPort(_ repo: URL) -> Int? {
        let resources = repo.appendingPathComponent("src/main/resources")
        if let text = ProjectFiles.read(resources.appendingPathComponent("application.properties")) {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[0] == "server.port", let port = Int(parts[1]) { return port }
            }
        }
        for name in ["application.yml", "application.yaml"] {
            guard let text = ProjectFiles.read(resources.appendingPathComponent(name)) else { continue }
            var inServer = false
            for line in text.split(separator: "\n") {
                let indented = line.first == " " || line.first == "\t"
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !indented { inServer = trimmed == "server:" ; continue }
                if inServer, trimmed.hasPrefix("port:"), let port = Int(trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
                    return port
                }
            }
        }
        return nil
    }
}
