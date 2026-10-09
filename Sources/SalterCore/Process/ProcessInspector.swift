import Darwin
import Foundation

public enum ProcessInspector {
    public static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public static func isGroupAlive(_ pgid: pid_t) -> Bool {
        guard pgid > 1 else { return false }
        return kill(-pgid, 0) == 0 || errno == EPERM
    }

    /// Process start time in microseconds since 1970, or nil if there is no such process.
    public static func startTime(of pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
    }
}
