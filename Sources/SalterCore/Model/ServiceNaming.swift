import Foundation

/// How a service is shown: `full` stands alone (pinned list, menu bar, detail title);
/// `inGroup` is the row under its repo group.
public struct ServiceName: Equatable, Sendable {
    public var full: String
    public var inGroup: String

    public init(full: String, inGroup: String) {
        self.full = full
        self.inGroup = inGroup
    }
}

/// Display-name rules. Discovered names ("🚀 Debug FastAPI") are cleaned; the repo name is the title.
public enum ServiceNaming {
    private static let parenDebug = try! NSRegularExpression(pattern: #"\(\s*debug\s*\)"#, options: .caseInsensitive)
    private static let noiseWords = try! NSRegularExpression(pattern: #"\b(debug|run)\b"#, options: .caseInsensitive)
    private static let edgeTrim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-·"))

    /// Strips emoji, the words "Debug"/"Run" and leftover separators.
    public static func clean(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            let p = scalar.properties
            let isEmoji = p.isEmojiPresentation || (p.isEmoji && scalar.value > 0x238C)
            if isEmoji || scalar.value == 0xFE0F || scalar.value == 0x200D { continue }
            scalars.append(scalar)
        }
        var text = String(scalars)
        text = replace(parenDebug, in: text)
        text = replace(noiseWords, in: text)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.trimmingCharacters(in: edgeTrim)
    }

    /// A cleaned name for messages about a launch configuration; never empty.
    public static func label(_ raw: String) -> String {
        let cleaned = clean(raw)
        return cleaned.isEmpty ? "launch.json yapılandırması" : cleaned
    }

    /// "<scanned root folder> / <repo>", or "<parent folder> / <repo>" when no root contains it.
    public static func breadcrumb(repoPath: String, roots: [String]) -> String {
        let url = URL(fileURLWithPath: repoPath)
        let root = roots
            .filter { repoPath.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            .max { $0.count < $1.count }
        let head = root.map { URL(fileURLWithPath: $0).lastPathComponent } ?? url.deletingLastPathComponent().lastPathComponent
        return "\(head) / \(url.lastPathComponent)"
    }

    /// In-repo names for services not added yet (pickers), keyed by discovered id.
    public static func discoveredNames(_ services: [DiscoveredService], repoName: String) -> [String: String] {
        let entries = services.map { Entry(id: $0.id, raw: $0.definition.name, alias: nil) }
        return repoNames(repoName: repoName, entries: entries).mapValues(\.inGroup)
    }

    struct Entry {
        var id: String
        var raw: String
        var alias: String?
    }

    static func repoNames(repoName: String, entries: [Entry]) -> [String: ServiceName] {
        var result: [String: ServiceName] = [:]
        var used: Set<String> = []
        for (index, entry) in entries.enumerated() {
            if let alias = entry.alias {
                result[entry.id] = ServiceName(full: alias, inGroup: alias)
                continue
            }
            if entries.count == 1 {
                result[entry.id] = ServiceName(full: repoName, inGroup: repoName)
                continue
            }
            var suffix = clean(entry.raw)
            if suffix.isEmpty { suffix = String(index + 1) }
            if used.contains(suffix) {
                var n = 2
                while used.contains("\(suffix) \(n)") { n += 1 }
                suffix = "\(suffix) \(n)"
            }
            used.insert(suffix)
            result[entry.id] = ServiceName(full: "\(repoName) · \(suffix)", inGroup: suffix)
        }
        return result
    }

    static func alias(of service: ServiceConfig) -> String? {
        if let name = service.overrides.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if service.source.kind == .manual {
            let name = service.discovered.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        return nil
    }

    private static func replace(_ regex: NSRegularExpression, in text: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }
}

/// Display names for every configured service and repo, resolved against the whole config
/// so names that would collide across repos get their parent folder appended.
public struct DisplayNames: Equatable, Sendable {
    public var services: [String: ServiceName] = [:]
    /// Group titles keyed by repo path.
    public var repos: [String: String] = [:]

    public init(config: AppConfig) {
        var owner: [String: String] = [:]
        for repo in config.repos {
            repos[repo.path] = repo.name
            let entries = repo.services.map {
                ServiceNaming.Entry(id: $0.id, raw: $0.discovered.name, alias: ServiceNaming.alias(of: $0))
            }
            for (id, name) in ServiceNaming.repoNames(repoName: repo.name, entries: entries) {
                services[id] = name
                owner[id] = repo.path
            }
        }

        var reposByFull: [String: Set<String>] = [:]
        for (id, name) in services { reposByFull[name.full, default: []].insert(owner[id]!) }
        for (id, name) in services where (reposByFull[name.full]?.count ?? 0) > 1 {
            let suffix = " (\(Self.parentName(owner[id]!)))"
            services[id] = ServiceName(
                full: name.full + suffix,
                inGroup: name.inGroup == name.full ? name.inGroup + suffix : name.inGroup
            )
        }

        var pathsByName: [String: Int] = [:]
        for repo in config.repos { pathsByName[repo.name, default: 0] += 1 }
        for repo in config.repos where (pathsByName[repo.name] ?? 0) > 1 {
            repos[repo.path] = "\(repo.name) (\(Self.parentName(repo.path)))"
        }
    }

    private static func parentName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
    }
}
