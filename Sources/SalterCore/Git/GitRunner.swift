import Foundation

public struct GitResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

/// Runs the `git` CLI without ever prompting, with an optional timeout; Task cancellation kills it.
public enum GitRunner {
    public static func environment(shell: [String: String]) -> [String: String] {
        var env = shell
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = nil
        env["SSH_ASKPASS"] = nil
        if env["GIT_SSH_COMMAND"]?.isEmpty ?? true { env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes" }
        env["LC_ALL"] = "C"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        return env
    }

    public static func run(
        _ args: [String],
        in cwd: String,
        environment: [String: String],
        timeout: TimeInterval?
    ) async -> GitResult {
        let executable = ProcessRunner.resolveExecutable("git", searchPath: environment["PATH"]) ?? "/usr/bin/git"
        let request = SpawnRequest(
            executable: executable,
            arguments: ["-c", "core.quotePath=false"] + args,
            environment: environment,
            cwd: cwd
        )
        let run = Collector()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                run.begin(continuation)
                do {
                    let process = try ProcessRunner.spawn(
                        request,
                        onLines: { kind, lines in run.add(kind, lines) },
                        onExit: { run.exited($0) },
                        onOutputClosed: { run.outputClosed() }
                    )
                    run.attach(process)
                    if let timeout {
                        Task.detached {
                            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                            run.timeOut()
                        }
                    }
                } catch {
                    run.failToStart("\(error)")
                }
            }
        } onCancel: {
            run.cancel()
        }
    }

    /// Thread-safe accumulator that resumes once the process exited and all output was read.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<GitResult, Never>?
        private var process: SpawnedProcess?
        private var stdout: [String] = []
        private var stderr: [String] = []
        private var exit: ExitStatus?
        private var closed = false
        private var timedOut = false
        private var cancelled = false
        private var finished = false

        func begin(_ continuation: CheckedContinuation<GitResult, Never>) {
            locked { self.continuation = continuation }
        }

        func attach(_ process: SpawnedProcess) {
            let killNow = locked { () -> Bool in
                self.process = process
                return cancelled
            }
            if killNow { kill(process.pgid) }
        }

        func add(_ kind: OutputKind, _ lines: [String]) {
            locked {
                if kind == .stderr { stderr += lines } else { stdout += lines }
            }
        }

        func exited(_ status: ExitStatus) {
            locked { exit = status }
            finishIfDone()
        }

        func outputClosed() {
            locked { closed = true }
            finishIfDone()
        }

        func timeOut() {
            let target = locked { () -> SpawnedProcess? in
                guard !finished else { return nil }
                timedOut = true
                return process
            }
            if let target { kill(target.pgid) }
        }

        func cancel() {
            let target = locked { () -> SpawnedProcess? in
                cancelled = true
                return finished ? nil : process
            }
            if let target { kill(target.pgid) }
        }

        func failToStart(_ message: String) {
            resume(GitResult(exitCode: 127, stdout: "", stderr: message, timedOut: false))
        }

        private func finishIfDone() {
            let result = locked { () -> GitResult? in
                guard let exit, closed else { return nil }
                return GitResult(
                    exitCode: cancelled ? 130 : exit.code,
                    stdout: stdout.joined(separator: "\n"),
                    stderr: stderr.joined(separator: "\n"),
                    timedOut: timedOut
                )
            }
            if let result { resume(result) }
        }

        private func resume(_ result: GitResult) {
            let continuation = locked { () -> CheckedContinuation<GitResult, Never>? in
                guard !finished else { return nil }
                finished = true
                defer { self.continuation = nil }
                return self.continuation
            }
            continuation?.resume(returning: result)
        }

        private func kill(_ pgid: pid_t) {
            Task.detached { await ProcessRunner.terminateGroup(pgid, grace: 1) }
        }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }
    }
}
