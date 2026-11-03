import SalterCore
import SwiftUI

struct LogView: View {
    @Environment(AppModel.self) private var model
    let supervisor: ServiceSupervisor
    @State private var query = ""
    @State private var autoScroll = true

    var body: some View {
        let lines = filtered
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.text3)
                    TextField("Logda ara…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: 320, minHeight: 24)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
                Toggle("Otomatik kaydır", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                Spacer()
                Text("\(lines.count) satır").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
                Button("Log dosyası") { model.integration.reveal(LogFileWriter.url(forService: supervisor.id).path) }
                    .buttonStyle(QuietButtonStyle(height: 24, tint: Theme.text2))
                Button("Temizle") { supervisor.logs.clear() }
                    .buttonStyle(QuietButtonStyle(height: 24, tint: Theme.text2))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            Rectangle().fill(Theme.line).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            LogLineView(line: line).id(line.id)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Theme.bg)
                .onChange(of: supervisor.logs.lines.last?.id) { _, last in
                    guard autoScroll, query.isEmpty, let last else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
                .onAppear {
                    if let last = lines.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var filtered: [LogLine] {
        let all = supervisor.logs.lines
        guard !query.isEmpty else { return all }
        return all.filter { ANSIParser.strip($0.text).localizedCaseInsensitiveContains(query) }
    }
}

struct LogLineView: View {
    let line: LogLine

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let font = Font.system(size: 11.5, design: .monospaced)

    var body: some View {
        Group {
            if line.kind == .system {
                systemRow
            } else {
                outputRow(LogLineParser.parse(line.text))
            }
        }
        .font(Self.font)
        .lineSpacing(4)
        .padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var systemRow: some View {
        let system = SystemLine(line.text)
        if system.isDivider {
            Text("— \(system.text) —")
                .foregroundStyle(system.color)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                timeColumn(line.date)
                Text("").frame(width: 44, alignment: .leading)
                Text(system.text).foregroundStyle(system.color)
            }
        }
    }

    private func outputRow(_ parsed: ParsedLogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            timeColumn(parsed.time ?? line.date)
            Text(parsed.level?.label ?? "")
                .foregroundStyle(color(parsed.level))
                .frame(width: 44, alignment: .leading)
            if parsed.isStructured {
                let fields = parsed.fields.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
                (Text(parsed.message).foregroundColor(Theme.logText)
                    + Text(fields.isEmpty ? "" : (parsed.message.isEmpty ? "" : " ") + fields).foregroundColor(Theme.text3))
            } else {
                Text(ANSIRender.attributed(line.text)).foregroundStyle(Theme.logText)
            }
        }
    }

    private func timeColumn(_ date: Date) -> some View {
        Text(Self.clock.string(from: date)).foregroundStyle(Theme.text3).fixedSize()
    }

    private func color(_ level: LogLevel?) -> Color {
        switch level {
        case .info: return Theme.info
        case .warn: return Theme.warn
        case .error: return Theme.err
        case .debug, .trace, nil: return Theme.text3
        }
    }
}

/// Supervisor messages ("──── durduruldu ────", "💥 …") without decoration or emoji; the emoji become a tone.
struct SystemLine {
    let text: String
    let isDivider: Bool
    let color: Color

    init(_ raw: String) {
        var color = Theme.text3
        if raw.hasPrefix("❌") || raw.hasPrefix("💥") { color = Theme.err }
        if raw.hasPrefix("⚠️") { color = Theme.warn }
        if raw.hasPrefix("✅") { color = Theme.ok }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "─ "))
        isDivider = raw.hasPrefix("─")
        let scalars = trimmed.unicodeScalars.filter { scalar in
            let p = scalar.properties
            return !(p.isEmojiPresentation || (p.isEmoji && scalar.value > 0x238C)) && scalar.value != 0xFE0F
        }
        text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
        self.color = color
    }
}
