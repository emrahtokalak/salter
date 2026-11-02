import Foundation
import Testing
@testable import SalterCore

@Suite struct OverrideEditorTests {
    func service(port: String) -> ServiceConfig {
        ServiceConfig(
            id: "r/api",
            source: .launchJson("api"),
            discovered: ServiceDefinition(
                name: "api", command: ["py", "-m", "uvicorn", "a:app", "--port", port], cwd: "/r",
                envFile: "/r/.env", supportsReload: true, reloadEnabled: false, reloadArgs: ["--reload"],
                portHint: Int(port)
            )
        )
    }

    @Test func onlyFieldsTheUserChangedBecomeOverrides() {
        let atLoad = service(port: "8010")
        let baseline = OverrideEditor.fields(of: atLoad)
        var edited = baseline
        edited.reloadEnabled = true
        let rescanned = service(port: "8011")
        let overrides = OverrideEditor.apply(edited: edited, baseline: baseline, to: rescanned)
        #expect(overrides.reloadEnabled == true)
        #expect(overrides.command == nil)
        #expect(overrides.portHint == nil)
        #expect(overrides.name == nil)
    }

    @Test func editsEqualToDiscoveredClearTheOverride() {
        var svc = service(port: "8010")
        svc.overrides.name = "Benim API"
        svc.overrides.env = ["A": "1"]
        let baseline = OverrideEditor.fields(of: svc)
        #expect(baseline.name == "Benim API")
        #expect(baseline.extraEnv == ["A": "1"])
        var edited = baseline
        edited.name = "api"
        edited.extraEnv = [:]
        edited.command = ["py", "x"]
        let overrides = OverrideEditor.apply(edited: edited, baseline: baseline, to: svc)
        #expect(overrides.name == nil)
        #expect(overrides.env == nil)
        #expect(overrides.command == ["py", "x"])
    }

    @Test func untouchedExistingOverridesAreKept() {
        var svc = service(port: "8010")
        svc.overrides.cwd = "/elsewhere"
        let baseline = OverrideEditor.fields(of: svc)
        var edited = baseline
        edited.envFile = ""
        let overrides = OverrideEditor.apply(edited: edited, baseline: baseline, to: svc)
        #expect(overrides.cwd == "/elsewhere")
        #expect(overrides.envFile == "")
    }
}
