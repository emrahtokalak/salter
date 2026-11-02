import Foundation
import Observation

public struct LogLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let kind: OutputKind
    public let text: String
    public let date: Date
}

/// In-memory tail of a service's output. Trims in batches so appends stay cheap.
@MainActor @Observable
public final class LogBuffer {
    public let capacity: Int
    public private(set) var lines: [LogLine] = []
    @ObservationIgnored private var nextID = 0

    public init(capacity: Int = 5_000) {
        self.capacity = capacity
    }

    public func append(_ kind: OutputKind, _ texts: [String], date: Date = Date()) {
        guard !texts.isEmpty else { return }
        var batch: [LogLine] = []
        batch.reserveCapacity(texts.count)
        for text in texts {
            batch.append(LogLine(id: nextID, kind: kind, text: text, date: date))
            nextID += 1
        }
        lines.append(contentsOf: batch)
        let slack = max(capacity / 10, 1)
        if lines.count > capacity + slack {
            lines.removeFirst(lines.count - capacity)
        }
    }

    public func clear() {
        lines.removeAll()
    }
}
