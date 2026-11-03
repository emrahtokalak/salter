import Foundation

/// Why a git action failed, with a Turkish message for the detail screen.
public enum GitFailure: Equatable, Sendable {
    case localChanges([String])
    case untrackedWouldBeOverwritten([String])
    case diverged
    case noUpstream
    case network(String)
    case timeout
    case other(String)

    public var message: String {
        switch self {
        case .localChanges(let files):
            return "Yerel değişiklikler çekilecek dosyalarla çakışıyor: " + files.joined(separator: ", ")
        case .untrackedWouldBeOverwritten(let files):
            return "Takip edilmeyen dosyalar üzerine yazılacağı için branch değiştirilemedi: " + files.joined(separator: ", ")
        case .diverged:
            return "Yerel ve uzak branch ayrışmış; birleştirmeyi VS Code ya da terminalden yap."
        case .noUpstream:
            return "Bu branch'in uzak karşılığı (upstream) yok."
        case .network:
            return "Uzak sunucuya bağlanılamadı"
        case .timeout:
            return "Uzak sunucuya bağlanılamadı (zaman aşımı)"
        case .other:
            return "Git işlemi başarısız oldu."
        }
    }

    /// Raw git output worth showing behind a disclosure.
    public var detail: String? {
        switch self {
        case .network(let raw), .other(let raw): return raw
        default: return nil
        }
    }

    public static func classify(stderr: String, timedOut: Bool) -> GitFailure {
        if timedOut { return .timeout }
        let text = stderr.lowercased()
        let raw = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("your local changes to the following files would be overwritten") {
            return .localChanges(indentedFiles(stderr))
        }
        if text.contains("untracked working tree files would be overwritten") {
            return .untrackedWouldBeOverwritten(indentedFiles(stderr))
        }
        if text.contains("not possible to fast-forward") || text.contains("diverging branches") {
            return .diverged
        }
        if text.contains("no upstream configured") || text.contains("no tracking information") {
            return .noUpstream
        }
        let network = [
            "could not read from remote repository", "could not resolve hostname", "permission denied",
            "unable to access", "authentication failed", "terminal prompts disabled",
            "does not appear to be a git repository", "connection timed out", "connection refused",
            "host key verification failed", "network is unreachable",
        ]
        if network.contains(where: text.contains) { return .network(raw) }
        return .other(raw)
    }

    /// The tab-indented file list git prints under "would be overwritten" errors.
    private static func indentedFiles(_ stderr: String) -> [String] {
        stderr.split(separator: "\n")
            .filter { $0.hasPrefix("\t") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
