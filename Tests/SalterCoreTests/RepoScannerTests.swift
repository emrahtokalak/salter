import Foundation
import Testing
@testable import SalterCore

@Suite struct RepoScannerTests {
    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func listsVisibleDirectoriesSorted() throws {
        let root = try makeTempDirectory()
        for name in ["b-repo", "a-repo", ".hidden", "node_modules"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try write("x", to: root.appendingPathComponent("file.txt"))
        #expect(RepoScanner.candidateRepos(in: root).map(\.lastPathComponent) == ["a-repo", "b-repo"])
        #expect(RepoScanner.candidateRepos(in: root.appendingPathComponent("missing")).isEmpty)
    }

    @Test func discoversLaunchAndPackageServicesWithUniqueIDs() throws {
        let repo = try makeTempDirectory().appendingPathComponent("web")
        try write(
            #"{ "configurations": [ { "name": "dev", "type": "debugpy", "request": "launch", "module": "uvicorn", "args": ["a:app"], }, ] } // c"#,
            to: repo.appendingPathComponent(".vscode/launch.json")
        )
        try write(#"{ "scripts": { "dev": "vite" } }"#, to: repo.appendingPathComponent("package.json"))
        let d = RepoScanner.discover(repo: repo)
        #expect(d.services.map(\.id) == ["web/dev", "web/dev-2"])
        #expect(d.services.map(\.source.kind) == [.launchJson, .packageJson])
        #expect(d.warnings.isEmpty)
    }

    @Test func brokenLaunchJsonIsReportedButPackageStillScanned() throws {
        let repo = try makeTempDirectory().appendingPathComponent("api")
        try write("{ not json", to: repo.appendingPathComponent(".vscode/launch.json"))
        try write(#"{ "scripts": { "dev": "next dev" } }"#, to: repo.appendingPathComponent("package.json"))
        let d = RepoScanner.discover(repo: repo)
        #expect(d.services.map(\.id) == ["api/dev"])
        #expect(d.warnings.count == 1)
        #expect(d.warnings.first?.contains("launch.json") == true)
    }

    @Test func missingRepoYieldsEmptyDiscovery() {
        let d = RepoScanner.discover(repo: URL(fileURLWithPath: "/nope/gone"))
        #expect(d.services.isEmpty)
        #expect(d.warnings.isEmpty)
    }

    @Test func goLaunchJsonSuppressesGoMod() throws {
        let repo = try makeRepo("api", [
            ".vscode/launch.json": #"{ "configurations": [ { "name": "Run", "type": "go", "request": "launch", "program": "${workspaceFolder}/cmd/api" } ] }"#,
            "go.mod": "module api\n",
            "cmd/api/main.go": "package main\n",
        ])
        let d = RepoScanner.discover(repo: repo)
        #expect(d.services.map(\.source) == [.launchJson("Run")])
    }

    @Test func goModUsedWhenLaunchJsonHasOnlyGoTests() throws {
        let repo = try makeRepo("api", [
            ".vscode/launch.json": #"{ "configurations": [ { "name": "T", "type": "go", "request": "launch", "mode": "test", "program": "${fileDirname}" } ] }"#,
            "go.mod": "module api\n",
            "cmd/api/main.go": "package main\n",
        ])
        let d = RepoScanner.discover(repo: repo)
        #expect(d.services.map(\.definition.command) == [["go", "run", "./cmd/api"]])
        #expect(d.services.map(\.source) == [.manifest("go:cmd/api")])
        #expect(d.skipped.map(\.name) == ["T"])
    }

    @Test func nodeLaunchDuplicateOfPackageJsonDropped() throws {
        let repo = try makeRepo("wiki-web", [
            ".vscode/launch.json": #"{ "configurations": [ { "name": "Frontend (Next.js)", "type": "node", "request": "launch", "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"], "env": { "NODE_ENV": "development" } } ] }"#,
            "package.json": #"{ "scripts": { "dev": "next dev" } }"#,
        ])
        let d = RepoScanner.discover(repo: repo)
        #expect(d.services.map(\.source) == [.packageJson("dev")])
        #expect(d.skipped == [SkippedConfig(name: "Frontend (Next.js)", reason: "package.json 'dev' ile aynı")])
    }

    @Test func preLaunchTaskWarningSurfaces() throws {
        let repo = try makeRepo("api", [
            ".vscode/launch.json": #"{ "configurations": [ { "name": "Run", "type": "go", "request": "launch", "program": "${workspaceFolder}", "preLaunchTask": "gen" } ] }"#,
        ])
        #expect(RepoScanner.discover(repo: repo).warnings == ["launch.json yapılandırması: preLaunchTask 'gen' çalıştırılmıyor"])
    }
}
