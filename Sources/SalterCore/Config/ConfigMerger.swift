import Foundation

public struct MergeOutcome: Equatable, Sendable {
    public var repo: RepoConfig
    /// Discovered services that are not in the repo and were not declined.
    public var suggestions: [DiscoveredService]
    /// Every discovered service that is not in the repo, declined ones included.
    public var unmatched: [DiscoveredService]
}

public enum ConfigMerger {
    /// Refreshes discovered definitions (user overrides win), flags services whose source vanished,
    /// and reports discovered services that are not configured yet.
    public static func merge(_ discovery: RepoDiscovery, into repo: RepoConfig) -> MergeOutcome {
        var repo = repo
        var matched = Set<ServiceSource>()
        for i in repo.services.indices where repo.services[i].source.kind != .manual {
            if let found = discovery.services.first(where: { $0.source == repo.services[i].source }) {
                repo.services[i].discovered = found.definition
                repo.services[i].sourceMissing = false
                matched.insert(found.source)
            } else {
                repo.services[i].sourceMissing = true
            }
        }
        let declined = Set(repo.declinedSources)
        let unmatched = discovery.services.filter { !matched.contains($0.source) }
        let suggestions = unmatched.filter { !declined.contains($0.source) }
        return MergeOutcome(repo: repo, suggestions: suggestions, unmatched: unmatched)
    }

    /// Adds `selected` to the repo and records the rest of `offered` as declined.
    public static func accept(
        _ selected: [DiscoveredService],
        offered: [DiscoveredService],
        into repo: RepoConfig,
        takenIDs: Set<String>
    ) -> RepoConfig {
        var repo = repo
        var taken = takenIDs.union(repo.services.map(\.id))
        for service in selected where !repo.services.contains(where: { $0.source == service.source }) {
            let id = Slug.unique(service.id, taken: taken)
            taken.insert(id)
            repo.services.append(ServiceConfig(id: id, source: service.source, discovered: service.definition))
        }
        let selectedSources = Set(selected.map(\.source))
        repo.declinedSources.removeAll { selectedSources.contains($0) }
        let present = Set(repo.services.map(\.source))
        for service in offered
        where !present.contains(service.source) && !repo.declinedSources.contains(service.source) {
            repo.declinedSources.append(service.source)
        }
        return repo
    }
}
