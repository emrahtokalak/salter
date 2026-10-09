import Foundation

public enum ANSIColor: Equatable, Sendable {
    case standard(Int)
    case bright(Int)
    case palette(Int)
    case rgb(Int, Int, Int)
}

public struct ANSIStyle: Equatable, Sendable {
    public var foreground: ANSIColor?
    public var bold: Bool
    public var dim: Bool

    public init(foreground: ANSIColor? = nil, bold: Bool = false, dim: Bool = false) {
        self.foreground = foreground
        self.bold = bold
        self.dim = dim
    }
}

public struct ANSISpan: Equatable, Sendable {
    public var text: String
    public var style: ANSIStyle

    public init(text: String, style: ANSIStyle) {
        self.text = text
        self.style = style
    }
}

/// Interprets SGR color/bold codes in one log line and drops every other escape sequence.
public enum ANSIParser {
    public static func parse(_ line: String) -> [ANSISpan] {
        let scalars = Array(line.unicodeScalars)
        var spans: [ANSISpan] = []
        var style = ANSIStyle()
        var text = String.UnicodeScalarView()

        func flush() {
            if !text.isEmpty {
                spans.append(ANSISpan(text: String(text), style: style))
                text = String.UnicodeScalarView()
            }
        }

        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if scalar == "\u{1B}", i + 1 < scalars.count {
                let next = scalars[i + 1]
                if next == "[" {
                    var j = i + 2
                    var params = ""
                    while j < scalars.count, !(0x40...0x7E).contains(scalars[j].value) {
                        params.unicodeScalars.append(scalars[j])
                        j += 1
                    }
                    if j < scalars.count, scalars[j] == "m" {
                        flush()
                        apply(params, to: &style)
                    }
                    i = j + 1
                    continue
                }
                if next == "]" {
                    var j = i + 2
                    while j < scalars.count {
                        if scalars[j] == "\u{07}" { j += 1; break }
                        if scalars[j] == "\u{1B}", j + 1 < scalars.count, scalars[j + 1] == "\\" { j += 2; break }
                        j += 1
                    }
                    i = j
                    continue
                }
                i += 2
                continue
            }
            if scalar.value < 0x20 && scalar != "\t" {
                i += 1
                continue
            }
            text.append(scalar)
            i += 1
        }
        flush()
        return spans
    }

    public static func strip(_ line: String) -> String {
        parse(line).map(\.text).joined()
    }

    static func apply(_ params: String, to style: inout ANSIStyle) {
        let codes = params.isEmpty
            ? [0]
            : params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var k = 0
        while k < codes.count {
            let code = codes[k]
            switch code {
            case 0: style = ANSIStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 22:
                style.bold = false
                style.dim = false
            case 30...37: style.foreground = .standard(code - 30)
            case 39: style.foreground = nil
            case 90...97: style.foreground = .bright(code - 90)
            case 38, 48:
                if k + 2 < codes.count, codes[k + 1] == 5 {
                    if code == 38 { style.foreground = .palette(codes[k + 2]) }
                    k += 2
                } else if k + 4 < codes.count, codes[k + 1] == 2 {
                    if code == 38 { style.foreground = .rgb(codes[k + 2], codes[k + 3], codes[k + 4]) }
                    k += 4
                }
            default:
                break
            }
            k += 1
        }
    }
}
