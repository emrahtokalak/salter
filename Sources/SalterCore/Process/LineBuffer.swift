import Foundation

/// Splits a byte stream into lines on `\n`, `\r\n` or a lone `\r` (progress bars); partial lines wait for more data.
public struct LineBuffer: Sendable {
    /// Lines longer than this are emitted without waiting for a newline.
    static let maxPending = 64 * 1024

    private var pending = Data()
    private var lastWasCarriageReturn = false

    public init() {}

    public var hasPending: Bool { !pending.isEmpty }

    public mutating func append(_ data: Data) -> [String] {
        var lines: [String] = []
        for byte in data {
            switch byte {
            case 0x0A where lastWasCarriageReturn:
                lastWasCarriageReturn = false
            case 0x0A, 0x0D:
                lines.append(Self.decode(pending))
                pending.removeAll(keepingCapacity: true)
                lastWasCarriageReturn = byte == 0x0D
            default:
                pending.append(byte)
                lastWasCarriageReturn = false
            }
        }
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
