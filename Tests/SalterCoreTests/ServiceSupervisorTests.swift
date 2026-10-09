import Darwin
import Foundation
import Testing
@testable import SalterCore

@MainActor @Suite(.serialized) struct ServiceSupervisorTests {
    func plan(_ script: String) -> LaunchPlan {
        LaunchPlan(
            request: SpawnRequest(executable: "/bin/sh", arguments: ["-c", script], environment: ["PATH": "/usr/bin:/bin"], cwd: "/tmp"),
            warnings: ["örnek uyarı"]
        )
    }

    @Test func crashIsDetectedWithExitCode() async throws {
        let s = ServiceSupervisor(id: "t/crash")
        try s.start(plan("echo boom; exit 4"), expectsPort: false)
        #expect(s.status == .starting)
        #expect(await waitUntil { s.status == .crashed(.exited(4)) })
        #expect(s.logs.lines.contains { $0.text == "boom" && $0.kind == .stdout })
        #expect(s.logs.lines.contains { $0.kind == .system && $0.text.contains("örnek uyarı") })
        #expect(s.runtimeRecord == nil)
        #expect(s.pgid == nil)
        #expect(s.status.isCrashed)
    }

    @Test func stopTransitionsToStopped() async throws {
        let s = ServiceSupervisor(id: "t/stop")
        var seen: [ServiceStatus] = []
        s.onStatusChange = { seen.append($0.status) }
        try s.start(plan("sleep 100"), expectsPort: false)
        let record = try #require(s.runtimeRecord)
        #expect(record.pgid == s.pgid)
        await s.stop(grace: 2)
        #expect(await waitUntil { s.status == .stopped })
        #expect(seen == [.starting, .stopping, .stopped])
        #expect(!ProcessInspector.isGroupAlive(record.pgid))
    }

    @Test func secondStartWhileRunningIsIgnored() async throws {
        let s = ServiceSupervisor(id: "t/double")
        try s.start(plan("sleep 100"), expectsPort: false)
        let first = s.pgid
        try s.start(plan("sleep 100"), expectsPort: false)
        #expect(s.pgid == first)
        await s.stop(grace: 2)
        #expect(await waitUntil { s.status == .stopped })
    }

    @Test func workerWithoutPortBecomesRunningAfterGracePeriod() async throws {
        var clock = Date()
        let s = ServiceSupervisor(id: "t/worker", now: { clock })
        try s.start(plan("sleep 100"), expectsPort: false)
        s.refresh(with: [])
        #expect(s.status == .starting)
        clock = clock.addingTimeInterval(3.1)
        s.refresh(with: [])
        #expect(s.status == .running(ports: []))
        await s.stop(grace: 2)
    }

    @Test func serverStaysStartingUntilPortAppears() async throws {
        var clock = Date()
        let s = ServiceSupervisor(id: "t/server", now: { clock })
        try s.start(plan("sleep 100"), expectsPort: true)
        let pgid = try #require(s.pgid)
        clock = clock.addingTimeInterval(10)
        s.refresh(with: [])
        #expect(s.status == .starting)
        s.refresh(with: [ListeningSocket(pid: pgid, pgid: pgid, command: "python", port: 8010)])
        #expect(s.status == .running(ports: [8010]))
        s.refresh(with: [ListeningSocket(pid: pgid + 1, pgid: pgid, command: "python", port: 8011)])
        #expect(s.status == .running(ports: [8011]))
        await s.stop(grace: 2)
    }

    @Test func adoptedProcessCanBeStopped() async throws {
        let process = try ProcessRunner.spawn(plan("sleep 100").request, onLines: { _, _ in }, onExit: { _ in })
        let s = ServiceSupervisor(id: "t/adopt")
        s.adopt(RuntimeRecord(serviceID: "t/adopt", pid: process.pid, pgid: process.pgid, startTime: process.startTime))
        #expect(s.status == .running(ports: []))
        #expect(s.isAdopted)
        await s.stop(grace: 2)
        #expect(s.status == .stopped)
        #expect(!s.isAdopted)
        #expect(await waitUntil { !ProcessInspector.isGroupAlive(process.pgid) })
    }

    @Test func adoptedProcessExitIsNoticedOnRefresh() {
        let s = ServiceSupervisor(id: "t/adopt2")
        s.adopt(RuntimeRecord(serviceID: "t/adopt2", pid: 99_998, pgid: 99_998, startTime: 1))
        s.refresh(with: [], isSameProcess: { _ in false })
        #expect(s.status == .stopped)
        #expect(s.runtimeRecord == nil)
    }

    @Test func reusedPidIsNotSignalledOnStop() async throws {
        let process = try ProcessRunner.spawn(plan("sleep 100").request, onLines: { _, _ in }, onExit: { _ in })
        let s = ServiceSupervisor(id: "t/reused")
        s.adopt(RuntimeRecord(serviceID: "t/reused", pid: process.pid, pgid: process.pgid, startTime: process.startTime + 1))
        await s.stop(grace: 1)
        #expect(s.status == .stopped)
        #expect(ProcessInspector.isGroupAlive(process.pgid))
        await ProcessRunner.terminateGroup(process.pgid, grace: 1)
    }

    @Test func spawnFailureIsReportedAsCrash() {
        let s = ServiceSupervisor(id: "t/fail")
        var bad = plan("true")
        bad.request.cwd = "/nope/dir"
        #expect(throws: ProcessRunnerError.directoryNotFound("/nope/dir")) { try s.start(bad, expectsPort: false) }
        #expect(s.status == .crashed(.exited(127)))
        #expect(s.logs.lines.contains { $0.kind == .system && $0.text.contains("/nope/dir") })
    }

    @Test func runSetupLogsResult() async throws {
        let s = ServiceSupervisor(id: "t/setup")
        try s.runSetup(plan("echo installing").request)
        #expect(s.isRunningSetup)
        #expect(await waitUntil { !s.isRunningSetup })
        #expect(s.logs.lines.contains { $0.text == "installing" })
        #expect(s.logs.lines.contains { $0.text.contains("kurulum tamamlandı") })
        #expect(s.status == .stopped)
    }
}
