import Foundation
import Testing
@testable import SalterCore

@Suite struct ConfigMergerTests {
    func discovered(_ name: String, port: Int? = nil) -> DiscoveredService {
        DiscoveredService(
            id: "repo/\(Slug.make(name))",
            source: .launchJson(name),
            definition: ServiceDefinition(name: name, command: ["run", name], cwd: "/repo", portHint: port)
        )
    }

    func discovery(_ services: [DiscoveredService]) -> RepoDiscovery {
        RepoDiscovery(repoPath: "/repo", services: services, skipped: [], warnings: [])
    }

    @Test func updatesDiscoveredButKeepsOverrides() {
        var existing = ServiceConfig(id: "repo/api", source: .launchJson("api"), discovered: discovered("api", port: 1).definition)
        existing.overrides.portHint = 9999
        let outcome = ConfigMerger.merge(discovery([discovered("api", port: 2)]), into: RepoConfig(path: "/repo", services: [existing]))
        let merged = outcome.repo.services[0]
        #expect(merged.discovered.portHint == 2)
        #expect(merged.overrides.portHint == 9999)
        #expect(merged.effective.portHint == 9999)
        #expect(!merged.sourceMissing)
        #expect(outcome.suggestions.isEmpty)
        #expect(outcome.unmatched.isEmpty)
    }

    @Test func marksMissingAndSuggestsNew() {
        let old = ServiceConfig(id: "repo/old", source: .launchJson("old"), discovered: discovered("old").definition)
        let manual = ServiceConfig(id: "repo/mvn", source: .manual, discovered: ServiceDefinition(name: "mvn", command: ["mvn"], cwd: "/repo"))
        let repo = RepoConfig(path: "/repo", services: [old, manual], declinedSources: [.launchJson("declined")])
        let outcome = ConfigMerger.merge(discovery([discovered("new"), discovered("declined")]), into: repo)
        #expect(outcome.repo.services.count == 2)
        #expect(outcome.repo.services[0].sourceMissing)
        #expect(!outcome.repo.services[1].sourceMissing)
        #expect(outcome.suggestions.map(\.definition.name) == ["new"])
        #expect(outcome.unmatched.map(\.definition.name) == ["new", "declined"])
    }

    @Test func deletedRepoFolderMarksEverythingMissingWithoutDeleting() {
        var service = ServiceConfig(id: "repo/api", source: .launchJson("api"), discovered: discovered("api").definition)
        service.overrides.name = "Benim API"
        let outcome = ConfigMerger.merge(discovery([]), into: RepoConfig(path: "/repo", services: [service]))
        #expect(outcome.repo.services.count == 1)
        #expect(outcome.repo.services[0].sourceMissing)
        #expect(outcome.repo.services[0].effective.name == "Benim API")
    }

    @Test func acceptAssignsUniqueIDsAndRecordsDeclined() {
        let offered = [discovered("api"), discovered("worker"), discovered("tests")]
        let repo = ConfigMerger.accept([offered[0], offered[1]], offered: offered, into: RepoConfig(path: "/repo"), takenIDs: ["repo/api"])
        #expect(repo.services.map(\.id) == ["repo/api-2", "repo/worker"])
        #expect(repo.declinedSources == [.launchJson("tests")])

        let again = ConfigMerger.accept([], offered: offered, into: repo, takenIDs: Set(repo.services.map(\.id)))
        #expect(again.declinedSources == [.launchJson("tests")])

        let reAccepted = ConfigMerger.accept([offered[2]], offered: [offered[2]], into: again, takenIDs: Set(again.services.map(\.id)))
        #expect(reAccepted.services.count == 3)
        #expect(reAccepted.declinedSources.isEmpty)
    }
}
