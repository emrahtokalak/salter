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
            .appendingPathComponent("Salter")
    }

    /// Where the app kept its data before it was renamed from DevLauncher to Şalter.
    public static var legacyDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevLauncher")
    }

    /// Moves `legacy` to `current` when only the legacy directory exists. Returns true if it moved.
    @discardableResult
    public static func migrateLegacyDirectory(from legacy: URL, to current: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: current.path) else { return false }
        do {
            try fm.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: legacy, to: current)
            return true
        } catch {
            return false
        }
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
