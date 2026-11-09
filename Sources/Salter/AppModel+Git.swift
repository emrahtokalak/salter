import Foundation
import SalterCore

extension AppModel {
    func repoPath(of id: String) -> String? { config.repo(containing: id)?.path }

    func gitTree(_ id: String) -> GitModel.Tree? {
        repoPath(of: id).flatMap { git.tree(forRepo: $0) }
    }

    /// Re-reads local git state; with `fetchMaxAge`, also fetches in the background if the last fetch is older.
    func gitRefresh(_ id: String, fetchMaxAge: TimeInterval?) {
        guard let path = repoPath(of: id), let shell = shell?.variables else { return }
        Task {
            await git.refresh(repoPath: path, shell: shell)
            if let fetchMaxAge { await git.backgroundFetch(repoPath: path, shell: shell, maxAge: fetchMaxAge) }
        }
    }

    func gitPull(_ id: String) {
        runGit(id) { await $0.pull() }
    }

    func gitSwitch(_ id: String, to target: BranchTarget) {
        runGit(id) { await $0.switchTo(target) }
    }

    /// Opens a branch's other worktree; git keeps listing a deleted worktree folder until `git worktree prune`.
    func gitOpenWorktree(_ id: String, path: String, reveal: Bool = false) {
        guard FileManager.default.fileExists(atPath: path) else {
            if let repo = repoPath(of: id) {
                git.showError(repoPath: repo, "Worktree klasörü bulunamadı: \((path as NSString).abbreviatingWithTildeInPath). Silinmişse `git worktree prune` ile temizleyebilirsin.")
            }
            return
        }
        if reveal { integration.reveal(path) } else { integration.openInEditor(path) }
    }

    private func runGit(_ id: String, _ action: @escaping @Sendable (GitRepo) async -> GitOutcome) {
        guard let path = repoPath(of: id), let shell = shell?.variables else { return }
        Task {
            guard let outcome = await git.perform(repoPath: path, shell: shell, action) else { return }
            codeChanged(outcome, repoPath: path)
        }
    }

    /// Logs the change in every service of the working tree and offers to restart the running ones.
    private func codeChanged(_ outcome: GitOutcome, repoPath: String) {
        let line: String
        switch outcome {
        case .pulled(let count): line = "git pull: \(count) yeni commit"
        case .switched(let name): line = "branch: \(name)"
        default: return
        }
        let root = git.root(forRepo: repoPath)
        let ids = config.repos
            .filter { $0.path == repoPath || (root != nil && git.root(forRepo: $0.path) == root) }
            .flatMap { $0.services.map(\.id) }
        for id in ids { supervisors[id]?.appendSystem([line]) }
        let active = ids.filter { status($0).isActive }
        guard !active.isEmpty else { return }
        let restart = Alerts.confirm(
            "\(repoTitle(repoPath)) güncellendi. Çalışan \(active.count) servis yeniden başlatılsın mı?",
            active.map(displayName).joined(separator: ", "),
            confirm: "Yeniden başlat",
            cancel: "Sonra"
        )
        if restart { active.forEach(self.restart) }
    }
}
