import Darwin
import Foundation

/// A child started by `ProcessRunner`. It keeps itself alive until it has exited and its output is drained.
public final class SpawnedProcess: @unchecked Sendable {
    public let pid: pid_t
    public let startTime: UInt64
    public var pgid: pid_t { pid }

    private let queue = DispatchQueue(label: "salter.process")
    private var exitSource: DispatchSourceProcess?
    private var handles: [FileHandle] = []
    private var exited = false

    init(pid: pid_t, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }

    /// A partial line (e.g. a prompt) is shown once output has paused this long.
    static let idleFlushDelay: TimeInterval = 0.5

    /// Line splitting shared by the reader and the idle-flush timer; lines are delivered under the lock to keep order.
    final class LineBufferBox: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = LineBuffer()
        private var token = 0

        /// Delivers complete lines; returns a token when a partial line is left waiting.
        func append(_ data: Data, deliver: ([String]) -> Void) -> Int? {
            lock.lock()
            defer { lock.unlock() }
            let lines = buffer.append(data)
            if !lines.isEmpty { deliver(lines) }
            token += 1
            return buffer.hasPending ? token : nil
        }

        /// Delivers the partial line if no output arrived since `expected`.
        func flushIfIdle(token expected: Int, deliver: ([String]) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard expected == token, let rest = buffer.flush() else { return }
            deliver([rest])
        }

        func finish(deliver: ([String]) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            if let rest = buffer.flush() { deliver([rest]) }
        }
    }

    func attachReader(fd: Int32, kind: OutputKind, onLines: @escaping ProcessRunner.LinesHandler) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let box = LineBufferBox()
        handle.readabilityHandler = { [self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                box.finish { onLines(kind, $0) }
                self.queue.async { self.handles.removeAll { $0 === h } }
                return
            }
            if let token = box.append(data, deliver: { onLines(kind, $0) }) {
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.idleFlushDelay) {
                    box.flushIfIdle(token: token) { onLines(kind, $0) }
                }
            }
        }
        queue.sync { handles.append(handle) }
    }

    func watchExit(onExit: @escaping ProcessRunner.ExitHandler) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler { [self] in self.reap(onExit) }
        exitSource = source
        source.resume()
        // The child may have exited before the source was registered.
        queue.async { [self] in self.reap(onExit) }
    }

    /// Runs on `queue`.
    private func reap(_ onExit: ProcessRunner.ExitHandler) {
        guard !exited else { return }
        var status: Int32 = 0
        guard waitpid(pid, &status, WNOHANG) == pid else { return }
        exited = true
        exitSource?.cancel()
        exitSource = nil
        onExit(ExitStatus(waitStatus: status))
    }
}

public enum ProcessRunner {
    public typealias LinesHandler = @Sendable (OutputKind, [String]) -> Void
    public typealias ExitHandler = @Sendable (ExitStatus) -> Void

    /// Resolves a bare command name against `searchPath`; names containing "/" must exist as given.
    public static func resolveExecutable(_ name: String, searchPath: String?) -> String? {
        let fm = FileManager.default
        if name.contains("/") { return fm.isExecutableFile(atPath: name) ? name : nil }
        for dir in (searchPath ?? "").split(separator: ":") where !dir.isEmpty {
            let candidate = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Starts the request in a new process group whose id equals the child pid.
    public static func spawn(
        _ request: SpawnRequest,
        onLines: @escaping LinesHandler,
        onExit: @escaping ExitHandler
    ) throws -> SpawnedProcess {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProcessRunnerError.directoryNotFound(request.cwd)
        }
        guard FileManager.default.isExecutableFile(atPath: request.executable) else {
            throw ProcessRunnerError.executableNotFound(request.executable)
        }

        var outPipe: [Int32] = [0, 0]
        var errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else { throw ProcessRunnerError.spawnFailed(errno) }
        guard pipe(&errPipe) == 0 else {
            let code = errno
            close(outPipe[0]); close(outPipe[1])
            throw ProcessRunnerError.spawnFailed(code)
        }
        for fd in outPipe + errPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        posix_spawn_file_actions_addchdir_np(&actions, request.cwd)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaultSignals: sigset_t = 0
        for signal in [SIGPIPE, SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGCHLD, SIGUSR1, SIGUSR2] {
            defaultSignals |= sigset_t(1) << sigset_t(signal - 1)
        }
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        var noSignals: sigset_t = 0
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))

        let argv: [UnsafeMutablePointer<CChar>?] = ([request.executable] + request.arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = request.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, request.executable, &actions, &attributes, argv, envp)
        close(outPipe[1])
        close(errPipe[1])
        guard rc == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            throw ProcessRunnerError.spawnFailed(rc)
        }

        let process = SpawnedProcess(pid: pid, startTime: ProcessInspector.startTime(of: pid) ?? 0)
        process.attachReader(fd: outPipe[0], kind: .stdout, onLines: onLines)
        process.attachReader(fd: errPipe[0], kind: .stderr, onLines: onLines)
        process.watchExit(onExit: onExit)
        return process
    }

    /// SIGTERM to the whole group, then SIGKILL after `grace` seconds. Returns true if SIGKILL was needed.
    @discardableResult
    public static func terminateGroup(_ pgid: pid_t, grace: TimeInterval = 5) async -> Bool {
        guard pgid > 1 else { return false }
        kill(-pgid, SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if !ProcessInspector.isGroupAlive(pgid) { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard ProcessInspector.isGroupAlive(pgid) else { return false }
        kill(-pgid, SIGKILL)
        return true
    }
}
