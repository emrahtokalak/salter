import Foundation
import Testing
@testable import SalterCore

/// Writes `files` (relative path → contents) into a fresh repo directory named `name`.
func makeRepo(_ name: String, _ files: [String: String]) throws -> URL {
    let repo = try makeTempDirectory().appendingPathComponent(name)
    for (path, text) in files {
        let url = repo.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    return repo
}

@Suite struct GoDetectorTests {
    @Test func detectsCmdBinaries() throws {
        let repo = try makeRepo("svc", [
            "go.mod": "module svc\n",
            "cmd/worker/main.go": "package main\n",
            "cmd/api/main.go": "// Command api.\npackage main\n",
            "cmd/api/main_test.go": "package main\n",
        ])
        let r = GoDetector.detect(repo: repo)
        #expect(r.services.map(\.definition.command) == [["go", "run", "./cmd/api"], ["go", "run", "./cmd/worker"]])
        #expect(r.services.map(\.source) == [.manifest("go:cmd/api"), .manifest("go:cmd/worker")])
        #expect(r.services.map(\.id) == ["svc/api", "svc/worker"])
        let d = try #require(r.services.first).definition
        #expect(d.name == "api")
        #expect(d.cwd == repo.path)
        #expect(d.envFile == repo.appendingPathComponent(".env").path)
        #expect(!d.supportsReload)
    }

    @Test func detectsRootMain() throws {
        let repo = try makeRepo("tool", ["go.mod": "module tool\n", "main.go": "//go:build !js\n\npackage main\n"])
        let r = GoDetector.detect(repo: repo)
        #expect(r.services.map(\.definition.command) == [["go", "run", "."]])
        #expect(r.services.first?.source == .manifest("go:."))
        #expect(r.services.first?.definition.name == "tool")
    }

    @Test func ignoresNonMainAndTestOnlyDirs() throws {
        let repo = try makeRepo("lib", [
            "go.mod": "module lib\n",
            "cmd/lib/lib.go": "package lib\n",
            "cmd/x/x_test.go": "package main\n",
            "lib.go": "package lib\n",
        ])
        #expect(GoDetector.detect(repo: repo).services.isEmpty)
    }

    @Test func requiresGoMod() throws {
        let repo = try makeRepo("nomod", ["main.go": "package main\n"])
        #expect(GoDetector.detect(repo: repo).services.isEmpty)
    }

    @Test func detectionIsDeterministic() throws {
        let files = Dictionary(uniqueKeysWithValues: (1...8).map { ("cmd/s\($0)/main.go", "package main\n") })
        let repo = try makeRepo("many", files.merging(["go.mod": "module many\n"]) { a, _ in a })
        #expect(GoDetector.detect(repo: repo) == GoDetector.detect(repo: repo))
        #expect(GoDetector.detect(repo: repo).services.count == 8)
    }

    @Test func packageClauseSkipsBuildTagsAndComments() {
        #expect(GoDetector.packageClause("//go:build linux\n\n/* doc\n package nope */\n// x\npackage main // c\n") == "main")
        #expect(GoDetector.packageClause("package   api\n") == "api")
        #expect(GoDetector.packageClause("") == nil)
    }

    @Test func crlfSourcesAreDetected() throws {
        let repo = try makeRepo("win", ["go.mod": "module win\r\n", "cmd/api/main.go": "// api\r\npackage main\r\n"])
        #expect(GoDetector.detect(repo: repo).services.map(\.definition.command) == [["go", "run", "./cmd/api"]])
    }

    @Test func buildIgnoreGeneratorIsNotAMainPackage() throws {
        let repo = try makeRepo("lib", [
            "go.mod": "module lib\n",
            "lib.go": "package lib\n",
            "gen.go": "//go:build ignore\n\npackage main\n",
            "cmd/tool/gen.go": "// +build ignore\n\npackage main\n",
        ])
        #expect(GoDetector.detect(repo: repo).services.isEmpty)
    }
}
