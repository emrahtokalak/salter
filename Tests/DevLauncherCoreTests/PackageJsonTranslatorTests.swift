import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct PackageJsonTranslatorTests {
    func translate(_ repo: String, lockFiles: Set<String>) throws -> TranslationResult {
        try PackageJsonTranslator.translate(Fixtures.data("\(repo)/package.json"), repo: URL(fileURLWithPath: "/w/\(repo)")) { path in
            lockFiles.contains(URL(fileURLWithPath: path).lastPathComponent)
        }
    }

    @Test func viteSpaUsesNpmAndDefaultVitePort() throws {
        let r = try translate("admin-web", lockFiles: ["package-lock.json"])
        let s = try #require(r.services.first)
        #expect(s.id == "admin-web/dev")
        #expect(s.source == .packageJson("dev"))
        #expect(s.definition.command == ["npm", "run", "dev"])
        #expect(s.definition.cwd == "/w/admin-web")
        #expect(s.definition.portHint == 5173)
        #expect(s.definition.envFile == nil)
        #expect(!s.definition.supportsReload)
    }

    @Test func nextAppWithExplicitPortPrefersNpmLock() throws {
        let r = try translate("wiki-web", lockFiles: ["package-lock.json", "yarn.lock"])
        #expect(r.services.first?.definition.command == ["npm", "run", "dev"])
        #expect(r.services.first?.definition.portHint == 3000)
    }

    @Test func plainNextDevDefaultsTo3000() throws {
        let r = try translate("flow-composer", lockFiles: [])
        #expect(r.services.first?.definition.portHint == 3000)
    }

    @Test func lockFilePriority() {
        let repo = URL(fileURLWithPath: "/w/r")
        func pm(_ files: Set<String>) -> PackageManager {
            PackageJsonTranslator.packageManager(repo: repo) { files.contains(URL(fileURLWithPath: $0).lastPathComponent) }
        }
        #expect(pm(["yarn.lock", "pnpm-lock.yaml"]) == .pnpm)
        #expect(pm(["yarn.lock"]) == .yarn)
        #expect(pm([]) == .npm)
    }

    @Test func fallsBackToStartScriptAndReadsPortFlags() throws {
        let start = #"{ "scripts": { "start": "vite --port 4000" } }"#
        let r = try PackageJsonTranslator.translate(Data(start.utf8), repo: URL(fileURLWithPath: "/w/r")) { _ in false }
        #expect(r.services.first?.definition.command == ["npm", "run", "start"])
        #expect(r.services.first?.definition.portHint == 4000)
        let none = #"{ "scripts": { "build": "tsc" } }"#
        #expect(try PackageJsonTranslator.translate(Data(none.utf8), repo: URL(fileURLWithPath: "/w/r")) { _ in false }.services.isEmpty)
    }
}
