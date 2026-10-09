import Foundation

/// POSIX-shell-like word splitting and quoting, used for editing commands as one line.
public enum ShellWords {
    public static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var hasWord = false
        var quote: Character?
        var escaping = false
        for ch in line {
            if escaping {
                current.append(ch)
                escaping = false
                hasWord = true
                continue
            }
            if let q = quote {
                if ch == q {
                    quote = nil
                } else if ch == "\\" && q == "\"" {
                    escaping = true
                } else {
                    current.append(ch)
                }
                continue
            }
            switch ch {
            case "\\":
                escaping = true
                hasWord = true
            case "\"", "'":
                quote = ch
                hasWord = true
            case " ", "\t", "\n":
                if hasWord {
                    words.append(current)
                    current = ""
                    hasWord = false
                }
            default:
                current.append(ch)
                hasWord = true
            }
        }
        if hasWord { words.append(current) }
        return words
    }

    public static func join(_ words: [String]) -> String {
        words.map(quote).joined(separator: " ")
    }

    private static let safe = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=@%+,"
    )

    static func quote(_ word: String) -> String {
        if word.isEmpty { return "''" }
        if word.unicodeScalars.allSatisfy({ safe.contains($0) }) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
