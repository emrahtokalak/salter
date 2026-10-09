import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool
    public var crashNotifications: Bool

    public init(launchAtLogin: Bool = false, crashNotifications: Bool = true) {
        self.launchAtLogin = launchAtLogin
        self.crashNotifications = crashNotifications
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        crashNotifications = try c.decodeIfPresent(Bool.self, forKey: .crashNotifications) ?? true
    }
}

public struct RepoConfig: Codable, Equatable, Sendable {
    public var path: String
    public var services: [ServiceConfig]
    /// Discovered sources the user chose not to add; they are not suggested again.
    public var declinedSources: [ServiceSource]

    public init(path: String, services: [ServiceConfig] = [], declinedSources: [ServiceSource] = []) {
        self.path = path
        self.services = services
        self.declinedSources = declinedSources
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        services = try c.decodeIfPresent([ServiceConfig].self, forKey: .services) ?? []
        declinedSources = try c.decodeIfPresent([ServiceSource].self, forKey: .declinedSources) ?? []
    }

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var roots: [String]
    public var ignoredRepos: [String]
    public var pinnedOrder: [String]
    public var settings: AppSettings
    public var repos: [RepoConfig]

    public init(
        version: Int = AppConfig.currentVersion,
        roots: [String] = [],
        ignoredRepos: [String] = [],
        pinnedOrder: [String] = [],
        settings: AppSettings = AppSettings(),
        repos: [RepoConfig] = []
    ) {
        self.version = version
        self.roots = roots
        self.ignoredRepos = ignoredRepos
        self.pinnedOrder = pinnedOrder
        self.settings = settings
        self.repos = repos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        roots = try c.decodeIfPresent([String].self, forKey: .roots) ?? []
        ignoredRepos = try c.decodeIfPresent([String].self, forKey: .ignoredRepos) ?? []
        pinnedOrder = try c.decodeIfPresent([String].self, forKey: .pinnedOrder) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        repos = try c.decodeIfPresent([RepoConfig].self, forKey: .repos) ?? []
    }

    public static func defaultConfig(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AppConfig {
        AppConfig(roots: [home.appendingPathComponent("Projects/acme").path])
    }

    public func service(id: String) -> ServiceConfig? {
        for repo in repos {
            if let service = repo.services.first(where: { $0.id == id }) { return service }
        }
        return nil
    }

    public func repo(containing serviceID: String) -> RepoConfig? {
        repos.first { $0.services.contains { $0.id == serviceID } }
    }

    public func repoIndex(path: String) -> Int? {
        repos.firstIndex { $0.path == path }
    }

    public var allServiceIDs: Set<String> {
        Set(repos.flatMap { $0.services.map(\.id) })
    }
}
