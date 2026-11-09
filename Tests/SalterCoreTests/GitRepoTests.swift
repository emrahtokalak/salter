import Foundation
import Testing
@testable import SalterCore

/// A bare "remote" plus a working clone in a temp dir; no network, no user git config.
struct TempRemote {
    let base: URL
    let remote: String
    let work: String
    let other: String
    let env: [String: String]

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("salter-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        remote = base.appendingPathComponent("remote.git").path
        work = base.appendingPathComponent("work").path
        other = base.appendingPathComponent("other").path
        var env = GitRunner.environment(shell: ProcessInfo.processInfo.environment)
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_AUTHOR_NAME"] = "t"
        env["GIT_AUTHOR_EMAIL"] = "t@example.com"
        env["GIT_COMMITTER_NAME"] = "t"
        env["GIT_COMMITTER_EMAIL"] = "t@example.com"
        self.env = env
        try sh(["init", "--bare", "-b", "main", remote], in: base.path)
        try sh(["clone", remote, work], in: base.path)
        try commit(file: "a.txt", content: "1\n", in: work)
        try sh(["push", "-u", "origin", "main"], in: work)
        try sh(["clone", remote, other], in: base.path)
    }

    @discardableResult
    func sh(_ args: [String], in dir: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad, userInfo: ["args": args]) }
        return text
    }

    func write(_ file: String, _ content: String, in dir: String) throws {
        try content.write(toFile: "\(dir)/\(file)", atomically: true, encoding: .utf8)
    }

    func commit(file: String, content: String, in dir: String) throws {
        try write(file, content, in: dir)
        try sh(["add", file], in: dir)
        try sh(["commit", "-m", "edit \(file)"], in: dir)
    }

    /// Commits `count` changes to `file` in the other clone and pushes them.
    func pushFromOther(file: String = "a.txt", count: Int = 1, branch: String = "main") throws {
        if branch != "main" { try sh(["switch", "-c", branch], in: other) }
        for i in 0..<count { try commit(file: file, content: "other \(i)\n", in: other) }
        try sh(["push", "origin", branch], in: other)
    }

    func repo() async throws -> GitRepo {
        try #require(await GitRepo.open(work, environment: env))
    }

    func head(_ dir: String) throws -> String {
        try sh(["rev-parse", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Suite struct GitRepoTests {
    @Test func openReturnsNilForPlainDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("salter-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var env = GitRunner.environment(shell: ProcessInfo.processInfo.environment)
        env["GIT_CEILING_DIRECTORIES"] = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        #expect(await GitRepo.open(dir.path, environment: env) == nil)
    }

    @Test func openFindsToplevelFromSubfolder() async throws {
        let t = try TempRemote()
        try FileManager.default.createDirectory(atPath: t.work + "/sub/dir", withIntermediateDirectories: true)
        let repo = try #require(await GitRepo.open(t.work + "/sub/dir", environment: t.env))
        #expect(URL(fileURLWithPath: repo.root).resolvingSymlinksInPath() == URL(fileURLWithPath: t.work).resolvingSymlinksInPath())
    }

    @Test func pullFastForwards() async throws {
        let t = try TempRemote()
        try t.pushFromOther(count: 2)
        let repo = try await t.repo()
        #expect(await repo.pull() == .pulled(newCommits: 2))
        #expect(await repo.pull() == .upToDate)
    }

    @Test func pullBlockedByOverlappingLocalChange() async throws {
        let t = try TempRemote()
        try t.pushFromOther(file: "a.txt")
        try t.write("a.txt", "mine\n", in: t.work)
        let before = try t.head(t.work)
        let repo = try await t.repo()
        #expect(await repo.pull() == .failed(.localChanges(["a.txt"])))
        #expect(try t.head(t.work) == before)
        #expect(try String(contentsOfFile: t.work + "/a.txt", encoding: .utf8) == "mine\n")
    }

    @Test func pullAllowedWithNonOverlappingChange() async throws {
        let t = try TempRemote()
        try t.commit(file: "b.txt", content: "b\n", in: t.other)
        try t.sh(["push", "origin", "main"], in: t.other)
        try t.write("a.txt", "mine\n", in: t.work)
        let repo = try await t.repo()
        #expect(await repo.pull() == .pulled(newCommits: 1))
    }

    @Test func pullDivergedFailsWithoutMerge() async throws {
        let t = try TempRemote()
        try t.pushFromOther(file: "b.txt")
        try t.commit(file: "c.txt", content: "c\n", in: t.work)
        let before = try t.head(t.work)
        let repo = try await t.repo()
        #expect(await repo.pull() == .failed(.diverged))
        #expect(try t.head(t.work) == before)
    }

    @Test func pullWithoutUpstream() async throws {
        let t = try TempRemote()
        try t.sh(["switch", "-c", "local-only"], in: t.work)
        let repo = try await t.repo()
        #expect(await repo.pull() == .failed(.noUpstream))
    }

    @Test func pullWithAutoStashConfigStillRefusesOverlap() async throws {
        let t = try TempRemote()
        try t.sh(["config", "merge.autoStash", "true"], in: t.work)
        try t.pushFromOther(file: "a.txt")
        try t.write("a.txt", "mine\n", in: t.work)
        let before = try t.head(t.work)
        let repo = try await t.repo()
        #expect(await repo.pull() == .failed(.localChanges(["a.txt"])))
        #expect(try t.head(t.work) == before)
        #expect(try t.sh(["stash", "list"], in: t.work).isEmpty)
    }

    @Test func pullWithDeletedUpstreamReportsNoUpstream() async throws {
        let t = try TempRemote()
        try t.pushFromOther(file: "f.txt", branch: "feature/gone")
        let repo = try await t.repo()
        _ = await repo.fetch()
        _ = await repo.switchTo(.remote(RemoteBranch(remote: "origin", name: "feature/gone")))
        try t.sh(["push", "origin", "--delete", "feature/gone"], in: t.other)
        _ = await repo.fetch()
        let status = try #require(await repo.status())
        #expect(status.upstreamGone)
        #expect(await repo.pull() == .failed(.noUpstream))
    }

    @Test func switchBlockedByTrackedChange() async throws {
        let t = try TempRemote()
        try t.sh(["branch", "other-branch"], in: t.work)
        try t.write("a.txt", "dirty\n", in: t.work)
        let repo = try await t.repo()
        #expect(await repo.switchTo(.local("other-branch")) == .blocked(changedFiles: ["a.txt"]))
    }

    @Test func switchNotBlockedByUntracked() async throws {
        let t = try TempRemote()
        try t.sh(["branch", "other-branch"], in: t.work)
        try t.write("scratch.txt", "x\n", in: t.work)
        let repo = try await t.repo()
        #expect(await repo.switchTo(.local("other-branch")) == .switched("other-branch"))
        #expect(await repo.status()?.branch == "other-branch")
    }

    @Test func switchToRemoteOnlyCreatesTracking() async throws {
        let t = try TempRemote()
        try t.pushFromOther(file: "f.txt", branch: "feature/x")
        let repo = try await t.repo()
        #expect(await repo.fetch().succeeded)
        let target = RemoteBranch(remote: "origin", name: "feature/x")
        #expect(await repo.branches().remoteOnly.contains(target))
        #expect(await repo.switchTo(.remote(target)) == .switched("feature/x"))
        #expect(await repo.status()?.upstream == "origin/feature/x")
    }

    @Test func branchesReportOtherWorktrees() async throws {
        let t = try TempRemote()
        let wt = t.base.appendingPathComponent("wt").path
        try t.sh(["worktree", "add", "-b", "feature/wt", wt], in: t.work)
        let repo = try await t.repo()
        let branches = await repo.branches()
        #expect(branches.local.contains("feature/wt"))
        let path = try #require(branches.worktree(of: "feature/wt"))
        #expect(URL(fileURLWithPath: path).resolvingSymlinksInPath() == URL(fileURLWithPath: wt).resolvingSymlinksInPath())
        // The current worktree's own branch is not reported as "elsewhere".
        #expect(branches.worktree(of: "main") == nil)
        // Seen from the other worktree, it is the other way round.
        let other = try #require(await GitRepo.open(wt, environment: t.env))
        let fromOther = await other.branches()
        #expect(fromOther.worktree(of: "main") != nil)
        #expect(fromOther.worktree(of: "feature/wt") == nil)
    }

    @Test func deletedWorktreeFolderIsStillReported() async throws {
        // Why the app checks the folder exists before opening it: git lists it until `git worktree prune`.
        let t = try TempRemote()
        let wt = t.base.appendingPathComponent("gone").path
        try t.sh(["worktree", "add", "-b", "feature/gone", wt], in: t.work)
        try FileManager.default.removeItem(atPath: wt)
        let repo = try await t.repo()
        #expect(await repo.branches().worktree(of: "feature/gone") != nil)
    }

    @Test func fetchFromMissingRemoteFailsFast() async throws {
        let t = try TempRemote()
        try t.sh(["remote", "set-url", "origin", "/nonexistent-salter-remote"], in: t.work)
        let repo = try await t.repo()
        let start = Date()
        let result = await repo.fetch()
        #expect(!result.succeeded)
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(GitFailure.classify(stderr: result.stderr, timedOut: result.timedOut) == .network(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    @Test func cancelledRunKillsProcess() async throws {
        let t = try TempRemote()
        let task = Task { await GitRunner.run(["-c", "alias.slow=!sleep 30", "slow"], in: t.work, environment: t.env, timeout: nil) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let start = Date()
        task.cancel()
        let result = await task.value
        #expect(!result.succeeded)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func timeoutKillsProcess() async throws {
        let t = try TempRemote()
        let result = await GitRunner.run(["-c", "alias.slow=!sleep 30", "slow"], in: t.work, environment: t.env, timeout: 0.3)
        #expect(result.timedOut)
        #expect(!result.succeeded)
    }

    @Test func environmentDisablesPrompts() {
        let env = GitRunner.environment(shell: ["PATH": "/usr/bin", "GIT_ASKPASS": "x", "SSH_ASKPASS": "y"])
        #expect(env["GIT_TERMINAL_PROMPT"] == "0")
        #expect(env["GIT_ASKPASS"] == nil)
        #expect(env["SSH_ASKPASS"] == nil)
        #expect(env["GIT_SSH_COMMAND"] == "ssh -o BatchMode=yes")
        #expect(env["LC_ALL"] == "C")
        #expect(env["GIT_OPTIONAL_LOCKS"] == "0")
        #expect(env["PATH"] == "/usr/bin")
        let kept = GitRunner.environment(shell: ["GIT_SSH_COMMAND": "ssh -i k"])
        #expect(kept["GIT_SSH_COMMAND"] == "ssh -i k")
    }
}
