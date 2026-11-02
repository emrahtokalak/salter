import Foundation
import Testing
@testable import SalterCore

@Suite struct ModelTests {
    func definition() -> ServiceDefinition {
        ServiceDefinition(
            name: "API",
            command: ["/r/.venv/bin/python", "-m", "uvicorn", "app:app"],
            cwd: "/r",
            envFile: "/r/.env",
            env: ["A": "1"],
            supportsReload: true,
            reloadEnabled: false,
            reloadArgs: ["--reload", "--reload-dir", "src"],
            portHint: 8010
        )
    }

    @Test func launchCommandAppendsReloadArgsOnlyWhenEnabled() {
        var d = definition()
        #expect(d.launchCommand == d.command)
        d.reloadEnabled = true
        #expect(d.launchCommand == d.command + ["--reload", "--reload-dir", "src"])
        d.supportsReload = false
        #expect(d.launchCommand == d.command)
    }

    @Test func effectiveAppliesOverrides() {
        var cfg = ServiceConfig(id: "r/api", source: .launchJson("API"), discovered: definition())
        #expect(cfg.effective == definition())
        #expect(cfg.overrides.isEmpty)
        cfg.overrides.name = "My API"
        cfg.overrides.env = ["A": "2", "B": "3"]
        cfg.overrides.envFile = ""
        cfg.overrides.reloadEnabled = true
        cfg.overrides.portHint = 9000
        let e = cfg.effective
        #expect(e.name == "My API")
        #expect(e.env == ["A": "2", "B": "3"])
        #expect(e.envFile == nil)
        #expect(e.reloadEnabled)
        #expect(e.portHint == 9000)
        #expect(e.command == definition().command)
        #expect(!cfg.overrides.isEmpty)
    }

    @Test func overridesRoundTripThroughJSON() throws {
        var cfg = ServiceConfig(id: "r/api", source: .launchJson("API"), discovered: definition())
        cfg.overrides.command = ["x"]
        let decoded = try JSONDecoder().decode(ServiceConfig.self, from: JSONEncoder().encode(cfg))
        #expect(decoded == cfg)
    }

    @Test func slugs() {
        #expect(Slug.make("🚀 Debug FastAPI") == "debug-fastapi")
        #expect(Slug.make("API: uvicorn (debug)") == "api-uvicorn-debug")
        #expect(Slug.make("***") == "service")
        #expect(Slug.unique("dev", taken: ["dev", "dev-2"]) == "dev-3")
        #expect(Slug.unique("x", taken: []) == "x")
    }

    @Test func shellWordsRoundTrip() {
        let words = ["python", "-m", "app", "--name", "hello world", "it's", ""]
        #expect(ShellWords.split(ShellWords.join(words)) == words)
        #expect(ShellWords.split(#"a "b c" 'd e' f\ g"#) == ["a", "b c", "d e", "f g"])
        #expect(ShellWords.join(["--port", "8010", "/a/b.py"]) == "--port 8010 /a/b.py")
        #expect(ShellWords.split("   ").isEmpty)
    }

    @Test func manifestSourceRoundTrips() throws {
        let s = ServiceSource.manifest("go:cmd/api")
        #expect(s.kind == .manifest && s.name == "go:cmd/api")
        let back = try JSONDecoder().decode(ServiceSource.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func unknownSourceKindDecodesAsManual() throws {
        let s = try JSONDecoder().decode(ServiceSource.self, from: Data(#"{"kind":"future","name":"x"}"#.utf8))
        #expect(s.kind == .manual)
        #expect(s.name == "x")
    }
}
