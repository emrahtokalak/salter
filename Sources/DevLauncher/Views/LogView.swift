import DevLauncherCore
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
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Logda ara", text: $query)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 240)
                Toggle("Otomatik kaydır", isOn: $autoScroll).toggleStyle(.checkbox)
                Spacer()
                Text("\(lines.count) satır").font(.caption).foregroundStyle(.secondary)
                Button("Log dosyası") { model.integration.reveal(LogFileWriter.url(forService: supervisor.id).path) }
                Button("Temizle") { supervisor.logs.clear() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            LogLineView(line: line).id(line.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
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

    var body: some View {
        Group {
            if line.kind == .system {
                Text(line.text).foregroundStyle(.secondary).italic()
            } else {
                Text(ANSIRender.attributed(line.text))
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
