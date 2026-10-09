import Foundation

/// The user's login-shell environment, captured once so GUI-launched services see the same PATH as a terminal.
public struct ShellEnvironment: Equatable, Sendable {
    public var variables: [String: String]
    public var error: String?

    public init(variables: [String: String], error: String?) {
        self.variables = variables
        self.error = error
    }

    public static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    static let beginMarker = "__DEVLAUNCHER_ENV_BEGIN__"
    static let endMarker = "__DEVLAUNCHER_ENV_END__"

    public static func fallback(error: String, base: [String: String] = ProcessInfo.processInfo.environment) -> ShellEnvironment {
        var variables = base
        variables["PATH"] = fallbackPath
        return ShellEnvironment(variables: variables, error: error)
    }

    /// Runs an interactive login shell once and reads its environment between markers,
    /// so anything .zshrc prints is ignored.
    public static func capture(shell: String = "/bin/zsh", timeout: TimeInterval = 5) -> ShellEnvironment {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "printf '\(beginMarker)'; /usr/bin/env -0; printf '\(endMarker)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let buffer = LockedData()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            buffer.append(handle.availableData)
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return fallback(error: "Shell başlatılamadı: \(error.localizedDescription)")
        }
        let end = Data(endMarker.utf8)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, buffer.snapshot().range(of: end) == nil {
            Thread.sleep(forTimeInterval: 0.05)
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        guard let variables = parse(buffer.snapshot()) else {
            return fallback(error: "Shell ortamı \(Int(timeout)) sn içinde okunamadı")
        }
        return ShellEnvironment(variables: variables, error: nil)
    }

    /// Extracts NUL-separated `KEY=VALUE` pairs between the markers.
    static func parse(_ data: Data) -> [String: String]? {
        guard let begin = data.range(of: Data(beginMarker.utf8)),
              let end = data.range(of: Data(endMarker.utf8), in: begin.upperBound..<data.endIndex) else {
            return nil
        }
        var variables: [String: String] = [:]
        for entry in data[begin.upperBound..<end.lowerBound].split(separator: 0) {
            let text = String(decoding: entry, as: UTF8.self)
            guard let eq = text.firstIndex(of: "="), eq != text.startIndex else { continue }
            variables[String(text[..<eq])] = String(text[text.index(after: eq)...])
        }
        return variables.isEmpty ? nil : variables
    }
}

final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
