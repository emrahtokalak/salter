import Foundation

/// A running service as remembered in state.json, so orphans can be found after a crash.
public struct RuntimeRecord: Codable, Equatable, Sendable {
    public var serviceID: String
    public var pid: Int32
    public var pgid: Int32
    /// Microseconds since 1970; guards against pid reuse.
    public var startTime: UInt64

    public init(serviceID: String, pid: Int32, pgid: Int32, startTime: UInt64) {
        self.serviceID = serviceID
        self.pid = pid
        self.pgid = pgid
        self.startTime = startTime
    }
}

public final class RuntimeStateStore {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("state.json")
    }

    public func load() -> [RuntimeRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([RuntimeRecord].self, from: data)) ?? []
    }

    public func save(_ records: [RuntimeRecord]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
    }

    /// Records whose process still exists, is the same process (start time matches) and leads its own group.
    public static func liveOrphans(
        _ records: [RuntimeRecord],
        startTime: (pid_t) -> UInt64? = { ProcessInspector.startTime(of: $0) }
    ) -> [RuntimeRecord] {
        records.filter { $0.pgid == $0.pid && startTime($0.pid) == $0.startTime }
    }
}
