import Darwin
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct RuntimeStateStoreTests {
    @Test func roundTrip() throws {
        let store = RuntimeStateStore(directory: try makeTempDirectory())
        #expect(store.load().isEmpty)
        let records = [RuntimeRecord(serviceID: "a/b", pid: 10, pgid: 10, startTime: 5)]
        store.save(records)
        #expect(store.load() == records)
    }

    @Test func liveOrphansRequireMatchingStartTime() {
        let records = [
            RuntimeRecord(serviceID: "a", pid: 1, pgid: 1, startTime: 100),
            RuntimeRecord(serviceID: "b", pid: 2, pgid: 2, startTime: 200),
            RuntimeRecord(serviceID: "c", pid: 3, pgid: 3, startTime: 300),
        ]
        let table: [pid_t: UInt64] = [1: 100, 2: 999]
        #expect(RuntimeStateStore.liveOrphans(records) { table[$0] }.map(\.serviceID) == ["a"])
    }

    @Test func currentProcessCountsAsLive() throws {
        let me = getpid()
        let start = try #require(ProcessInspector.startTime(of: me))
        let record = RuntimeRecord(serviceID: "me", pid: me, pgid: me, startTime: start)
        #expect(RuntimeStateStore.liveOrphans([record]) == [record])
    }
}
