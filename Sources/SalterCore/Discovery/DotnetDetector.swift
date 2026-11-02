import Foundation

/// Runnable `*.csproj` files (Web/Worker SDK or `OutputType` Exe), excluding test projects.
public enum DotnetDetector: ManifestDetector {
    public static let ecosystem = Ecosystem.dotnet

    public static func detect(repo: URL) -> TranslationResult {
        let projects = ProjectFiles.files(in: repo) { $0.pathExtension == "csproj" }
        var services: [DiscoveredService] = []
        for project in projects {
            guard let text = ProjectFiles.read(project), isRunnable(text), !isTest(project, text) else { continue }
            let relative = ProjectFiles.relativePath(project, to: repo)
            services.append(ProjectFiles.service(
                repo: repo,
                name: project.deletingPathExtension().lastPathComponent,
                target: "dotnet:\(relative)",
                command: ["dotnet", "run", "--project", relative],
                portHint: launchSettingsPort(project.deletingLastPathComponent())
            ))
        }
        return TranslationResult(services: services, skipped: [], ecosystems: services.isEmpty ? [] : [.dotnet])
    }

    static func isRunnable(_ text: String) -> Bool {
        text.contains("Microsoft.NET.Sdk.Web") || text.contains("Microsoft.NET.Sdk.Worker")
            || text.range(of: #"<OutputType>\s*(Exe|WinExe)\s*</OutputType>"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isTest(_ project: URL, _ text: String) -> Bool {
        let name = project.deletingPathExtension().lastPathComponent
        return name.hasSuffix("Tests") || name.hasSuffix(".Test")
            || text.range(of: #"<IsTestProject>\s*true\s*</IsTestProject>"#, options: [.regularExpression, .caseInsensitive]) != nil
            || text.contains("Microsoft.NET.Test.Sdk")
    }

    /// Port of the first URL of the first "Project" profile (profiles sorted by name) in Properties/launchSettings.json.
    static func launchSettingsPort(_ projectDir: URL) -> Int? {
        guard let data = try? Data(contentsOf: projectDir.appendingPathComponent("Properties/launchSettings.json")),
              let root = try? JSONCReader.object(from: data),
              let profiles = root["profiles"] as? [String: Any] else { return nil }
        for key in profiles.keys.sorted() {
            guard let profile = profiles[key] as? [String: Any],
                  profile["commandName"] as? String == "Project",
                  let urls = profile["applicationUrl"] as? String,
                  let first = urls.split(separator: ";").first,
                  let port = URLComponents(string: String(first).trimmingCharacters(in: .whitespaces))?.port else { continue }
            return port
        }
        return nil
    }
}
