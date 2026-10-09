import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct LaunchJsonParserTests {
    @Test func parsesJsoncWithTrailingCommas() throws {
        let configs = try LaunchJsonParser.parse(Fixtures.data("flow-api/launch.json"))
        #expect(configs.map(\.name) == ["🚀 Debug FastAPI", "🔧 Debug Main (CLI)"])
        #expect(configs[0].python == "${workspaceFolder}/.venv/bin/python")
        #expect(configs[0].program == "${workspaceFolder}/src/app/main.py")
        #expect(configs[0].type == "debugpy")
        #expect(configs[0].request == "launch")
    }

    @Test func collectsVariablesAndPurpose() throws {
        let configs = try LaunchJsonParser.parse(Fixtures.data("docs-api/launch.json"))
        let current = try #require(configs.first { $0.name == "Tests: current file" })
        #expect(current.variables == ["workspaceFolder", "file"])
        let debugTest = try #require(configs.first { $0.name == "Tests: debug-test (Testing panel)" })
        #expect(debugTest.purpose == ["debug-test"])
    }

    @Test func acceptsStringArgsAndNumericEnv() throws {
        let json = #"{ "configurations": [ { "name": "A", "args": "--port 8000 --name 'x y'", "env": { "N": 3 } }, { "noName": true } ] }"#
        let configs = try LaunchJsonParser.parse(Data(json.utf8))
        #expect(configs.count == 1)
        #expect(configs[0].args == ["--port", "8000", "--name", "x y"])
        #expect(configs[0].env == ["N": "3"])
    }

    @Test func missingConfigurationsYieldsEmptyList() throws {
        #expect(try LaunchJsonParser.parse(Data("{}".utf8)).isEmpty)
    }
}
