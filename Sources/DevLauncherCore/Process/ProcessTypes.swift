import Foundation

public enum OutputKind: String, Codable, Sendable {
    case stdout, stderr, system
}

public enum ExitStatus: Equatable, Sendable, CustomStringConvertible {
    case exited(Int32)
    case signaled(Int32)

    /// Decodes a `waitpid` status word.
    public init(waitStatus: Int32) {
        let signal = waitStatus & 0x7f
        self = signal == 0 ? .exited((waitStatus >> 8) & 0xff) : .signaled(signal)
    }

    /// Shell-style code: the exit code, or 128 + signal number.
    public var code: Int32 {
        switch self {
        case .exited(let code): return code
        case .signaled(let signal): return 128 + signal
        }
    }

    public var description: String {
        switch self {
        case .exited(let code): return "çıkış kodu \(code)"
        case .signaled(let signal): return "sinyal \(signal)"
        }
    }
}

public struct SpawnRequest: Equatable, Sendable {
    /// Absolute path of the executable.
    public var executable: String
    /// Arguments after argv[0].
    public var arguments: [String]
    public var environment: [String: String]
    public var cwd: String

    public init(executable: String, arguments: [String], environment: [String: String], cwd: String) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.cwd = cwd
    }
}

public enum ProcessRunnerError: Error, Equatable, CustomStringConvertible {
    case executableNotFound(String)
    case directoryNotFound(String)
    case spawnFailed(Int32)

    public var description: String {
        switch self {
        case .executableNotFound(let name): return "çalıştırılabilir dosya bulunamadı: \(name)"
        case .directoryNotFound(let path): return "çalışma klasörü yok: \(path)"
        case .spawnFailed(let code): return "süreç başlatılamadı: \(String(cString: strerror(code)))"
        }
    }
}
