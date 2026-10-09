import DevLauncherCore
import SwiftUI

extension ServiceStatus {
    var color: Color {
        switch self {
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        case .running: return .green
        case .crashed: return .red
        }
    }

    var label: String {
        switch self {
        case .stopped: return "Durdu"
        case .starting: return "Başlatılıyor…"
        case .running(let ports):
            return ports.isEmpty ? "Çalışıyor" : "Çalışıyor · " + ports.map { ":\($0)" }.joined(separator: " ")
        case .stopping: return "Durduruluyor…"
        case .crashed(let exit): return "Çöktü (\(exit))"
        }
    }

    var ports: [Int] {
        switch self {
        case .running(let ports): return ports
        default: return []
        }
    }
}

struct StatusDot: View {
    let status: ServiceStatus

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .help(status.label)
    }
}

enum ANSIRender {
    static let base: [Color] = [Color(white: 0.45), .red, .green, .orange, .blue, .purple, .teal, .secondary]

    static func attributed(_ line: String) -> AttributedString {
        var result = AttributedString()
        for span in ANSIParser.parse(line) {
            var piece = AttributedString(span.text)
            if let foreground = span.style.foreground { piece.foregroundColor = color(foreground) }
            if span.style.dim { piece.foregroundColor = .secondary }
            if span.style.bold { piece.inlinePresentationIntent = .stronglyEmphasized }
            result += piece
        }
        return result
    }

    static func color(_ color: ANSIColor) -> Color {
        switch color {
        case .standard(let index), .bright(let index):
            return base[max(0, min(7, index))]
        case .palette(let n):
            if n < 16 { return base[n % 8] }
            if n < 232 {
                let v = n - 16
                return Color(red: Double(v / 36) / 5, green: Double((v / 6) % 6) / 5, blue: Double(v % 6) / 5)
            }
            return Color(white: Double(min(n, 255) - 232) / 23)
        case .rgb(let r, let g, let b):
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }
}
