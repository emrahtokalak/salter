import Foundation

/// Reads JSON with comments (JSONC), the format VS Code uses for launch.json.
public enum JSONCReader {
    public enum Error: Swift.Error, Equatable {
        case notAnObject
        case invalidJSON(String)
    }

    /// Removes `//` and `/* */` comments and trailing commas; string literals are left untouched.
    public static func sanitize(_ data: Data) -> Data {
        Data(removeTrailingCommas(removeComments([UInt8](data))))
    }

    public static func object(from data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: sanitize(data))
        } catch {
            throw Error.invalidJSON(error.localizedDescription)
        }
        guard let object = value as? [String: Any] else { throw Error.notAnObject }
        return object
    }

    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let slash = UInt8(ascii: "/")
    private static let star = UInt8(ascii: "*")
    private static let newline = UInt8(ascii: "\n")
    private static let comma = UInt8(ascii: ",")
    private static let closeBrace = UInt8(ascii: "}")
    private static let closeBracket = UInt8(ascii: "]")

    private static func removeComments(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(input.count)
        var i = 0
        var inString = false
        while i < input.count {
            let c = input[i]
            if inString {
                out.append(c)
                if c == backslash, i + 1 < input.count {
                    out.append(input[i + 1])
                    i += 2
                    continue
                }
                if c == quote { inString = false }
                i += 1
                continue
            }
            if c == quote {
                inString = true
                out.append(c)
                i += 1
                continue
            }
            if c == slash, i + 1 < input.count, input[i + 1] == slash {
                i += 2
                while i < input.count, input[i] != newline { i += 1 }
                continue
            }
            if c == slash, i + 1 < input.count, input[i + 1] == star {
                i += 2
                while i < input.count, !(input[i] == star && i + 1 < input.count && input[i + 1] == slash) {
                    i += 1
                }
                i += 2
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func removeTrailingCommas(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(input.count)
        var i = 0
        var inString = false
        while i < input.count {
            let c = input[i]
            if inString {
                out.append(c)
                if c == backslash, i + 1 < input.count {
                    out.append(input[i + 1])
                    i += 2
                    continue
                }
                if c == quote { inString = false }
                i += 1
                continue
            }
            if c == quote {
                inString = true
                out.append(c)
                i += 1
                continue
            }
            if c == comma {
                var j = i + 1
                while j < input.count, isWhitespace(input[j]) { j += 1 }
                if j < input.count, input[j] == closeBrace || input[j] == closeBracket {
                    i += 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func isWhitespace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }
}
