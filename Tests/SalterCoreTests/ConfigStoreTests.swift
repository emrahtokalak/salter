import Foundation
import Testing
@testable import SalterCore

@Suite struct ConfigStoreTests {
    func sampleConfig() -> AppConfig {
        var service = ServiceConfig(
            id: "api/dev",
            source: .launchJson("dev"),
            discovered: ServiceDefinition(
                name: "dev", command: ["/api/.venv/bin/python", "-m", "uvicorn", "a:app"], cwd: "/api",
                envFile: "/api/.env", supportsReload: true, reloadArgs: ["--reload"], portHint: 8000
            )
        )
        service.overrides.reloadEnabled = true
        return AppConfig(
            roots: ["/root"],
            ignoredRepos: ["/root/docs"],
            pinnedOrder: ["api/dev"],
            repos: [RepoConfig(path: "/api", services: [service], declinedSources: [.launchJson("tests")])]
        )
    }

    @Test func savesAndLoadsRoundTrip() throws {
        let dir = try makeTempDirectory().appendingPathComponent("nested")
        let store = ConfigStore(directory: dir)
        try store.save(sampleConfig())
        let loaded = store.load()
        #expect(loaded.warning == nil)
        #expect(loaded.config == sampleConfig())
    }

    @Test func missingFileGivesDefault() throws {
        let store = ConfigStore(directory: try makeTempDirectory())
        let loaded = store.load(defaultConfig: AppConfig(roots: ["/default"]))
        #expect(loaded.config.roots == ["/default"])
        #expect(loaded.warning == nil)
    }

    @Test func brokenFileIsBackedUp() throws {
        let dir = try makeTempDirectory()
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent("config.json"))
        let store = ConfigStore(directory: dir, now: { Date(timeIntervalSince1970: 0) })
        let loaded = store.load(defaultConfig: AppConfig(roots: ["/default"]))
        #expect(loaded.config.roots == ["/default"])
        #expect(loaded.warning?.contains("config.json.broken-") == true)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("config.json.broken-") })
        #expect(!files.contains("config.json"))
    }

    @Test func toleratesMissingFields() throws {
        let dir = try makeTempDirectory()
        try Data(#"{ "roots": ["/a"], "repos": [ { "path": "/a/x" } ] }"#.utf8).write(to: dir.appendingPathComponent("config.json"))
        let loaded = ConfigStore(directory: dir).load()
        #expect(loaded.warning == nil)
        #expect(loaded.config.roots == ["/a"])
        #expect(loaded.config.repos.first?.services == [])
        #expect(loaded.config.repos.first?.declinedSources == [])
        #expect(loaded.config.settings.crashNotifications)
        #expect(loaded.config.version == AppConfig.currentVersion)
    }

    @Test func migratesLegacyDirectoryOnce() throws {
        let base = try makeTempDirectory()
        let legacy = base.appendingPathComponent("DevLauncher")
        let current = base.appendingPathComponent("Salter")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data(#"{ "roots": ["/legacy"] }"#.utf8).write(to: legacy.appendingPathComponent("config.json"))
        #expect(ConfigStore.migrateLegacyDirectory(from: legacy, to: current))
        #expect(ConfigStore(directory: current).load().config.roots == ["/legacy"])
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!ConfigStore.migrateLegacyDirectory(from: legacy, to: current))
    }

    @Test func migrationNeverOverwritesExistingDirectory() throws {
        let base = try makeTempDirectory()
        let legacy = base.appendingPathComponent("DevLauncher")
        let current = base.appendingPathComponent("Salter")
        for dir in [legacy, current] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(#"{ "roots": ["\#(dir.lastPathComponent)"] }"#.utf8).write(to: dir.appendingPathComponent("config.json"))
        }
        #expect(!ConfigStore.migrateLegacyDirectory(from: legacy, to: current))
        #expect(ConfigStore(directory: current).load().config.roots == ["Salter"])
        #expect(ConfigStore(directory: legacy).load().config.roots == ["DevLauncher"])
    }

    @Test func lookupHelpers() {
        let c = sampleConfig()
        #expect(c.service(id: "api/dev")?.overrides.reloadEnabled == true)
        #expect(c.service(id: "nope") == nil)
        #expect(c.repo(containing: "api/dev")?.path == "/api")
        #expect(c.repo(containing: "api/dev")?.name == "api")
        #expect(c.repoIndex(path: "/api") == 0)
        #expect(c.allServiceIDs == ["api/dev"])
        #expect(AppConfig.defaultConfig(home: URL(fileURLWithPath: "/Users/u")).roots == ["/Users/u/Projects"])
    }
}
