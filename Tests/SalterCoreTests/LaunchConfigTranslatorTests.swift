import Foundation
import Testing
@testable import SalterCore

@Suite struct LaunchConfigTranslatorTests {
    func translate(_ repo: String) throws -> TranslationResult {
        let configs = try LaunchJsonParser.parse(Fixtures.data("\(repo)/launch.json"))
        return LaunchConfigTranslator.translate(configs, repo: URL(fileURLWithPath: "/w/\(repo)"))
    }

    @Test func aihubBffUvicornWithReload() throws {
        let r = try translate("gateway-api")
        #expect(r.skipped.isEmpty)
        #expect(r.services.count == 1)
        let s = try #require(r.services.first)
        #expect(s.id == "gateway-api/python-debugger-fastapi")
        #expect(s.source == .launchJson("Python Debugger: FastAPI"))
        let d = s.definition
        #expect(d.command == ["/w/gateway-api/.venv/bin/python", "-m", "uvicorn", "app.app:app", "--host", "0.0.0.0", "--port", "8002"])
        #expect(d.cwd == "/w/gateway-api")
        #expect(d.envFile == "/w/gateway-api/.env")
        #expect(d.env == ["PYTHONPATH": "/w/gateway-api/src/python"])
        #expect(d.supportsReload)
        #expect(d.reloadEnabled)
        #expect(d.reloadArgs == ["--reload"])
        #expect(d.portHint == 8002)
    }

    @Test func docsApiMergesReloadVariantAndSkipsTests() throws {
        let r = try translate("docs-api")
        #expect(r.services.count == 1)
        let d = try #require(r.services.first).definition
        #expect(d.name == "API: uvicorn (debug)")
        #expect(d.command == ["/w/docs-api/.venv/bin/python", "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8010"])
        #expect(d.reloadEnabled)
        #expect(d.reloadArgs == ["--reload", "--reload-dir", "src"])
        #expect(d.env == ["PYTHONPATH": "/w/docs-api/src"])
        #expect(Set(r.skipped.map(\.name)) == ["Tests: all", "Tests: current file", "Tests: debug-test (Testing panel)"])
    }

    @Test func flowApiIdenticalProgramConfigsMergeIntoOne() throws {
        let r = try translate("flow-api")
        #expect(r.services.count == 1)
        let s = try #require(r.services.first)
        #expect(s.id == "flow-api/debug-fastapi")
        #expect(s.definition.name == "🚀 Debug FastAPI")
        #expect(s.definition.command == ["/w/flow-api/.venv/bin/python", "/w/flow-api/src/app/main.py"])
        #expect(!s.definition.supportsReload)
        #expect(s.definition.portHint == nil)
    }

    @Test func mediaPipelineKeepsAllWorkers() throws {
        let r = try translate("media-pipeline")
        #expect(r.services.count == 11)
        #expect(r.skipped.isEmpty)
        #expect(Set(r.services.map(\.id)).count == 11)
        let transcode = try #require(r.services.first { $0.definition.name == "Temporal: Process Transcode Worker" })
        #expect(transcode.definition.command == ["/w/media-pipeline/.venv/bin/python", "-m", "workflows.process_transcode.launcher"])
        #expect(transcode.definition.env["TEMPORAL_TASK_QUEUE"] == "process-transcode-task-queue")
        let post = try #require(r.services.first { $0.definition.name == "Temporal: Post-Transcode Orchestrator Worker" })
        #expect(Array(post.definition.command.suffix(3)) == ["main_standard", "--worker", "post-transcode-orchestrator"])
    }

    @Test func analyticsFlowUsesExplicitEnvFileAndPython() throws {
        let r = try translate("analytics-worker")
        #expect(r.services.count == 1)
        #expect(r.skipped.map(\.name) == ["Pytest: All Tests"])
        let d = try #require(r.services.first).definition
        #expect(d.envFile == "/w/analytics-worker/.env")
        #expect(d.command == ["/w/analytics-worker/.venv/bin/python", "-m", "main"])
    }

    @Test func storefrontPreservesReloadDirAndCwd() throws {
        let r = try translate("storefront")
        #expect(r.services.map(\.definition.name) == ["Debug BFF", "Debug Order Worker"])
        let bff = r.services[0].definition
        #expect(bff.cwd == "/w/storefront/src")
        #expect(bff.command == ["/w/storefront/.venv/bin/python", "-m", "uvicorn", "adapters.incoming.bff.app:app", "--host", "0.0.0.0", "--port", "8080"])
        #expect(bff.reloadEnabled)
        #expect(bff.reloadArgs == ["--reload", "--reload-dir", "/w/storefront/src"])
        #expect(bff.portHint == 8080)
        let worker = r.services[1].definition
        #expect(worker.command == ["/w/storefront/.venv/bin/python", "/w/storefront/src/main.py", "--adapter", "order-worker"])
        #expect(worker.env["TEMPORAL_DEBUG"] == "true")
        #expect(worker.env["CONFIGURATION_FILE_PATH"] == "/w/storefront/configuration/app-config.yaml")
    }

    @Test func unsupportedVariablesAndTypesAreSkipped() throws {
        let json = """
        { "configurations": [
          { "name": "Input", "type": "debugpy", "request": "launch", "module": "x", "args": ["${input:port}"] },
          { "name": "Attach", "type": "debugpy", "request": "attach" },
          { "name": "Node", "type": "chrome", "request": "launch", "url": "http://localhost" },
          { "name": "Nothing", "type": "debugpy", "request": "launch" },
          { "name": "PortEnv", "type": "python", "request": "launch", "module": "worker", "env": { "PORT": "9001" } }
        ] }
        """
        let configs = try LaunchJsonParser.parse(Data(json.utf8))
        let r = LaunchConfigTranslator.translate(configs, repo: URL(fileURLWithPath: "/w/x"))
        #expect(r.services.map(\.definition.name) == ["PortEnv"])
        #expect(r.services.first?.definition.portHint == 9001)
        #expect(r.skipped.map(\.name) == ["Input", "Attach", "Node", "Nothing"])
        #expect(r.skipped.first?.reason.contains("${input:port}") == true)
    }

    @Test func reloadFlagVariantsAreSeparated() {
        let split = LaunchConfigTranslator.splitReloadArgs(
            ["app:app", "--reload", "--reload-dir", "src", "--reload-include=*.yaml", "--port", "1"]
        )
        #expect(split.args == ["app:app", "--port", "1"])
        #expect(split.extras == ["--reload-dir", "src", "--reload-include=*.yaml"])
        #expect(split.hadReload)
    }

    func translateJSON(_ json: String, repo: String = "/w/x") throws -> TranslationResult {
        LaunchConfigTranslator.translate(try LaunchJsonParser.parse(Data(json.utf8)), repo: URL(fileURLWithPath: repo))
    }

    @Test func intentClassifierGoRunAndDebugMerge() throws {
        let r = try translate("classifier-go")
        #expect(r.services.count == 1)
        let s = try #require(r.services.first)
        #expect(s.id == "classifier-go/run")
        #expect(s.source == .launchJson("Run"))
        #expect(s.definition.command == ["go", "run", "./cmd/classifier"])
        #expect(s.definition.cwd == "/w/classifier-go")
        #expect(s.definition.envFile == "/w/classifier-go/.env")
        #expect(!s.definition.supportsReload)
        #expect(r.skipped.map(\.name) == ["Debug Tests (current package)"])
        #expect(r.ecosystems == [.go])
        #expect(r.warnings.isEmpty)
    }

    @Test func goExecModeBuildFlagsAndPreLaunchTask() throws {
        let r = try translateJSON("""
        { "configurations": [
          { "name": "Bin", "type": "go", "request": "launch", "mode": "exec",
            "program": "${workspaceFolder}/bin/api", "args": ["-port", "9000"] },
          { "name": "A", "type": "go", "request": "launch", "mode": "debug", "buildFlags": "-tags dev",
            "program": "${workspaceFolder}", "preLaunchTask": "gen" }
        ] }
        """)
        #expect(r.services.map(\.definition.command) == [["/w/x/bin/api", "-port", "9000"], ["go", "run", "-tags", "dev", "."]])
        #expect(r.services.first?.definition.portHint == 9000)
        #expect(r.warnings == ["A: preLaunchTask 'gen' çalıştırılmıyor"])
    }

    @Test func goProgramRelativeToCwdWithSpaces() throws {
        let r = try translateJSON("""
        { "configurations": [
          { "name": "In", "type": "go", "request": "launch", "cwd": "${workspaceFolder}/svc",
            "program": "${workspaceFolder}/svc/cmd/a" },
          { "name": "Out", "type": "go", "request": "launch", "cwd": "${workspaceFolder}/svc",
            "program": "${workspaceFolder}/tools/gen" },
          { "name": "NoProgram", "type": "go", "request": "launch" }
        ] }
        """, repo: "/w/my repo")
        #expect(r.services.map(\.definition.command) == [["go", "run", "./cmd/a"], ["go", "run", "/w/my repo/tools/gen"]])
        #expect(r.services.first?.definition.cwd == "/w/my repo/svc")
        #expect(r.skipped == [SkippedConfig(name: "NoProgram", reason: "program tanımlı değil")])
    }

    @Test func nodeRuntimeExecutable() throws {
        let r = try translateJSON("""
        { "configurations": [ { "name": "Web", "type": "node", "request": "launch",
          "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"] } ] }
        """)
        #expect(r.services.map(\.definition.command) == [["npm", "run", "dev"]])
        #expect(r.ecosystems == [.node])
    }

    @Test func nodeProgram() throws {
        let r = try translateJSON("""
        { "configurations": [ { "name": "Srv", "type": "pwa-node", "request": "launch",
          "program": "${workspaceFolder}/server.js", "args": ["--port", "4000"] } ] }
        """)
        let d = try #require(r.services.first).definition
        #expect(d.command == ["node", "/w/x/server.js", "--port", "4000"])
        #expect(d.portHint == 4000)
    }

    @Test func nodeTypeScriptWithoutRuntimeSkipped() throws {
        let r = try translateJSON("""
        { "configurations": [ { "name": "TS", "type": "node", "request": "launch", "program": "${workspaceFolder}/src/main.ts" },
          { "name": "Empty", "type": "node", "request": "launch" } ] }
        """)
        #expect(r.services.isEmpty)
        #expect(r.skipped == [
            SkippedConfig(name: "TS", reason: "TypeScript programı için runtimeExecutable gerekli"),
            SkippedConfig(name: "Empty", reason: "program tanımlı değil"),
        ])
    }

    @Test func rustCargoBlock() throws {
        let r = try translateJSON("""
        { "configurations": [
          { "name": "Srv", "type": "lldb", "request": "launch",
            "cargo": { "args": ["build", "--bin=srv", "--package=api"] }, "args": ["-v"] },
          { "name": "Plain", "type": "lldb", "request": "launch", "cargo": { "args": ["build"] } }
        ] }
        """)
        #expect(r.services.map(\.definition.command) == [
            ["cargo", "run", "--bin=srv", "--package=api", "--", "-v"],
            ["cargo", "run"],
        ])
        #expect(r.ecosystems == [.rust])
    }

    @Test func rustWithoutCargoSkipped() throws {
        let r = try translateJSON("""
        { "configurations": [ { "name": "Bin", "type": "lldb", "request": "launch", "program": "${workspaceFolder}/target/debug/srv" } ] }
        """)
        #expect(r.skipped == [SkippedConfig(name: "Bin", reason: "cargo bloğu yok; Cargo.toml kullanılıyor")])
    }

    @Test func rustCargoTestSkipped() throws {
        let r = try translateJSON("""
        { "configurations": [ { "name": "T", "type": "lldb", "request": "launch", "cargo": { "args": ["test", "--no-run"] } } ] }
        """)
        #expect(r.skipped == [SkippedConfig(name: "T", reason: "test konfigürasyonu")])
    }

    @Test func javaAndCoreclrSkipped() throws {
        let r = try translateJSON("""
        { "configurations": [
          { "name": "J", "type": "java", "request": "launch", "mainClass": "a.App" },
          { "name": "C", "type": "coreclr", "request": "launch", "program": "${workspaceFolder}/bin/Debug/net8.0/Api.dll" }
        ] }
        """)
        #expect(r.services.isEmpty)
        #expect(r.ecosystems.isEmpty)
        #expect(r.skipped == [
            SkippedConfig(name: "J", reason: "proje dosyasından çalıştırılıyor"),
            SkippedConfig(name: "C", reason: "proje dosyasından çalıştırılıyor"),
        ])
    }
}
