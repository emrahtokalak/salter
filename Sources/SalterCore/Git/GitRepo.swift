import Foundation

public enum BranchTarget: Equatable, Sendable {
    case local(String)
    case remote(RemoteBranch)
}

public enum GitOutcome: Equatable, Sendable {
    case switched(String)
    case pulled(newCommits: Int)
    case upToDate
    /// Branch switch refused up front because tracked files have changes.
    case blocked(changedFiles: [String])
    case failed(GitFailure)
}

/// A git working tree and the actions the detail screen offers on it.
public struct GitRepo: Equatable, Sendable {
    public static let fetchTimeout: TimeInterval = 60

    /// `git rev-parse --show-toplevel`.
    public let root: String
    public let environment: [String: String]

    /// nil when `path` is not inside a git working tree (or git is unavailable).
    public static func open(_ path: String, environment: [String: String]) async -> GitRepo? {
        let result = await GitRunner.run(["rev-parse", "--show-toplevel"], in: path, environment: environment, timeout: 10)
        let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, !root.isEmpty else { return nil }
        return GitRepo(root: root, environment: environment)
    }

    public func status() async -> GitStatus? {
        let result = await git(["status", "--porcelain=v2", "--branch"])
        return result.succeeded ? GitStatus.parse(porcelainV2: result.stdout) : nil
    }

    public func branches() async -> GitBranchList {
        let result = await git(["for-each-ref", "--format=%(refname)%09%(worktreepath)", "refs/heads", "refs/remotes"])
        return result.succeeded ? GitBranchList.parse(refs: result.stdout, currentWorktree: root) : GitBranchList()
    }

    public func fetch(timeout: TimeInterval = GitRepo.fetchTimeout) async -> GitResult {
        await git(["fetch", "--prune"], timeout: timeout)
    }

    public func switchTo(_ target: BranchTarget) async -> GitOutcome {
        if let changed = await status()?.changedFiles, !changed.isEmpty {
            return .blocked(changedFiles: changed)
        }
        let name: String
        let result: GitResult
        switch target {
        case .local(let branch):
            name = branch
            result = await git(["switch", branch])
        case .remote(let remote):
            name = remote.name
            result = await git(["switch", "-c", remote.name, "--track", "\(remote.remote)/\(remote.name)"])
        }
        return result.succeeded ? .switched(name) : .failed(Self.failure(result))
    }

    /// `git pull --ff-only` as a timed fetch plus an untimed local fast-forward, so a timeout
    /// can never interrupt the working-tree update.
    public func pull() async -> GitOutcome {
        guard let status = await status(), status.upstream != nil, !status.upstreamGone else { return .failed(.noUpstream) }
        let old = await git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetched = await fetch()
        guard fetched.succeeded else { return .failed(Self.failure(fetched)) }
        // fetch --prune may just have removed the upstream branch.
        if await self.status()?.upstreamGone == true { return .failed(.noUpstream) }
        // --no-autostash: a configured merge.autoStash would re-apply local changes and could leave conflicts.
        let merged = await git(["merge", "--ff-only", "--no-autostash", "@{u}"])
        guard merged.succeeded else { return .failed(Self.failure(merged)) }
        let count = await git(["rev-list", "--count", "\(old)..HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let commits = Int(count) ?? 0
        return commits == 0 ? .upToDate : .pulled(newCommits: commits)
    }

    private func git(_ args: [String], timeout: TimeInterval? = nil) async -> GitResult {
        await GitRunner.run(args, in: root, environment: environment, timeout: timeout)
    }

    private static func failure(_ result: GitResult) -> GitFailure {
        GitFailure.classify(stderr: result.stderr.isEmpty ? result.stdout : result.stderr, timedOut: result.timedOut)
    }
}
