import Foundation

/// A dotted numeric version such as `1.2.0` or `v1.2`; missing parts count as 0.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    /// Accepts an optional leading `v` or `v.` (tags like `v.1.1.0` exist) and ignores a
    /// pre-release/build suffix (`-beta.1`, `+5`).
    public init?(_ text: String) {
        var core = Substring(text.trimmingCharacters(in: .whitespaces))
        if core.first == "v" || core.first == "V" {
            core = core.dropFirst()
            if core.first == "." { core = core.dropFirst() }
        }
        if let cut = core.firstIndex(where: { $0 == "-" || $0 == "+" }) { core = core[..<cut] }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        parts = numbers.map { $0! }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0
            let r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

public struct ReleaseInfo: Equatable, Sendable {
    public let tag: String
    public let version: AppVersion
    public let pageURL: URL
}

/// Finds the latest GitHub release without the REST API, whose 60 requests/hour unauthenticated
/// limit is shared by everyone behind the same (corporate) IP: `github.com/<repo>/releases/latest`
/// answers with a redirect to `/releases/tag/<tag>`, so a HEAD request that does not follow it is enough.
public enum ReleaseChecker {
    public static let defaultRepo = "emrahtokalak/salter"
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    public static func latestURL(repo: String = defaultRepo) -> URL {
        URL(string: "https://github.com/\(repo)/releases/latest")!
    }

    /// The release a `releases/latest` redirect points to; nil for anything else (e.g. `/releases` when there is none).
    public static func release(fromRedirect location: URL) -> ReleaseInfo? {
        let parts = location.pathComponents
        guard parts.count >= 2, parts[parts.count - 2] == "tag" else { return nil }
        let tag = parts[parts.count - 1]
        guard parts.count >= 3, parts[parts.count - 3] == "releases",
              let version = AppVersion(tag) else { return nil }
        return ReleaseInfo(tag: tag, version: version, pageURL: location)
    }

    public static func isDue(lastCheck: Date?, now: Date = Date(), interval: TimeInterval = checkInterval) -> Bool {
        guard let lastCheck else { return true }
        // A clock moved backwards would otherwise postpone checks indefinitely.
        return now.timeIntervalSince(lastCheck) >= interval || lastCheck > now
    }

    /// The release worth announcing: newer than `current` and not the version the user chose to skip.
    public static func announce(_ release: ReleaseInfo, current: AppVersion, skipped: String?) -> Bool {
        guard current < release.version else { return false }
        if let skipped, let skippedVersion = AppVersion(skipped), skippedVersion == release.version { return false }
        return true
    }

    public enum CheckError: Error, Equatable {
        case unexpectedResponse(Int)
        case noRelease
    }

    /// One HEAD request; the redirect is read, not followed.
    public static func fetchLatest(repo: String = defaultRepo, timeout: TimeInterval = 20) async throws -> ReleaseInfo {
        var request = URLRequest(url: latestURL(repo: repo), timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        request.setValue("Salter-update-check", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CheckError.unexpectedResponse(0) }
        guard (300..<400).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: request.url)?.absoluteURL else {
            throw CheckError.unexpectedResponse(http.statusCode)
        }
        guard let release = release(fromRedirect: url) else { throw CheckError.noRelease }
        return release
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
