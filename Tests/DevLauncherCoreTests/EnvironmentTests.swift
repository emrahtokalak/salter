import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct DotEnvParserTests {
    @Test func parsesCommonFormats() {
        let text = "# comment\r\nA=1\r\nexport B = two \nC=\"quoted # not comment\"\nD='single'\nE=value # inline\nF=\"line\\nbreak\"\n=bad\nnoequals\nG=\n"
        let env = DotEnvParser.parse(text)
        #expect(env == [
            "A": "1", "B": "two", "C": "quoted # not comment", "D": "single",
            "E": "value", "F": "line\nbreak", "G": "",
        ])
    }
}

@Suite struct EnvResolverTests {
    let definition = ServiceDefinition(
        name: "api", command: ["py"], cwd: "/r", envFile: "/r/.env",
        env: ["FROM_CONFIG": "c", "SHARED": "config"]
    )

    @Test func layersInOrder() {
        let shell = ["PATH": "/bin", "SHARED": "shell", "FROM_SHELL": "s", "PYTHONUNBUFFERED": "0"]
        let r = EnvResolver.resolve(shell: shell, definition: definition) { path in
            path == "/r/.env" ? "SHARED=file\nFROM_FILE=f\nFROM_CONFIG=file" : nil
        }
        #expect(r.warnings.isEmpty)
        #expect(r.environment["PATH"] == "/bin")
        #expect(r.environment["FROM_SHELL"] == "s")
        #expect(r.environment["FROM_FILE"] == "f")
        #expect(r.environment["FROM_CONFIG"] == "c")
        #expect(r.environment["SHARED"] == "config")
        #expect(r.environment["PYTHONUNBUFFERED"] == "1")
        #expect(r.environment["FORCE_COLOR"] == "1")
    }

    @Test func missingEnvFileWarnsButContinues() {
        let r = EnvResolver.resolve(shell: [:], definition: definition) { _ in nil }
        #expect(r.warnings == ["Env dosyası bulunamadı: /r/.env"])
        #expect(r.environment["FROM_CONFIG"] == "c")
    }

    @Test func noEnvFileMeansNoRead() {
        var d = definition
        d.envFile = nil
        let r = EnvResolver.resolve(shell: [:], definition: d) { _ in
            Issue.record("env file should not be read")
            return nil
        }
        #expect(r.warnings.isEmpty)
    }
}

@Suite struct ShellEnvironmentTests {
    @Test func parsesMarkedNulSeparatedOutput() {
        var data = Data("motd noise\n".utf8)
        data.append(Data(ShellEnvironment.beginMarker.utf8))
        data.append(Data("PATH=/a:/b\0MULTI=x\ny\0=skip\0EMPTY=\0".utf8))
        data.append(Data(ShellEnvironment.endMarker.utf8))
        #expect(ShellEnvironment.parse(data) == ["PATH": "/a:/b", "MULTI": "x\ny", "EMPTY": ""])
    }

    @Test func parseFailsWithoutMarkers() {
        #expect(ShellEnvironment.parse(Data("PATH=/x".utf8)) == nil)
    }

    @Test func capturesRealLoginShell() {
        let env = ShellEnvironment.capture()
        #expect(env.error == nil)
        #expect(env.variables["PATH"]?.contains("/usr/bin") == true)
        #expect(env.variables["HOME"] == NSHomeDirectory())
    }

    @Test func fallsBackWhenShellMissing() {
        let env = ShellEnvironment.capture(shell: "/nonexistent/zsh", timeout: 1)
        #expect(env.error != nil)
        #expect(env.variables["PATH"] == ShellEnvironment.fallbackPath)
    }
}
