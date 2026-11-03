import AppKit
import SalterCore
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
                VStack(alignment: .leading, spacing: 0) {
                    header(service, supervisor)
                    GitRow(serviceID: id)
                    banners(service, supervisor)
                    ResourceCards(
                        history: model.resources.histories[id],
                        isActive: supervisor.status.isActive,
                        startedAt: supervisor.startedAt
                    )
                    .padding(.bottom, 16)
                    UnderlineTabs(selection: $tab)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                Rectangle().fill(Theme.line).frame(height: 1)
                switch tab {
                case .log: LogView(supervisor: supervisor)
                case .settings: ServiceSettingsForm(service: service)
                }
            }
            .background(Theme.bg)
            .task(id: id) { model.gitRefresh(id, fetchMaxAge: 300) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.gitRefresh(id, fetchMaxAge: nil)
            }
        }
    }

    @ViewBuilder
    private func header(_ service: ServiceConfig, _ supervisor: ServiceSupervisor) -> some View {
        let status = supervisor.status
        Text(model.breadcrumb(of: id))
            .font(.system(size: 12))
            .foregroundStyle(Theme.text3)
            .padding(.bottom, 6)
        HStack(spacing: 10) {
            Text(model.displayName(id))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .layoutPriority(1)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                StatusPill(status: status, text: status.pillLabel(since: supervisor.startedAt, now: context.date))
            }
            .fixedSize()
            if supervisor.isAdopted {
                Text("sahiplenildi")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(Theme.line))
                    .help("Önceki oturumdan devralındı; loglar görünmez.")
            }
            ForEach(status.ports, id: \.self) { port in
                Button("localhost:\(String(port)) ↗") { model.integration.openBrowser(port: port) }
                    .buttonStyle(QuietButtonStyle(height: 22, tint: Theme.text2))
                    .help("Tarayıcıda aç")
            }
            Spacer(minLength: 8)
            Button { model.togglePin(id) } label: {
                Image(systemName: model.isPinned(id) ? "pin.fill" : "pin")
            }
            .buttonStyle(IconButtonStyle())
            .help(model.isPinned(id) ? "Sabitlemeyi kaldır" : "Sabitle")
            if status.isActive {
                Button("Yeniden başlat") { model.restart(id) }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(status == .stopping)
                Button("Durdur") { model.stop(id) }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(status == .stopping)
            } else {
                Button("Başlat") { model.start(id) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut("r")
            }
        }
        Text(ShellWords.join(service.effective.launchCommand))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.text2)
            .lineLimit(2)
            .textSelection(.enabled)
            .padding(.top, 8)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private func banners(_ service: ServiceConfig, _ supervisor: ServiceSupervisor) -> some View {
        if let requirement = model.setupRequirement(id) {
            Banner(text: requirement.message) {
                if requirement.fix != nil {
                    Button(supervisor.isRunningSetup ? "Çalışıyor…" : requirement.fixTitle) { model.runSetup(id) }
                        .buttonStyle(QuietButtonStyle(height: 24))
                        .disabled(supervisor.isRunningSetup)
                }
            }
            .padding(.bottom, 12)
        }
        if service.sourceMissing {
            Banner(text: "Bu servis artık kaynağında (launch.json / package.json) bulunmuyor. Ayarlar sekmesinden kaldırabilirsin.") {
                EmptyView()
            }
            .padding(.bottom, 12)
        }
    }
}

struct StatusPill: View {
    let status: ServiceStatus
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5).monospacedDigit())
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(status.color.opacity(0.1)))
            .overlay(Capsule().strokeBorder(status.color.opacity(0.25)))
    }
}

struct UnderlineTabs: View {
    @Binding var selection: ServiceDetailView.Tab

    var body: some View {
        HStack(spacing: 18) {
            ForEach(ServiceDetailView.Tab.allCases) { tab in
                let selected = tab == selection
                Text(tab.rawValue)
                    .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.text2)
                    .padding(.bottom, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(selected ? Theme.text : .clear).frame(height: 2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = tab }
            }
        }
    }
}

struct Banner<Actions: View>: View {
    let text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.warn)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actions()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.warn.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.warn.opacity(0.25)))
    }
}
