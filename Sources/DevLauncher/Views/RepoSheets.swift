import DevLauncherCore
import SwiftUI

struct ServicePickerList: View {
    let services: [DiscoveredService]
    @Binding var selected: Set<String>

    var body: some View {
        ForEach(services, id: \.id) { service in
            Toggle(isOn: Binding(
                get: { selected.contains(service.id) },
                set: { isOn in
                    if isOn { selected.insert(service.id) } else { selected.remove(service.id) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(service.definition.name)
                        if let port = service.definition.portHint {
                            Text(":\(port)").foregroundStyle(.secondary)
                        }
                    }
                    Text(ShellWords.join(service.definition.launchCommand))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
    }
}

struct SkippedNote: View {
    let discovery: RepoDiscovery?

    var body: some View {
        if let discovery, !(discovery.skipped.isEmpty && discovery.warnings.isEmpty) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(discovery.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if !discovery.skipped.isEmpty {
                    Text("Atlanan konfigürasyonlar: " + discovery.skipped.map { "\($0.name) (\($0.reason))" }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}

struct SheetButtons: View {
    let confirmTitle: String
    var confirmDisabled = false
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button("İptal") { dismiss() }
            Button(confirmTitle) {
                onConfirm()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(confirmDisabled)
        }
    }
}

struct NewReposSheet: View {
    @Environment(AppModel.self) private var model
    @State private var selectedRepos: Set<String> = []
    @State private var selectedServices: Set<String> = []
    @State private var ignoreRest = false

    var body: some View {
        let candidates = model.newRepoCandidates.map(\.path)
        VStack(alignment: .leading, spacing: 12) {
            Text("Yeni repolar").font(.title2.bold())
            Text("Eklemek istediğin repoları ve servislerini seç.").foregroundStyle(.secondary)
            List {
                ForEach(candidates, id: \.self) { path in
                    let services = model.discoveries[path]?.services ?? []
                    Toggle(isOn: Binding(
                        get: { selectedRepos.contains(path) },
                        set: { isOn in
                            if isOn { selectedRepos.insert(path) } else { selectedRepos.remove(path) }
                        }
                    )) {
                        HStack {
                            Text(URL(fileURLWithPath: path).lastPathComponent).bold()
                            Text(services.isEmpty ? "servis bulunamadı" : "\(services.count) servis").foregroundStyle(.secondary)
                        }
                    }
                    if selectedRepos.contains(path), !services.isEmpty {
                        ServicePickerList(services: services, selected: $selectedServices)
                            .padding(.leading, 22)
                    }
                }
            }
            .frame(minHeight: 380)
            Toggle("Seçmediğim repoları bir daha önerme", isOn: $ignoreRest)
            SheetButtons(confirmTitle: "Ekle") { apply(candidates) }
        }
        .padding(20)
        .frame(width: 620)
        .onAppear {
            for path in candidates {
                let services = model.discoveries[path]?.services ?? []
                if !services.isEmpty { selectedRepos.insert(path) }
                selectedServices.formUnion(services.map(\.id))
            }
        }
    }

    private func apply(_ candidates: [String]) {
        for path in candidates where selectedRepos.contains(path) {
            let services = model.discoveries[path]?.services ?? []
            model.addRepo(path, services: services.filter { selectedServices.contains($0.id) })
        }
        if ignoreRest {
            model.ignoreRepos(candidates.filter { !selectedRepos.contains($0) })
        }
    }
}

struct AddRepoSheet: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var selected: Set<String> = []

    var body: some View {
        let discovery = model.discoveries[path]
        let services = discovery?.services ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text(URL(fileURLWithPath: path).lastPathComponent).font(.title2.bold())
            if services.isEmpty {
                Text("Bu klasörde servis bulunamadı. Repoyu ekleyip sonra manuel servis tanımlayabilirsin.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Eklenecek servisleri seç:").foregroundStyle(.secondary)
                List { ServicePickerList(services: services, selected: $selected) }
                    .frame(minHeight: 220)
            }
            SkippedNote(discovery: discovery)
            SheetButtons(confirmTitle: "Repoyu ekle") {
                model.addRepo(path, services: services.filter { selected.contains($0.id) })
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { selected = Set(services.map(\.id)) }
    }
}

struct SuggestionsSheet: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var selected: Set<String> = []

    var body: some View {
        let services = model.unmatched[path] ?? []
        let fresh = Set((model.suggestions[path] ?? []).map(\.id))
        VStack(alignment: .leading, spacing: 12) {
            Text("Keşfedilen servisler · \(URL(fileURLWithPath: path).lastPathComponent)").font(.title2.bold())
            if services.isEmpty {
                Text("Listede olmayan keşfedilmiş servis yok.").foregroundStyle(.secondary)
            } else {
                Text("Seçmediklerin bir daha öneri olarak gösterilmez; bu ekrandan her zaman ekleyebilirsin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List { ServicePickerList(services: services, selected: $selected) }
                    .frame(minHeight: 220)
            }
            SkippedNote(discovery: model.discoveries[path])
            SheetButtons(confirmTitle: "Kaydet") {
                model.acceptSuggestions(path, selected: services.filter { selected.contains($0.id) })
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { selected = fresh }
    }
}

struct ManualServiceSheet: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var name = ""
    @State private var command = ""
    @State private var cwd = ""
    @State private var port = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manuel servis").font(.title2.bold())
            Form {
                TextField("Ad", text: $name, prompt: Text("örn. legacy-ear"))
                TextField("Komut", text: $command, prompt: Text("örn. mvn spring-boot:run"))
                    .font(.system(.body, design: .monospaced))
                TextField("Çalışma klasörü", text: $cwd)
                TextField("Port (opsiyonel)", text: $port)
            }
            SheetButtons(
                confirmTitle: "Ekle",
                confirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty || ShellWords.split(command).isEmpty
            ) {
                model.addManualService(
                    path,
                    definition: ServiceDefinition(name: name, command: ShellWords.split(command), cwd: cwd, portHint: Int(port))
                )
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { cwd = path }
    }
}
