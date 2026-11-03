import Foundation

/// The parts of `git status --porcelain=v2 --branch` the detail screen shows.
public struct GitStatus: Equatable, Sendable {
    /// nil in detached HEAD.
    public var branch: String?
    /// Short (7-char) commit id.
    public var commit: String?
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    /// Tracked files with changes (modified, renamed, conflicted); untracked files are not included.
    public var changedFiles: [String] = []
    /// The upstream is configured but its remote branch no longer exists (e.g. deleted after a PR merge).
    public var upstreamGone = false

    public var isDetached: Bool { branch == nil }

    public init(branch: String? = nil, commit: String? = nil, upstream: String? = nil, ahead: Int = 0, behind: Int = 0, changedFiles: [String] = []) {
        self.branch = branch
        self.commit = commit
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changedFiles = changedFiles
    }

    public static func parse(porcelainV2 text: String) -> GitStatus {
        var status = GitStatus()
        var sawAheadBehind = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# branch.oid ") {
                let oid = line.dropFirst("# branch.oid ".count)
                status.commit = oid == "(initial)" ? nil : String(oid.prefix(7))
            } else if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                status.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.upstream ") {
                status.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                sawAheadBehind = true
                for part in line.dropFirst("# branch.ab ".count).split(separator: " ") {
                    if part.hasPrefix("+") { status.ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { status.behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if let path = trackedPath(line) {
                status.changedFiles.append(path)
            }
        }
        // git prints branch.ab only when the upstream commit exists.
        status.upstreamGone = status.upstream != nil && !sawAheadBehind
        return status
    }

    /// Path of a changed-entry record: type 1 has 8 fields before the path, type 2 has 9, type u has 10.
    private static func trackedPath(_ line: Substring) -> String? {
        let fieldsBeforePath: Int
        switch line.first {
        case "1": fieldsBeforePath = 8
        case "2": fieldsBeforePath = 9
        case "u": fieldsBeforePath = 10
        default: return nil
        }
        let parts = line.split(separator: " ", maxSplits: fieldsBeforePath, omittingEmptySubsequences: false)
        guard parts.count == fieldsBeforePath + 1 else { return nil }
        let path = parts[fieldsBeforePath]
        // Renames: "<new>\t<orig>".
        return String(path.split(separator: "\t", maxSplits: 1).first ?? path)
    }
}

public struct RemoteBranch: Equatable, Hashable, Sendable {
    public var remote: String
    public var name: String

    public init(remote: String, name: String) {
        self.remote = remote
        self.name = name
    }
}

/// Local branches plus remote branches that have no local branch of the same name.
public struct GitBranchList: Equatable, Sendable {
    public var local: [String]
    public var remoteOnly: [RemoteBranch]

    public init(local: [String] = [], remoteOnly: [RemoteBranch] = []) {
        self.local = local
        self.remoteOnly = remoteOnly
    }

    /// Parses `git for-each-ref --format=%(refname) refs/heads refs/remotes`.
    public static func parse(refs text: String) -> GitBranchList {
        var local: [String] = []
        var remotes: [RemoteBranch] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("refs/heads/") {
                local.append(String(line.dropFirst("refs/heads/".count)))
            } else if line.hasPrefix("refs/remotes/") {
                let rest = line.dropFirst("refs/remotes/".count)
                guard let slash = rest.firstIndex(of: "/") else { continue }
                let name = String(rest[rest.index(after: slash)...])
                guard name != "HEAD", !name.isEmpty else { continue }
                remotes.append(RemoteBranch(remote: String(rest[..<slash]), name: name))
            }
        }
        let localSet = Set(local)
        var seen: Set<String> = []
        let remoteOnly = remotes.filter { !localSet.contains($0.name) && seen.insert($0.name).inserted }
        return GitBranchList(
            local: local.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            remoteOnly: remoteOnly.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }
}
