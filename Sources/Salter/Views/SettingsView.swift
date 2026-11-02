import AppKit
import SalterCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Taranan klasörler") {
                ForEach(model.config.roots, id: \.self) { root in
                    HStack {
                        Text(root).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { Task { await model.removeRoot(root) } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Klasör ekle…") { addRoot() }
            }
            Section("Genel") {
                Toggle("Login'de başlat", isOn: Binding(
                    get: { model.integration.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Servis çökünce bildirim gönder", isOn: Binding(
                    get: { model.config.settings.crashNotifications },
                    set: { model.setCrashNotifications($0) }
                ))
            }
            Section("Shell ortamı") {
                if let shell = model.shell {
                    if let error = shell.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else {
                        Text("PATH: " + (shell.variables["PATH"] ?? ""))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
                Button("Yeniden yükle") { Task { await model.reloadShell() } }
            }
            Section("Dosyalar") {
                Button("Ayar dosyasını göster") {
                    model.integration.reveal(ConfigStore.defaultDirectory.appendingPathComponent("config.json").path)
                }
                Button("Log klasörünü göster") { model.integration.reveal(LogFileWriter.defaultDirectory.path) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
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
