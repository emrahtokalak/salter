import AppKit
import SalterCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                group("Taranan klasörler") {
                    ForEach(model.config.roots, id: \.self) { root in
                        HStack {
                            Text(root)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button { Task { await model.removeRoot(root) } } label: { Image(systemName: "minus") }
                                .buttonStyle(PlainTextButtonStyle(color: Theme.text3))
                                .help("Kaldır")
                        }
                    }
                    Button("Klasör ekle…") { addRoot() }.buttonStyle(QuietButtonStyle(height: 24))
                }
                group("Genel") {
                    Toggle("Login'de başlat", isOn: Binding(
                        get: { model.integration.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    Toggle("Servis çökünce bildirim gönder", isOn: Binding(
                        get: { model.config.settings.crashNotifications },
                        set: { model.setCrashNotifications($0) }
                    ))
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                group("Shell ortamı") {
                    if let shell = model.shell {
                        if let error = shell.error {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                                Text(error).foregroundStyle(Theme.text2)
                            }
                            .font(.system(size: 12))
                        } else {
                            Text("PATH: " + (shell.variables["PATH"] ?? ""))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.text2)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Button("Yeniden yükle") { Task { await model.reloadShell() } }.buttonStyle(QuietButtonStyle(height: 24))
                }
                group("Dosyalar") {
                    HStack(spacing: 8) {
                        Button("Ayar dosyasını göster") {
                            model.integration.reveal(ConfigStore.defaultDirectory.appendingPathComponent("config.json").path)
                        }
                        Button("Log klasörünü göster") { model.integration.reveal(LogFileWriter.defaultDirectory.path) }
                    }
                    .buttonStyle(QuietButtonStyle(height: 24))
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .frame(width: 520, height: 520)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            Card {
                VStack(alignment: .leading, spacing: 10) { content() }
            }
        }
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Ekle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.addRoot(url.path) }
    }
}
