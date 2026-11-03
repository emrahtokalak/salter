import SalterCore
import SwiftUI

/// CPU, memory, process count and uptime of the service's process group.
struct ResourceCards: View {
    let history: ResourceHistory?
    let isActive: Bool
    let startedAt: Date?

    var body: some View {
        let point = isActive ? history?.latest : nil
        let points = isActive ? history?.points ?? [] : []
        HStack(spacing: 10) {
            ResourceCard(title: "CPU", value: point?.cpuPercent.map(ResourceFormat.cpu)) {
                Sparkline(values: points.compactMap(\.cpuPercent), color: Theme.accent)
            }
            ResourceCard(title: "Bellek", value: point.map { ResourceFormat.memory($0.memoryBytes) }) {
                Sparkline(values: points.map { Double($0.memoryBytes) }, color: Theme.ok)
            }
            ResourceCard(title: "Süreçler", value: point.map { "\($0.processCount)" }) {
                if let pid = point?.mainPID {
                    Text("PID \(String(pid))").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.text3)
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ResourceCard(
                    title: "Çalışma süresi",
                    value: isActive ? startedAt.map { ResourceFormat.duration(context.date.timeIntervalSince($0)) } : nil
                ) { EmptyView() }
            }
        }
    }
}

struct ResourceCard<Accessory: View>: View {
    let title: String
    let value: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.text3)
                HStack(alignment: .bottom, spacing: 8) {
                    Text(value ?? "—")
                        .font(.system(size: 17, weight: .medium).monospacedDigit())
                        .foregroundStyle(value == nil ? Theme.text3 : Theme.text)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    accessory()
                }
                .frame(height: 24)
            }
        }
        .frame(height: 64)
    }
}

/// A minimal line chart; values are scaled to their own maximum.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            if values.count > 1 {
                let maxValue = max(values.max() ?? 1, 1)
                let step = geometry.size.width / CGFloat(values.count - 1)
                let point = { (i: Int) -> CGPoint in
                    CGPoint(x: CGFloat(i) * step, y: geometry.size.height * (1 - CGFloat(values[i] / maxValue)))
                }
                let line = Path { path in
                    path.move(to: point(0))
                    for i in 1..<values.count { path.addLine(to: point(i)) }
                }
                Path { path in
                    path.addPath(line)
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(color.opacity(0.12))
                line.stroke(color, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
        }
        .frame(width: 72, height: 22)
    }
}
