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
        .onAppear { load(service.effective, extraEnv: service.overrides.env ?? [:]) }
    }

    private func load(_ definition: ServiceDefinition, extraEnv: [String: String]) {
        name = definition.name
        command = ShellWords.join(definition.command)
        cwd = definition.cwd
        envFile = definition.envFile ?? ""
        reload = definition.reloadEnabled
        port = definition.portHint.map(String.init) ?? ""
        envText = extraEnv.keys.sorted().map { "\($0)=\(extraEnv[$0] ?? "")" }.joined(separator: "\n")
        saved = false
    }

    private func save() {
        let discovered = service.discovered
        var overrides = ServiceOverrides()
        if name != discovered.name { overrides.name = name }
        let words = ShellWords.split(command)
        if words != discovered.command { overrides.command = words }
        if cwd != discovered.cwd { overrides.cwd = cwd }
        if envFile != (discovered.envFile ?? "") { overrides.envFile = envFile }
        let extra = DotEnvParser.parse(envText)
        if !extra.isEmpty { overrides.env = extra }
        if reload != discovered.reloadEnabled { overrides.reloadEnabled = reload }
        if let value = Int(port), value != discovered.portHint { overrides.portHint = value }
        model.updateOverrides(service.id, overrides)
        saved = true
    }

    private func resetToDiscovered() {
        model.updateOverrides(service.id, ServiceOverrides())
        load(service.discovered, extraEnv: [:])
    }
}
