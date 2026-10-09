import Foundation
@testable import DevLauncherCore

enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` elapses.
@MainActor
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

/// A fresh, empty temporary directory.
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("devlauncher-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Creates an executable shell script named `name` in a new temp directory and returns the directory.
func makeFakeExecutable(_ name: String) throws -> URL {
    let dir = try makeTempDirectory()
    let file = dir.appendingPathComponent(name)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    return dir
}
