import Foundation
import Testing
@testable import SalterCore

@Suite(.serialized) struct PortProbeTests {
    @Test func parsesLsofFieldOutput() {
        let output = "p100\ng100\ncpython3.11\nf5\nn127.0.0.1:8010\nf6\nn[::1]:8010\np200\ng150\ncnode\nf20\nn*:5173\n"
        let sockets = PortProbe.parse(output)
        #expect(sockets == [
            ListeningSocket(pid: 100, pgid: 100, command: "python3.11", port: 8010),
            ListeningSocket(pid: 200, pgid: 150, command: "node", port: 5173),
        ])
        #expect(PortProbe.ports(forGroup: 150, in: sockets) == [5173])
        #expect(PortProbe.owners(ofPort: 8010, in: sockets).map(\.pid) == [100])
        #expect(PortProbe.ports(forGroup: 999, in: sockets).isEmpty)
    }

    @Test func findsPortOfRealServerByProcessGroup() async throws {
        let c = OutputCollector()
        let request = SpawnRequest(
            executable: "/bin/sh",
            arguments: ["-c", "exec python3 -u -m http.server 0 --bind 127.0.0.1"],
            environment: ["PATH": ShellEnvironment.fallbackPath],
            cwd: "/tmp"
        )
        let process = try ProcessRunner.spawn(request, onLines: { c.add($0, $1) }, onExit: { c.finish($0) })
        defer { Task { await ProcessRunner.terminateGroup(process.pgid, grace: 1) } }

        var printed: Int?
        #expect(await waitUntil(timeout: 10) {
            printed = c.lines.lazy.compactMap { line -> Int? in
                guard let r = line.1.range(of: #"port (\d+)"#, options: .regularExpression) else { return nil }
                return Int(line.1[r].dropFirst("port ".count))
            }.first
            return printed != nil
        })
        var ports: [Int] = []
        #expect(await waitUntil(timeout: 10) {
            ports = PortProbe.ports(forGroup: process.pgid, in: PortProbe.snapshot())
            return !ports.isEmpty
        })
        #expect(ports == [try #require(printed)])
    }
}
