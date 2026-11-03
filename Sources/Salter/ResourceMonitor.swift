import Foundation
import Observation
import SalterCore

/// Samples CPU and memory of every running service's process group every 2 s.
@MainActor @Observable
final class ResourceMonitor {
    struct Target: Sendable {
        var id: String
        var pgid: pid_t?
        var mainPID: pid_t?
    }

    private(set) var histories: [String: ResourceHistory] = [:]
    @ObservationIgnored private var groups: [String: pid_t] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    func latest(_ id: String) -> ResourcePoint? { histories[id]?.latest }

    func start(targets: @escaping @MainActor () -> [Target]) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick(targets())
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func tick(_ targets: [Target]) {
        for target in targets where target.pgid == nil {
            histories[target.id] = nil
            groups[target.id] = nil
        }
        let live = targets.filter { $0.pgid != nil }
        guard !live.isEmpty else { return }
        Task {
            let results = await Task.detached { () -> [(Target, [ProcessSample])] in
                let table = LibprocTable()
                return live.map { ($0, table.samples(group: $0.pgid!)) }
            }.value
            let now = Date()
            for (target, samples) in results where !samples.isEmpty {
                if groups[target.id] != target.pgid {
                    groups[target.id] = target.pgid
                    histories[target.id] = ResourceHistory()
                }
                histories[target.id]?.record(samples, mainPID: target.mainPID, at: now)
            }
        }
    }
}
