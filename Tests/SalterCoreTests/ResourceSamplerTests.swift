import Darwin
import Foundation
import Testing
@testable import SalterCore

@Suite struct ResourceSamplerTests {
    let t0 = Date(timeIntervalSince1970: 1000)

    func s(_ pid: pid_t, _ cpuSeconds: Double, _ mb: UInt64 = 10) -> ProcessSample {
        ProcessSample(pid: pid, cpuNanos: UInt64(cpuSeconds * 1e9), residentBytes: mb << 20)
    }

    @Test func firstRecordHasNoCPU() {
        var h = ResourceHistory()
        h.record([s(1, 1, 10), s(2, 1, 5)], mainPID: 1, at: t0)
        #expect(h.points.count == 1)
        #expect(h.latest?.cpuPercent == nil)
        #expect(h.latest?.memoryBytes == 15 << 20)
        #expect(h.latest?.processCount == 2)
        #expect(h.latest?.mainPID == 1)
    }

    @Test func cpuPercentIsCPUDeltaOverWallTime() {
        var h = ResourceHistory()
        h.record([s(1, 1)], mainPID: 1, at: t0)
        h.record([s(1, 2)], mainPID: 1, at: t0 + 2)
        #expect(h.latest?.cpuPercent == 50)
    }

    @Test func multipleProcessesCanExceed100() {
        var h = ResourceHistory()
        h.record([s(1, 1), s(2, 1)], mainPID: 1, at: t0)
        h.record([s(1, 3), s(2, 3)], mainPID: 1, at: t0 + 2)
        #expect(h.latest?.cpuPercent == 200)
    }

    @Test func newPidCountsForMemoryNotCPU() {
        var h = ResourceHistory()
        h.record([s(1, 1, 10)], mainPID: 1, at: t0)
        h.record([s(1, 2, 10), s(2, 50, 20)], mainPID: 1, at: t0 + 2)
        #expect(h.latest?.cpuPercent == 50)
        #expect(h.latest?.memoryBytes == 30 << 20)
        #expect(h.latest?.processCount == 2)
    }

    @Test func cpuTimeGoingBackwardsCountsZero() {
        var h = ResourceHistory()
        h.record([s(1, 10)], mainPID: 1, at: t0)
        h.record([s(1, 1)], mainPID: 1, at: t0 + 2)
        #expect(h.latest?.cpuPercent == 0)
    }

    @Test func vanishedPidIsIgnored() {
        var h = ResourceHistory()
        h.record([s(1, 1), s(2, 1)], mainPID: 1, at: t0)
        h.record([s(1, 2)], mainPID: 1, at: t0 + 2)
        #expect(h.latest?.cpuPercent == 50)
        #expect(h.latest?.processCount == 1)
    }

    @Test func pointsOlderThanWindowAreTrimmed() {
        var h = ResourceHistory()
        h.record([s(1, 1)], mainPID: 1, at: t0)
        h.record([s(1, 1)], mainPID: 1, at: t0 + 200)
        h.record([s(1, 1)], mainPID: 1, at: t0 + 400)
        #expect(h.points.map(\.date) == [t0 + 200, t0 + 400])
    }

    @Test func formatting() {
        #expect(ResourceFormat.cpu(3.42) == "%3,4")
        #expect(ResourceFormat.cpu(27.6) == "%28")
        #expect(ResourceFormat.cpu(0) == "%0")
        #expect(ResourceFormat.memory(412 << 20) == "412 MB")
        #expect(ResourceFormat.memory(1_610_612_736) == "1,5 GB")
        #expect(ResourceFormat.duration(35) == "35 sn")
        #expect(ResourceFormat.duration(240) == "4 dk")
        #expect(ResourceFormat.duration(7500) == "2 sa 5 dk")
        #expect(ResourceFormat.duration(90000) == "1 g 1 sa")
    }

    @Test func libprocSeesOwnProcessGroup() throws {
        let table = LibprocTable()
        #expect(table.pids(inGroup: getpgrp()).contains(getpid()))
        let before = try #require(table.sample(getpid()))
        let start = Date()
        var x = 0.0
        while Date().timeIntervalSince(start) < 0.3 { x += sin(x) + 1 }
        #expect(x > 0)
        let after = try #require(table.sample(getpid()))
        let delta = Double(after.cpuNanos - before.cpuNanos)
        #expect(delta > 0.1e9 && delta < 3e9)
        #expect(after.residentBytes > 1 << 20)
    }
}
