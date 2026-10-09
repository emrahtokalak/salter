import Foundation
import Testing
@testable import DevLauncherCore

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
          { "name": "Node", "type": "node", "request": "launch", "program": "a.js" },
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
}
