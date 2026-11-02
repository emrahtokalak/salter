import Foundation
import Testing
@testable import SalterCore

@Suite struct RustDetectorTests {
    @Test func singleBinaryUsesPlainCargoRun() throws {
        let repo = try makeRepo("api", ["Cargo.toml": "[package]\nname = \"api\"\n", "src/main.rs": "fn main() {}\n"])
        let r = RustDetector.detect(repo: repo)
        #expect(r.services.map(\.definition.command) == [["cargo", "run"]])
        #expect(r.services.map(\.source) == [.manifest("rust:api/api")])
        #expect(r.services.first?.definition.name == "api")
        #expect(r.ecosystems == [.rust])
    }

    @Test func multipleBinsInOnePackage() throws {
        let repo = try makeRepo("app", [
            "Cargo.toml": "[package]\nname = \"app\"\n\n[[bin]]\nname = \"srv\"\npath = \"src/srv.rs\"\n",
            "src/main.rs": "", "src/srv.rs": "", "src/bin/tool.rs": "", "src/bin/gen/main.rs": "",
        ])
        let r = RustDetector.detect(repo: repo)
        #expect(r.services.map(\.definition.command) == [
            ["cargo", "run", "--bin", "srv"],
            ["cargo", "run", "--bin", "app"],
            ["cargo", "run", "--bin", "gen"],
            ["cargo", "run", "--bin", "tool"],
        ])
    }

    @Test func workspaceWithGlobMembers() throws {
        let repo = try makeRepo("ws", [
            "Cargo.toml": "[workspace]\nmembers = [\n  \"crates/*\",\n]\n",
            "crates/a/Cargo.toml": "[package]\nname = \"a\"\n", "crates/a/src/main.rs": "",
            "crates/b/Cargo.toml": "[package]\nname = \"b\"\n", "crates/b/src/lib.rs": "",
        ])
        let r = RustDetector.detect(repo: repo)
        #expect(r.services.map(\.definition.command) == [["cargo", "run", "-p", "a"]])
        #expect(r.services.first?.definition.cwd == repo.path)
        #expect(r.services.first?.source == .manifest("rust:a/a"))
    }

    @Test func workspaceWithSeveralBinaries() throws {
        let repo = try makeRepo("ws", [
            "Cargo.toml": "[workspace]\nmembers = [\"api\", \"cli\"]\n",
            "api/Cargo.toml": "[package]\nname = \"api\"\n", "api/src/main.rs": "",
            "cli/Cargo.toml": "[package]\nname = \"cli\"\n", "cli/src/main.rs": "",
        ])
        #expect(RustDetector.detect(repo: repo).services.map(\.definition.command) == [
            ["cargo", "run", "-p", "api", "--bin", "api"],
            ["cargo", "run", "-p", "cli", "--bin", "cli"],
        ])
    }

    @Test func autobinsFalseIgnoresSrcBin() throws {
        let repo = try makeRepo("x", [
            "Cargo.toml": "[package]\nname = \"x\"\nautobins = false\n\n[[bin]]\nname = \"only\"\npath = \"src/only.rs\"\n",
            "src/main.rs": "", "src/bin/extra.rs": "",
        ])
        #expect(RustDetector.detect(repo: repo).services.map(\.definition.command) == [["cargo", "run"]])
    }

    @Test func libOnlyYieldsNothing() throws {
        let repo = try makeRepo("lib", ["Cargo.toml": "[package]\nname = \"lib\"\n", "src/lib.rs": ""])
        let r = RustDetector.detect(repo: repo)
        #expect(r.services.isEmpty)
        #expect(r.ecosystems.isEmpty)
    }
}
