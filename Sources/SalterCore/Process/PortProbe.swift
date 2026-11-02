import Foundation

public struct ListeningSocket: Equatable, Sendable {
    public var pid: pid_t
    public var pgid: pid_t
    public var command: String
    public var port: Int

    public init(pid: pid_t, pgid: pid_t, command: String, port: Int) {
        self.pid = pid
        self.pgid = pgid
        self.command = command
        self.port = port
    }
}

/// Finds listening TCP ports with `lsof`, so a service is "running" only once it actually listens.
public enum PortProbe {
    /// All TCP sockets in LISTEN state owned by processes visible to this user.
    public static func snapshot() -> [ListeningSocket] {
        guard let output = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpgcn"]) else { return [] }
        return parse(output)
    }

    public static func ports(forGroup pgid: pid_t, in snapshot: [ListeningSocket]) -> [Int] {
        Array(Set(snapshot.filter { $0.pgid == pgid }.map(\.port))).sorted()
    }

    public static func owners(ofPort port: Int, in snapshot: [ListeningSocket]) -> [ListeningSocket] {
        snapshot.filter { $0.port == port }
    }

    static func parse(_ output: String) -> [ListeningSocket] {
        var result: [ListeningSocket] = []
        var pid: pid_t = 0
        var pgid: pid_t = 0
        var command = ""
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p":
                pid = pid_t(value) ?? 0
                pgid = 0
                command = ""
            case "g":
                pgid = pid_t(value) ?? 0
            case "c":
                command = String(value)
            case "n":
                guard let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                let socket = ListeningSocket(pid: pid, pgid: pgid, command: command, port: port)
                if !result.contains(socket) { result.append(socket) }
            default:
                break
            }
        }
        return result
    }

    static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
