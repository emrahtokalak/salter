import Foundation

public enum Slug {
    /// Lowercase ASCII letters and digits joined by single dashes.
    public static func make(_ text: String) -> String {
        var out = ""
        var lastWasDash = true
        for scalar in text.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "service" : out
    }

    /// Returns `base`, or `base-2`, `base-3`… so that the result is not in `taken`.
    public static func unique(_ base: String, taken: Set<String>) -> String {
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}
