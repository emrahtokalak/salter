import Darwin
import Foundation

public struct ProcessSample: Equatable, Sendable {
    public var pid: pid_t
    /// Total user + system CPU time.
    public var cpuNanos: UInt64
    public var residentBytes: UInt64

    public init(pid: pid_t, cpuNanos: UInt64, residentBytes: UInt64) {
        self.pid = pid
        self.cpuNanos = cpuNanos
        self.residentBytes = residentBytes
    }
}

/// Reads per-process usage; abstracted so the history math is testable without real processes.
public protocol ProcessTable: Sendable {
    func pids(inGroup pgid: pid_t) -> [pid_t]
    func sample(_ pid: pid_t) -> ProcessSample?
}

public extension ProcessTable {
    /// Samples every live member of a process group; members that exit meanwhile are skipped.
    func samples(group pgid: pid_t) -> [ProcessSample] {
        pids(inGroup: pgid).compactMap(sample)
    }
}

/// `ProcessTable` backed by libproc.
public struct LibprocTable: ProcessTable {
    /// Task-info CPU times are Mach absolute-time ticks (not nanoseconds on Apple silicon).
    private static let ticksToNanos: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? 1 : Double(info.numer) / Double(info.denom)
    }()

    public init() {}

    public func pids(inGroup pgid: pid_t) -> [pid_t] {
        guard pgid > 1 else { return [] }
        var capacity = 64
        while true {
            var buffer = [pid_t](repeating: 0, count: capacity)
            // Returns a pid count, not a byte count.
            let count = Int(proc_listpgrppids(pgid, &buffer, Int32(capacity * MemoryLayout<pid_t>.size)))
            guard count >= 0 else { return [] }
            if count < capacity || capacity >= 16_384 {
                return buffer.prefix(min(count, capacity)).filter { $0 > 0 }
            }
            capacity *= 4
        }
    }

    public func sample(_ pid: pid_t) -> ProcessSample? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        let ticks = Double(info.pti_total_user) + Double(info.pti_total_system)
        return ProcessSample(pid: pid, cpuNanos: UInt64(ticks * Self.ticksToNanos), residentBytes: info.pti_resident_size)
    }
}

public struct ResourcePoint: Equatable, Sendable {
    public var date: Date
    /// nil for the first sample, which has nothing to diff against. 100 = one full core.
    public var cpuPercent: Double?
    public var memoryBytes: UInt64
    public var processCount: Int
    public var mainPID: pid_t?
}

/// A service's recent usage: one point per sample, kept for `window` seconds.
public struct ResourceHistory: Equatable, Sendable {
    public static let window: TimeInterval = 300
    /// Shorter gaps (e.g. two samples delivered back to back) give meaningless CPU ratios.
    static let minimumCPUInterval: TimeInterval = 0.5

    public private(set) var points: [ResourcePoint] = []
    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousDate: Date?

    public init() {}

    public var latest: ResourcePoint? { points.last }

    public mutating func record(_ samples: [ProcessSample], mainPID: pid_t?, at date: Date) {
        if let previousDate, date <= previousDate { return }
        var cpu: Double?
        if let previousDate, date.timeIntervalSince(previousDate) >= Self.minimumCPUInterval {
            var nanos: UInt64 = 0
            for sample in samples {
                if let before = previousCPU[sample.pid], sample.cpuNanos > before {
                    nanos += sample.cpuNanos - before
                }
            }
            cpu = Double(nanos) / 1e9 / date.timeIntervalSince(previousDate) * 100
        }
        points.append(ResourcePoint(
            date: date,
            cpuPercent: cpu,
            memoryBytes: samples.reduce(0) { $0 + $1.residentBytes },
            processCount: samples.count,
            mainPID: mainPID
        ))
        previousCPU = Dictionary(samples.map { ($0.pid, $0.cpuNanos) }, uniquingKeysWith: { $1 })
        previousDate = date
        let cutoff = date.addingTimeInterval(-Self.window)
        points.removeAll { $0.date < cutoff }
    }
}
