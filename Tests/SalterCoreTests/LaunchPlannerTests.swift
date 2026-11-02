import Foundation
import Testing
@testable import SalterCore

@Suite struct LaunchPlannerTests {
    let python = ServiceDefinition(
        name: "api", command: ["/repo/.venv/bin/python", "-m", "uvicorn", "a:app"], cwd: "/repo/src",
        supportsReload: true, reloadEnabled: true, reloadArgs: ["--reload"]
    )

    @Test func detectsMissingVirtualEnvironment() {
        let requirement = LaunchPlanner.setupRequirement(for: python, searchPath: "/bin") { _ in false }
        #expect(requirement == .pythonEnvironment(project: "/repo"))
        #expect(requirement?.fix?.command == ["uv", "sync"])
        #expect(requirement?.fix?.directory == "/repo")
        #expect(LaunchPlanner.setupRequirement(for: python, searchPath: "/bin") { _ in true } == nil)
    }

    @Test func detectsMissingNodeModulesAndPackageManager() throws {
        let bin = try makeFakeExecutable("npm")
        let web = ServiceDefinition(name: "dev", command: ["npm", "run", "dev"], cwd: "/web")
        let requirement = LaunchPlanner.setupRequirement(for: web, searchPath: bin.path) { _ in false }
        #expect(requirement == .packageInstall(.npm, directory: "/web"))
        #expect(requirement?.fix?.command == ["npm", "install"])
        #expect(LaunchPlanner.setupRequirement(for: web, searchPath: bin.path) { $0 == "/web/node_modules" } == nil)
        #expect(LaunchPlanner.setupRequirement(for: web, searchPath: "/nonexistent") { _ in true } == .missingExecutable("npm"))
    }

    @Test func otherMissingAbsoluteExecutable() {
        let tool = ServiceDefinition(name: "x", command: ["/opt/tool/bin/run"], cwd: "/")
        let requirement = LaunchPlanner.setupRequirement(for: tool, searchPath: nil) { _ in false }
        #expect(requirement == .missingExecutable("/opt/tool/bin/run"))
        #expect(requirement?.fix == nil)
    }

    @Test func planResolvesCommandEnvAndReload() throws {
        let definition = ServiceDefinition(
            name: "echo", command: ["sh", "-c", "echo hi"], cwd: "/tmp", envFile: "/tmp/none.env",
            env: ["X": "1"], supportsReload: true, reloadEnabled: true, reloadArgs: ["--reload"]
        )
        let plan = try LaunchPlanner.plan(definition, shell: ["PATH": "/bin"]) { _ in nil }
        #expect(plan.request.executable == "/bin/sh")
        #expect(plan.request.arguments == ["-c", "echo hi", "--reload"])
        #expect(plan.request.cwd == "/tmp")
        #expect(plan.request.environment["X"] == "1")
        #expect(plan.request.environment["PYTHONUNBUFFERED"] == "1")
        #expect(plan.warnings == ["Env dosyası bulunamadı: /tmp/none.env"])
    }

    @Test func planFailsForUnknownExecutable() {
        let definition = ServiceDefinition(name: "x", command: ["no-such-tool-xyz"], cwd: "/tmp")
        #expect(throws: ProcessRunnerError.executableNotFound("no-such-tool-xyz")) {
            try LaunchPlanner.plan(definition, shell: ["PATH": "/bin"])
        }
    }

    @Test func setupRequestRunsFixInItsDirectory() throws {
        let bin = try makeFakeExecutable("uv")
        let request = try LaunchPlanner.setupRequest(.pythonEnvironment(project: "/repo"), shell: ["PATH": bin.path])
        #expect(request?.executable == bin.appendingPathComponent("uv").path)
        #expect(request?.arguments == ["sync"])
        #expect(request?.cwd == "/repo")
        #expect(request?.environment["FORCE_COLOR"] == "1")
        #expect(try LaunchPlanner.setupRequest(.missingExecutable("x"), shell: [:]) == nil)
    }
}
