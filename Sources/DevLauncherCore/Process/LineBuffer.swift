import Foundation

/// Splits a byte stream into lines; partial lines wait for more data.
public struct LineBuffer: Sendable {
    /// Lines longer than this are emitted without waiting for a newline.
    static let maxPending = 64 * 1024

    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
            lines.append(Self.decode(pending[start..<newline]))
            start = pending.index(after: newline)
        }
        if start != pending.startIndex { pending = Data(pending[start...]) }
        if pending.count > Self.maxPending {
            lines.append(Self.decode(pending))
            pending = Data()
        }
        return lines
    }

    public mutating func flush() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending = Data() }
        return Self.decode(pending)
    }

    static func decode(_ bytes: Data) -> String {
        var bytes = bytes
        if bytes.last == 0x0D { bytes = bytes.dropLast() }
        return String(decoding: bytes, as: UTF8.self)
    }
}
