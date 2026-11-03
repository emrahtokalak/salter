import Foundation
import Observation
import SalterCore

/// Git state per working tree (`git rev-parse --show-toplevel`), shared by every service in it.
@MainActor @Observable
final class GitModel {
    struct Message: Equatable {
        var text: String
        var detail: String?
        var isError: Bool
        var id = UUID()
    }

    struct Tree {
        var repo: GitRepo
        var status: GitStatus?
        var branches: GitBranchList?
        /// Last successful fetch, shown as "son kontrol".
        var lastFetch: Date?
        var fetching = false
        var busy = false
        var message: Message?
    }

    private(set) var trees: [String: Tree] = [:]
    // Observed: views that looked up a repo before its root was known must update once it is.
    private var rootForRepo: [String: String] = [:]
    @ObservationIgnored private var lastFetchAttempt: [String: Date] = [:]
    @ObservationIgnored private var fetchTasks: [String: Task<Bool, Never>] = [:]

    static let messageLifetime: TimeInterval = 5

    func root(forRepo path: String) -> String? { rootForRepo[path] }
    func tree(forRepo path: String) -> Tree? { rootForRepo[path].flatMap { trees[$0] } }

    /// Re-reads branch, status and branch list without touching the network.
    func refresh(repoPath: String, shell: [String: String]) async {
        let environment = GitRunner.environment(shell: shell)
        if rootForRepo[repoPath] == nil {
            guard let repo = await GitRepo.open(repoPath, environment: environment) else { return }
            rootForRepo[repoPath] = repo.root
            if trees[repo.root] == nil { trees[repo.root] = Tree(repo: repo) }
        }
        guard let root = rootForRepo[repoPath], let repo = trees[root]?.repo else { return }
        async let status = repo.status()
        async let branches = repo.branches()
        let (newStatus, newBranches) = await (status, branches)
        trees[root]?.status = newStatus
        trees[root]?.branches = newBranches
    }

    /// Fetches in the background unless one ran within `maxAge`. Disables nothing; failures stay quiet.
    func backgroundFetch(repoPath: String, shell: [String: String], maxAge: TimeInterval) async {
        guard let root = rootForRepo[repoPath], let tree = trees[root], !tree.busy, !tree.fetching else { return }
        if let last = lastFetchAttempt[root], Date().timeIntervalSince(last) < maxAge { return }
        lastFetchAttempt[root] = Date()
        trees[root]?.fetching = true
        let repo = tree.repo
        let task = Task { await repo.fetch().succeeded }
        fetchTasks[root] = task
        let succeeded = await task.value
        fetchTasks[root] = nil
        trees[root]?.fetching = false
        if succeeded, !task.isCancelled { trees[root]?.lastFetch = Date() }
        await refresh(repoPath: repoPath, shell: shell)
    }

    /// Runs a user action (pull / switch). Returns nil when another action is already running in this tree.
    func perform(
        repoPath: String,
        shell: [String: String],
        _ action: @escaping @Sendable (GitRepo) async -> GitOutcome
    ) async -> GitOutcome? {
        guard let root = rootForRepo[repoPath], let tree = trees[root], !tree.busy else { return nil }
        trees[root]?.busy = true
        trees[root]?.message = nil
        if let fetch = fetchTasks[root] {
            fetch.cancel()
            _ = await fetch.value
        }
        let outcome = await action(tree.repo)
        switch outcome {
        case .pulled, .upToDate: trees[root]?.lastFetch = Date()
        default: break
        }
        await refresh(repoPath: repoPath, shell: shell)
        trees[root]?.busy = false
        show(Self.message(for: outcome), in: root)
        return outcome
    }

    func dismissMessage(repoPath: String) {
        guard let root = rootForRepo[repoPath] else { return }
        trees[root]?.message = nil
    }

    private func show(_ message: Message, in root: String) {
        trees[root]?.message = message
        guard !message.isError else { return }
        let id = message.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.messageLifetime * 1_000_000_000))
            if self?.trees[root]?.message?.id == id { self?.trees[root]?.message = nil }
        }
    }

    static func message(for outcome: GitOutcome) -> Message {
        switch outcome {
        case .switched(let name):
            return Message(text: "\(name) branch'ine geçildi", isError: false)
        case .pulled(let count):
            return Message(text: "\(count) yeni commit çekildi", isError: false)
        case .upToDate:
            return Message(text: "Zaten güncel", isError: false)
        case .blocked(let files):
            return Message(
                text: "\(files.count) dosyada kaydedilmemiş değişiklik var; önce commit'le ya da geri al.",
                detail: files.joined(separator: "\n"),
                isError: true
            )
        case .failed(let failure):
            return Message(text: failure.message, detail: failure.detail, isError: true)
        }
    }
}
