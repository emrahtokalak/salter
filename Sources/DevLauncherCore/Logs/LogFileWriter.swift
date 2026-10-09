import Foundation

/// Appends raw log lines to a file on a background queue, rotating to `<file>.1` past `maxBytes`.
public final class LogFileWriter: @unchecked Sendable {
    public let url: URL
    public let maxBytes: Int
    private let queue = DispatchQueue(label: "devlauncher.logfile")
    private var handle: FileHandle?
    private var size = 0

    public init(url: URL, maxBytes: Int = 10 * 1024 * 1024) {
        self.url = url
        self.maxBytes = maxBytes
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DevLauncher")
    }

    public static func url(forService id: String, directory: URL = defaultDirectory) -> URL {
        directory.appendingPathComponent("\(Slug.make(id)).log")
    }

    public func write(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        let data = Data(lines.map { $0 + "\n" }.joined().utf8)
        queue.async { [self] in self.append(data) }
    }

    /// Blocks until queued writes are on disk.
    public func flush() {
        queue.sync {}
    }

    private func append(_ data: Data) {
        if handle == nil { open() }
        if size > 0, size + data.count > maxBytes { rotate() }
        try? handle?.write(contentsOf: data)
        size += data.count
    }

    private func open() {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let rotated = URL(fileURLWithPath: url.path + ".1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
        open()
    }
}
