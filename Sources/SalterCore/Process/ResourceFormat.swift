import Foundation

/// Turkish-style formatting for the resource cards ("%3,4", "1,5 GB", "2 sa 5 dk").
public enum ResourceFormat {
    public static func cpu(_ percent: Double) -> String {
        let value = max(0, percent)
        let tenths = (value * 10).rounded() / 10
        if value < 10, tenths != tenths.rounded() {
            return "%" + decimal(tenths)
        }
        return "%\(Int(value.rounded()))"
    }

    public static func memory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1024 { return "\(Int(mb.rounded())) MB" }
        return decimal(((mb / 1024) * 10).rounded() / 10) + " GB"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400, hours = (total % 86_400) / 3600, minutes = (total % 3600) / 60
        if total < 60 { return "\(total) sn" }
        if total < 3600 { return "\(minutes) dk" }
        if total < 86_400 { return minutes > 0 ? "\(hours) sa \(minutes) dk" : "\(hours) sa" }
        return hours > 0 ? "\(days) g \(hours) sa" : "\(days) g"
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
