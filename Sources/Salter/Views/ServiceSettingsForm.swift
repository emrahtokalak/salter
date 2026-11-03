import SalterCore
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
    @State private var showDiscoveredEnv = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                group("Genel") {
                    row("Ad", note: "Takma ad; boş bırakırsan varsayılan ad kullanılır.") {
                        TextField("", text: $name, prompt: Text(defaultName)).fieldStyle()
                    }
                    row("Komut") {
                        TextField("", text: $command, axis: .vertical).lineLimit(1...4).fieldStyle(monospaced: true)
                    }
                    row("Çalışma klasörü") { TextField("", text: $cwd).fieldStyle() }
                    row("Port") { TextField("", text: $port, prompt: Text("örn. 8000")).fieldStyle().frame(maxWidth: 120) }
                    if service.discovered.supportsReload {
                        row("Yeniden yükleme") {
                            Toggle("Kod değişince yeniden yükle (--reload)", isOn: $reload)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                group("Ortam değişkenleri") {
                    row("Env dosyası") {
                        TextField("", text: $envFile, prompt: Text("boş = env dosyası yok")).fieldStyle()
                    }
                    row("Ek değişkenler", note: "Her satıra KEY=VALUE; keşfedilenlerin üzerine yazar.") {
                        TextEditor(text: $envText)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .frame(minHeight: 80)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
                    }
                    if !service.discovered.env.isEmpty {
                        row("Keşfedilenler") {
                            DisclosureGroup("\(service.discovered.env.count) değişken", isExpanded: $showDiscoveredEnv) {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(service.discovered.env.keys.sorted(), id: \.self) { key in
                                        Text("\(key)=\(service.discovered.env[key] ?? "")")
                                            .font(.system(size: 11.5, design: .monospaced))
                                            .foregroundStyle(Theme.text2)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.text2)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button("Keşfedilen değerlere dön") { resetToDiscovered() }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(service.overrides.isEmpty)
                        Spacer()
                        if saved { Text("Kaydedildi").font(.system(size: 12)).foregroundStyle(Theme.text3) }
                        Button("Kaydet") { save() }
                            .buttonStyle(PrimaryButtonStyle())
                            .keyboardShortcut("s")
                    }
                    Text("Değişiklikler bir sonraki başlatmada geçerli olur.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Tehlikeli bölge")
                    HStack {
                        Text("Servisi listeden kaldırır; yeniden taramada öneri olarak gelmez.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text2)
                        Spacer()
                        Button("Servisi kaldır") { model.removeService(service.id) }
                            .buttonStyle(QuietButtonStyle(tint: Theme.err))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.err.opacity(0.35)))
                }
            }
            .padding(22)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .onAppear { load(OverrideEditor.fields(of: service)) }
    }

    private var defaultName: String {
        var plain = model.config
        for r in plain.repos.indices {
            for s in plain.repos[r].services.indices where plain.repos[r].services[s].id == service.id {
                plain.repos[r].services[s].overrides.name = nil
            }
        }
        return DisplayNames(config: plain).services[service.id]?.full ?? ""
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            Card {
                VStack(alignment: .leading, spacing: 12) { content() }
            }
        }
    }

    private func row<Control: View>(_ label: String, note: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .frame(width: 140, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                control()
                if let note {
                    Text(note).font(.system(size: 11)).foregroundStyle(Theme.text3)
                }
            }
        }
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
