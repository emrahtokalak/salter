import Foundation

public struct ConfigLoadResult: Equatable, Sendable {
    public var config: AppConfig
    /// Set when an unreadable config.json was moved aside.
    public var warning: String?
}

public final class ConfigStore {
    public let fileURL: URL
    private let now: () -> Date

    public init(directory: URL, now: @escaping () -> Date = { Date() }) {
        fileURL = directory.appendingPathComponent("config.json")
        self.now = now
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevLauncher")
    }

    public func load(defaultConfig: AppConfig = .defaultConfig()) -> ConfigLoadResult {
        guard let data = try? Data(contentsOf: fileURL) else {
            return ConfigLoadResult(config: defaultConfig, warning: nil)
        }
        do {
            return ConfigLoadResult(config: try JSONDecoder().decode(AppConfig.self, from: data), warning: nil)
        } catch {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("config.json.broken-\(formatter.string(from: now()))")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return ConfigLoadResult(
                config: defaultConfig,
                warning: "config.json okunamadı; yedeği \(backup.lastPathComponent) olarak saklandı."
            )
        }
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }
}
