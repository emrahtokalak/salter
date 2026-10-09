import DevLauncherCore
import SwiftUI

struct ServiceDetailView: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var tab: Tab = .log

    enum Tab: String, CaseIterable, Identifiable {
        case log = "Log"
        case settings = "Ayarlar"
        var id: String { rawValue }
    }

    var body: some View {
        if let service = model.service(id), let supervisor = model.supervisors[id] {
            VStack(spacing: 0) {
                header(service, supervisor)
                banners(service, supervisor)
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .padding(.vertical, 8)
                Divider()
                switch tab {
                case .log: LogView(supervisor: supervisor)
                case .settings: ServiceSettingsForm(service: service)
                }
            }
        }
    }

    @ViewBuilder
    private func header(_ service: ServiceConfig, _ supervisor: ServiceSupervisor) -> some View {
        let definition = service.effective
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusDot(status: supervisor.status)
                    Text(definition.name).font(.title2.bold())
                    if supervisor.isAdopted {
                        Text("sahiplenildi")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(model.repoName(of: id) + " · " + supervisor.status.label).foregroundStyle(.secondary)
                Text(ShellWords.join(definition.launchCommand))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            ForEach(supervisor.status.ports, id: \.self) { port in
                Button(":\(port)") { model.integration.openBrowser(port: port) }.help("Tarayıcıda aç")
            }
            Button { model.togglePin(id) } label: {
                Image(systemName: model.isPinned(id) ? "pin.fill" : "pin")
            }
            .help(model.isPinned(id) ? "Sabitlemeyi kaldır" : "Sabitle")
            if supervisor.status.isActive {
                Button("Yeniden başlat") { model.restart(id) }.disabled(supervisor.status == .stopping)
                Button("Durdur") { model.stop(id) }.disabled(supervisor.status == .stopping)
            } else {
                Button("Başlat") { model.start(id) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("r")
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func banners(_ service: ServiceConfig, _ supervisor: ServiceSupervisor) -> some View {
        if let requirement = model.setupRequirement(id) {
            Banner(systemImage: "exclamationmark.triangle.fill", tint: .orange, text: requirement.message) {
                if requirement.fix != nil {
                    Button(supervisor.isRunningSetup ? "Çalışıyor…" : requirement.fixTitle) { model.runSetup(id) }
                        .disabled(supervisor.isRunningSetup)
                }
            }
        }
        if service.sourceMissing {
            Banner(
                systemImage: "questionmark.circle.fill",
                tint: .orange,
                text: "Bu servis artık kaynağında (launch.json / package.json) bulunmuyor. Ayarlar sekmesinden kaldırabilirsin."
            ) { EmptyView() }
        }
    }
}

struct Banner<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            actions()
        }
        .padding(10)
        .background(tint.opacity(0.12))
    }
}
