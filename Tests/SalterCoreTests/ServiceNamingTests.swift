import Foundation
import Testing
@testable import SalterCore

@Suite struct ServiceNamingTests {
    func svc(_ id: String, _ name: String, kind: ServiceSource.Kind = .launchJson, alias: String? = nil) -> ServiceConfig {
        var config = ServiceConfig(
            id: id,
            source: ServiceSource(kind: kind, name: kind == .manual ? nil : name),
            discovered: ServiceDefinition(name: name, command: ["x"], cwd: "/")
        )
        config.overrides.name = alias
        return config
    }

    func repo(_ path: String, _ services: [ServiceConfig]) -> RepoConfig {
        RepoConfig(path: path, services: services)
    }

    func names(_ repos: [RepoConfig]) -> DisplayNames {
        DisplayNames(config: AppConfig(repos: repos))
    }

    @Test func cleanStripsEmojiDebugRunAndSeparators() {
        #expect(ServiceNaming.clean("🚀 Debug FastAPI") == "FastAPI")
        #expect(ServiceNaming.clean("Debug BFF") == "BFF")
        #expect(ServiceNaming.clean("API: uvicorn (debug)") == "API: uvicorn")
        #expect(ServiceNaming.clean("Run") == "")
        #expect(ServiceNaming.clean("Python: Debug Tests") == "Python: Tests")
        #expect(ServiceNaming.clean("Debug: Main") == "Main")
        #expect(ServiceNaming.clean("Runner") == "Runner")
        #expect(ServiceNaming.clean("  Order  Worker ") == "Order Worker")
    }

    @Test func labelFallsBackWhenCleanIsEmpty() {
        #expect(ServiceNaming.label("Debug API") == "API")
        #expect(ServiceNaming.label("Run") == "launch.json yapılandırması")
    }

    @Test func singleServiceRepoUsesRepoName() {
        let path = "/p/acme/classifier-go"
        let n = names([repo(path, [svc("a", "Run")])])
        #expect(n.services["a"] == ServiceName(full: "classifier-go", inGroup: "classifier-go"))
        #expect(n.repos[path] == "classifier-go")
    }

    @Test func multiServiceRepoAddsCleanedSuffix() {
        let n = names([repo("/p/storefront", [svc("a", "Debug BFF"), svc("b", "🚀 Debug Order Worker")])])
        #expect(n.services["a"] == ServiceName(full: "storefront · BFF", inGroup: "BFF"))
        #expect(n.services["b"] == ServiceName(full: "storefront · Order Worker", inGroup: "Order Worker"))
    }

    @Test func emptySuffixUsesPosition() {
        let n = names([repo("/p/r", [svc("a", "Run"), svc("b", "Debug")])])
        #expect(n.services["a"]?.full == "r · 1")
        #expect(n.services["b"]?.full == "r · 2")
    }

    @Test func duplicateSuffixGetsNumbered() {
        let n = names([repo("/p/r", [svc("a", "Debug FastAPI"), svc("b", "Run FastAPI")])])
        #expect(n.services["a"]?.inGroup == "FastAPI")
        #expect(n.services["b"]?.inGroup == "FastAPI 2")
    }

    @Test func aliasWins() {
        let n = names([repo("/p/r", [svc("a", "Debug A", alias: "Intent"), svc("b", "B")])])
        #expect(n.services["a"] == ServiceName(full: "Intent", inGroup: "Intent"))
    }

    @Test func blankAliasIsIgnored() {
        let n = names([repo("/p/r", [svc("a", "Run", alias: "  ")])])
        #expect(n.services["a"]?.full == "r")
    }

    @Test func manualNameIsUsedAsIs() {
        let n = names([repo("/p/r", [svc("a", "legacy-ear Run", kind: .manual), svc("b", "B")])])
        #expect(n.services["a"]?.full == "legacy-ear Run")
    }

    @Test func crossRepoCollisionAddsParentFolder() {
        let n = names([
            repo("/p/acme/api", [svc("a", "Run")]),
            repo("/p/personal/api", [svc("b", "Run")]),
        ])
        #expect(n.services["a"]?.full == "api (acme)")
        #expect(n.services["b"]?.full == "api (personal)")
        #expect(n.repos["/p/acme/api"] == "api (acme)")
        #expect(n.repos["/p/personal/api"] == "api (personal)")
    }

    @Test func aliasCollidingWithOtherRepoAddsParentFolder() {
        let n = names([
            repo("/p/x/foo", [svc("a", "Run", alias: "api")]),
            repo("/p/y/api", [svc("b", "Run")]),
        ])
        #expect(n.services["a"]?.full == "api (x)")
        #expect(n.services["b"]?.full == "api (y)")
    }

    @Test func breadcrumbUsesRootFolderName() {
        #expect(ServiceNaming.breadcrumb(repoPath: "/u/Projects/acme/x", roots: ["/u/Projects/acme"]) == "acme / x")
        #expect(ServiceNaming.breadcrumb(repoPath: "/u/other/y", roots: ["/u/Projects/acme"]) == "other / y")
    }

    @Test func discoveredNamesFollowSameRules() {
        func d(_ id: String, _ name: String) -> DiscoveredService {
            DiscoveredService(id: id, source: .launchJson(name), definition: ServiceDefinition(name: name, command: ["x"], cwd: "/"))
        }
        #expect(ServiceNaming.discoveredNames([d("a", "Run")], repoName: "svc") == ["a": "svc"])
        #expect(ServiceNaming.discoveredNames([d("a", "Debug BFF"), d("b", "🚀 Debug Worker")], repoName: "svc") == ["a": "BFF", "b": "Worker"])
    }

    @Test func cleanDropsKeycapsTextPresentationAndTagEmoji() {
        #expect(ServiceNaming.clean("☕︎ Run") == "")
        #expect(ServiceNaming.clean("🏴󠁧󠁢󠁥󠁮󠁧󠁿 Run") == "")
        #expect(ServiceNaming.clean("1️⃣ API") == "API")
        #expect(ServiceNaming.clean("#️⃣ Debug") == "")
    }

    @Test func cleanStripsDebuggerAndInnerSeparators() {
        #expect(ServiceNaming.clean("Python Debugger: FastAPI") == "Python: FastAPI")
        #expect(ServiceNaming.clean("Debugging API") == "API")
        #expect(ServiceNaming.clean("Python: Debug: Tests") == "Python: Tests")
    }

    @Test func symbolOnlySuffixFallsBackToPosition() {
        let n = names([repo("/p/r", [svc("a", "☕︎ Run"), svc("b", "1️⃣ Debug")])])
        #expect(n.services["a"]?.inGroup == "1")
        #expect(n.services["b"]?.inGroup == "2")
    }

    @Test func namesInsideOneRepoNeverRepeat() {
        let n = names([repo("/p/r", [
            svc("a", "BFF", kind: .launchJson, alias: "BFF"),
            svc("b", "Debug BFF"),
            svc("c", "legacy-ear", kind: .manual),
            svc("d", "legacy-ear", kind: .manual),
        ])])
        #expect(n.services["a"]?.inGroup == "BFF")
        #expect(n.services["b"]?.inGroup == "BFF 2")
        #expect(n.services["c"]?.inGroup == "legacy-ear")
        #expect(n.services["d"]?.inGroup == "legacy-ear 2")
    }
}
