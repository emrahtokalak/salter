import Foundation
import Observation

public enum ServiceStatus: Equatable, Sendable {
    case stopped
    case starting
    case running(ports: [Int])
    case stopping
    case crashed(ExitStatus)

    public var isActive: Bool {
        switch self {
        case .starting, .running, .stopping: return true
        case .stopped, .crashed: return false
        }
    }

    public var isCrashed: Bool {
        if case .crashed = self { return true }
        return false
    }
}

/// Owns one service's process: start, stop, port-based readiness, crash detection and logs.
@MainActor @Observable
public final class ServiceSupervisor {
    public static let noPortGracePeriod: TimeInterval = 3

    public let id: String
    public let logs: LogBuffer
    public private(set) var status: ServiceStatus = .stopped
    public private(set) var pgid: pid_t?
    public private(set) var isAdopted = false
    public private(set) var isRunningSetup = false
    public private(set) var startedAt: Date?

    @ObservationIgnored public var onStatusChange: ((ServiceSupervisor) -> Void)?
    @ObservationIgnored private let fileLog: LogFileWriter?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var process: SpawnedProcess?
    @ObservationIgnored private var setupProcess: SpawnedProcess?
    @ObservationIgnored private var record: RuntimeRecord?
    @ObservationIgnored private var expectsPort = false
    @ObservationIgnored private var generation = 0

    public init(id: String, logs: LogBuffer? = nil, fileLog: LogFileWriter? = nil, now: @escaping () -> Date = { Date() }) {
        self.id = id
        self.logs = logs ?? LogBuffer()
        self.fileLog = fileLog
        self.now = now
    }

    public var runtimeRecord: RuntimeRecord? { record }

    public func start(_ plan: LaunchPlan, expectsPort: Bool) throws {
        guard !status.isActive else { return }
        generation += 1
        let current = generation
        self.expectsPort = expectsPort
        appendSystem(
            ["──── başlatılıyor · \(Self.timestamp(now())) ────",
             "$ " + ShellWords.join([plan.request.executable] + plan.request.arguments),
             "cwd: \(plan.request.cwd)"]
                + plan.warnings.map { "⚠️ \($0)" }
        )
        do {
            let spawned = try ProcessRunner.spawn(
                plan.request,
                onLines: { [weak self] kind, lines in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(kind, lines) } }
                },
                onExit: { [weak self] exit in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.processExited(exit, generation: current) } }
                }
            )
            process = spawned
            pgid = spawned.pgid
            isAdopted = false
            startedAt = now()
            record = RuntimeRecord(serviceID: id, pid: spawned.pid, pgid: spawned.pgid, startTime: spawned.startTime)
            setStatus(.starting)
        } catch {
            appendSystem(["❌ başlatılamadı: \(error)"])
            setStatus(.crashed(.exited(127)))
            throw error
        }
    }

    public func stop(grace: TimeInterval = 5) async {
        guard let group = pgid, status.isActive, status != .stopping else { return }
        if isAdopted, let record, !Self.isSameProcess(record) {
            // The pid now belongs to another process; never signal its group.
            clearProcessState()
            appendSystem(["──── sahiplenilen süreç zaten sonlanmış ────"])
            setStatus(.stopped)
            return
        }
        setStatus(.stopping)
        appendSystem(["──── durduruluyor (SIGTERM) ────"])
        let killed = await ProcessRunner.terminateGroup(group, grace: grace)
        if killed { appendSystem(["⚠️ \(Int(grace)) sn içinde kapanmadı, SIGKILL gönderildi"]) }
        if isAdopted, status == .stopping {
            clearProcessState()
            appendSystem(["──── durduruldu ────"])
            setStatus(.stopped)
        }
    }

    /// Tracks a process left over from a previous app session. Its output cannot be recovered.
    public func adopt(_ record: RuntimeRecord) {
        guard !status.isActive else { return }
        generation += 1
        self.record = record
        pgid = record.pgid
        isAdopted = true
        expectsPort = false
        startedAt = now()
        appendSystem(["──── önceki oturumdan sahiplenildi (pid \(record.pid)); loglar bu oturumda görüntülenemez ────"])
        setStatus(.running(ports: []))
    }

    /// Updates readiness and ports from a port snapshot; also notices when an adopted process exits.
    public func refresh(
        with snapshot: [ListeningSocket],
        isSameProcess: (RuntimeRecord) -> Bool = { ServiceSupervisor.isSameProcess($0) }
    ) {
        guard let group = pgid else { return }
        if isAdopted, let record, !isSameProcess(record) {
            clearProcessState()
            appendSystem(["──── sahiplenilen süreç sonlandı ────"])
            setStatus(.stopped)
            return
        }
        let ports = PortProbe.ports(forGroup: group, in: snapshot)
        switch status {
        case .starting:
            if !ports.isEmpty {
                setStatus(.running(ports: ports))
            } else if !expectsPort, let startedAt, now().timeIntervalSince(startedAt) >= Self.noPortGracePeriod {
                setStatus(.running(ports: []))
            }
        case .running(let current) where current != ports:
            setStatus(.running(ports: ports))
        default:
            break
        }
    }

    /// Runs a one-off setup command (e.g. `uv sync`) whose output goes to this service's log.
    public func runSetup(_ request: SpawnRequest) throws {
        guard !isRunningSetup else { return }
        appendSystem(["──── kurulum: " + ShellWords.join([request.executable] + request.arguments) + " ────"])
        setupProcess = try ProcessRunner.spawn(
            request,
            onLines: { [weak self] kind, lines in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(kind, lines) } }
            },
            onExit: { [weak self] exit in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.setupFinished(exit) } }
            }
        )
        isRunningSetup = true
    }

    public func appendSystem(_ lines: [String]) {
        logs.append(.system, lines)
        fileLog?.write(lines)
    }

    private func receive(_ kind: OutputKind, _ lines: [String]) {
        logs.append(kind, lines)
        fileLog?.write(lines)
    }

    private func processExited(_ exit: ExitStatus, generation exited: Int) {
        guard exited == generation else { return }
        let group = pgid
        let wasStopping = status == .stopping
        clearProcessState()
        if wasStopping {
            appendSystem(["──── durduruldu ────"])
            setStatus(.stopped)
        } else {
            appendSystem(["💥 beklenmedik şekilde sonlandı (\(exit))"])
            setStatus(.crashed(exit))
            if let group {
                Task.detached { await ProcessRunner.terminateGroup(group, grace: 2) }
            }
        }
    }

    private func setupFinished(_ exit: ExitStatus) {
        isRunningSetup = false
        setupProcess = nil
        appendSystem([exit == .exited(0) ? "✅ kurulum tamamlandı" : "❌ kurulum başarısız (\(exit))"])
        onStatusChange?(self)
    }

    private func clearProcessState() {
        process = nil
        record = nil
        pgid = nil
        isAdopted = false
    }

    private func setStatus(_ newStatus: ServiceStatus) {
        guard newStatus != status else { return }
        status = newStatus
        onStatusChange?(self)
    }

    /// True while `record.pid` is still the process that was recorded (guards against pid reuse).
    public nonisolated static func isSameProcess(_ record: RuntimeRecord) -> Bool {
        ProcessInspector.startTime(of: record.pid) == record.startTime
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
