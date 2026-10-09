import DevLauncherCore
import SwiftUI

/// Edits a service's overrides. Only fields that differ from the discovered definition are stored.
struct ServiceSettingsForm: View {
    @Environment(AppModel.self) private var model
    let service: ServiceConfig

    @State private var name = ""
    @State private var command = ""
    @State private var cwd = ""
    @State private var envFile = ""
    @State private var envText = ""
    @State private var reload = false
    @State private var port = ""
    @State private var saved = false
    @State private var baseline: OverrideEditor.Fields?

    var body: some View {
        Form {
            Section {
                TextField("Ad", text: $name)
                TextField("Komut", text: $command, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
                TextField("Çalışma klasörü", text: $cwd)
                TextField("Port", text: $port, prompt: Text("örn. 8000"))
                if service.discovered.supportsReload {
                    Toggle("Kod değişince yeniden yükle (--reload)", isOn: $reload)
                }
            } header: {
                Text("Genel")
            } footer: {
                Text("Değişiklikler bir sonraki başlatmada geçerli olur.").foregroundStyle(.secondary)
            }
            Section("Ortam değişkenleri") {
                TextField("Env dosyası", text: $envFile, prompt: Text("boş = env dosyası yok"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ek değişkenler (her satıra KEY=VALUE); keşfedilenlerin üzerine yazar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $envText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                }
                if !service.discovered.env.isEmpty {
                    DisclosureGroup("Keşfedilen değişkenler (\(service.discovered.env.count))") {
                        ForEach(service.discovered.env.keys.sorted(), id: \.self) { key in
                            Text("\(key)=\(service.discovered.env[key] ?? "")")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Section {
                HStack {
                    Button("Keşfedilen değerlere dön") { resetToDiscovered() }
                        .disabled(service.overrides.isEmpty)
                    Spacer()
                    if saved { Text("Kaydedildi").foregroundStyle(.secondary) }
                    Button("Kaydet") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                }
            }
            Section {
                Button("Servisi kaldır", role: .destructive) { model.removeService(service.id) }
            }
        }
        .formStyle(.grouped)
        .onAppear { load(OverrideEditor.fields(of: service)) }
    }

    private func load(_ fields: OverrideEditor.Fields) {
        name = fields.name
        command = ShellWords.join(fields.command)
        cwd = fields.cwd
        envFile = fields.envFile
        reload = fields.reloadEnabled
        port = fields.portHint.map(String.init) ?? ""
        envText = fields.extraEnv.keys.sorted().map { "\($0)=\(fields.extraEnv[$0] ?? "")" }.joined(separator: "\n")
        baseline = fields
        saved = false
    }

    private func save() {
        guard let baseline else { return }
        let edited = OverrideEditor.Fields(
            name: name,
            command: ShellWords.split(command),
            cwd: cwd,
            envFile: envFile,
            extraEnv: DotEnvParser.parse(envText),
            reloadEnabled: reload,
            portHint: Int(port)
        )
        model.updateOverrides(service.id, OverrideEditor.apply(edited: edited, baseline: baseline, to: service))
        self.baseline = edited
        saved = true
    }

    private func resetToDiscovered() {
        model.updateOverrides(service.id, ServiceOverrides())
        var reset = service
        reset.overrides = ServiceOverrides()
        load(OverrideEditor.fields(of: reset))
    }
}
