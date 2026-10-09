import Darwin
import Foundation
import Testing
@testable import DevLauncherCore

final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [(OutputKind, String)] = []
    private var status: ExitStatus?

    func add(_ kind: OutputKind, _ lines: [String]) {
        lock.lock()
        collected += lines.map { (kind, $0) }
        lock.unlock()
    }

    func finish(_ exit: ExitStatus) {
        lock.lock()
        status = exit
        lock.unlock()
    }

    var lines: [(OutputKind, String)] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    var exit: ExitStatus? {
        lock.lock()
        defer { lock.unlock() }
        return status
    }
}

@Suite(.serialized) struct ProcessRunnerTests {
    func sh(_ script: String, _ extra: [String] = []) -> SpawnRequest {
        SpawnRequest(executable: "/bin/sh", arguments: ["-c", script] + extra, environment: ["PATH": "/usr/bin:/bin"], cwd: "/tmp")
    }

    func spawn(_ request: SpawnRequest, into collector: OutputCollector) throws -> SpawnedProcess {
        try ProcessRunner.spawn(request, onLines: { collector.add($0, $1) }, onExit: { collector.finish($0) })
    }

    @Test func capturesOutputAndExitCode() async throws {
        let c = OutputCollector()
        _ = try spawn(sh("echo hello; echo oops 1>&2; printf partial; exit 3"), into: c)
        #expect(await waitUntil { c.exit != nil && c.lines.count == 3 })
        #expect(c.exit == .exited(3))
        #expect(c.lines.filter { $0.0 == .stdout }.map(\.1) == ["hello", "partial"])
        #expect(c.lines.contains { $0.0 == .stderr && $0.1 == "oops" })
    }

    @Test func passesEnvironmentAndWorkingDirectory() async throws {
        let c = OutputCollector()
        var request = sh("echo $DL_TEST; pwd")
        request.environment["DL_TEST"] = "merhaba"
        request.cwd = "/usr"
        _ = try spawn(request, into: c)
        #expect(await waitUntil { c.exit != nil && c.lines.count == 2 })
        #expect(c.lines.map(\.1) == ["merhaba", "/usr"])
    }

    @Test func handlesPathsWithSpacesAndTurkishCharacters() async throws {
        let dir = try makeTempDirectory().appendingPathComponent("çalışma klasörü")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let c = OutputCollector()
        var request = sh(#"pwd; echo "$0""#, ["ağ değer"])
        request.cwd = dir.path
        _ = try spawn(request, into: c)
        #expect(await waitUntil { c.exit != nil && c.lines.count == 2 })
        #expect(c.lines.first?.1.hasSuffix("çalışma klasörü") == true)
        #expect(c.lines.last?.1 == "ağ değer")
    }

    @Test func terminateGroupKillsChildren() async throws {
        let c = OutputCollector()
        let process = try spawn(sh("sleep 100 & sleep 100 & wait"), into: c)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(ProcessInspector.isGroupAlive(process.pgid))
        let killed = await ProcessRunner.terminateGroup(process.pgid, grace: 3)
        #expect(!killed)
        #expect(await waitUntil { !ProcessInspector.isGroupAlive(process.pgid) })
        #expect(await waitUntil { c.exit != nil })
    }

    @Test func escalatesToSigkill() async throws {
        let c = OutputCollector()
        let process = try spawn(sh("trap '' TERM; sleep 100 & wait"), into: c)
        try await Task.sleep(nanoseconds: 300_000_000)
        let killed = await ProcessRunner.terminateGroup(process.pgid, grace: 0.5)
        #expect(killed)
        #expect(await waitUntil { !ProcessInspector.isGroupAlive(process.pgid) })
        #expect(await waitUntil { c.exit == .signaled(SIGKILL) })
    }

    @Test func refusesToSignalInvalidGroups() async {
        #expect(await ProcessRunner.terminateGroup(0, grace: 0.1) == false)
        #expect(await ProcessRunner.terminateGroup(1, grace: 0.1) == false)
    }

    @Test func rejectsMissingExecutableAndDirectory() {
        #expect(throws: ProcessRunnerError.executableNotFound("/nope/bin")) {
            try ProcessRunner.spawn(SpawnRequest(executable: "/nope/bin", arguments: [], environment: [:], cwd: "/tmp"), onLines: { _, _ in }, onExit: { _ in })
        }
        #expect(throws: ProcessRunnerError.directoryNotFound("/nope/dir")) {
            try ProcessRunner.spawn(SpawnRequest(executable: "/bin/sh", arguments: [], environment: [:], cwd: "/nope/dir"), onLines: { _, _ in }, onExit: { _ in })
        }
    }

    @Test func resolvesExecutablesOnPath() {
        #expect(ProcessRunner.resolveExecutable("sh", searchPath: "/nope:/bin") == "/bin/sh")
        #expect(ProcessRunner.resolveExecutable("/bin/sh", searchPath: nil) == "/bin/sh")
        #expect(ProcessRunner.resolveExecutable("definitely-missing-xyz", searchPath: "/bin") == nil)
    }

    @Test func inspectsProcesses() {
        #expect(ProcessInspector.startTime(of: getpid()) != nil)
        #expect(ProcessInspector.startTime(of: 999_999) == nil)
        #expect(ProcessInspector.isAlive(getpid()))
        #expect(!ProcessInspector.isAlive(999_999))
    }

    @Test func decodesWaitStatus() {
        #expect(ExitStatus(waitStatus: 3 << 8) == .exited(3))
        #expect(ExitStatus(waitStatus: 9) == .signaled(9))
        #expect(ExitStatus.signaled(9).code == 137)
        #expect(ExitStatus.exited(2).code == 2)
    }
}
