import SalterCore
import SwiftUI

struct ServicePickerList: View {
    let services: [DiscoveredService]
    let repoName: String
    @Binding var selected: Set<String>

    var body: some View {
        let names = ServiceNaming.discoveredNames(services, repoName: repoName)
        ForEach(services, id: \.id) { service in
            Toggle(isOn: Binding(
                get: { selected.contains(service.id) },
                set: { isOn in
                    if isOn { selected.insert(service.id) } else { selected.remove(service.id) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(names[service.id] ?? repoName).font(.system(size: 13)).foregroundStyle(Theme.text)
                        if let port = service.definition.portHint {
                            Text(":\(String(port))").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text3)
                        }
                    }
                    Text(ShellWords.join(service.definition.launchCommand))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.vertical, 3)
        }
    }
}

struct SkippedNote: View {
    let discovery: RepoDiscovery?

    var body: some View {
        if let discovery, !(discovery.skipped.isEmpty && discovery.warnings.isEmpty) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(discovery.warnings, id: \.self) { warning in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                        Text(warning).foregroundStyle(Theme.text2)
                    }
                }
                if !discovery.skipped.isEmpty {
                    Text("Atlanan konfigürasyonlar: " + discovery.skipped.map { "\(ServiceNaming.label($0.name)) (\($0.reason))" }.joined(separator: ", "))
                        .foregroundStyle(Theme.text3)
                }
            }
            .font(.system(size: 11.5))
        }
    }
}

struct SheetButtons: View {
    let confirmTitle: String
    var confirmDisabled = false
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("İptal") { dismiss() }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button(confirmTitle) {
                onConfirm()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(confirmDisabled)
        }
    }
}

/// Title, subtitle and body in the shared sheet chrome.
struct SheetChrome<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            content()
        }
        .padding(20)
        .background(Theme.bg)
    }
}

/// Bordered scrolling list area used inside sheets.
struct SheetList<Content: View>: View {
    var minHeight: CGFloat = 220
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) { content() }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: minHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
    }
}

struct NewReposSheet: View {
    @Environment(AppModel.self) private var model
    @State private var selectedRepos: Set<String> = []
    @State private var selectedServices: Set<String> = []
    @State private var ignoreRest = false

    var body: some View {
        let candidates = model.newRepoCandidates.map(\.path)
        SheetChrome(title: "Yeni repolar", subtitle: "Eklemek istediğin repoları ve servislerini seç.") {
            SheetList(minHeight: 380) {
                ForEach(candidates, id: \.self) { path in
                    let services = model.discoveries[path]?.services ?? []
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    Toggle(isOn: Binding(
                        get: { selectedRepos.contains(path) },
                        set: { isOn in
                            if isOn { selectedRepos.insert(path) } else { selectedRepos.remove(path) }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                            Text(services.isEmpty ? "servis bulunamadı" : "\(services.count) servis")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text3)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, 3)
                    if selectedRepos.contains(path), !services.isEmpty {
                        ServicePickerList(services: services, repoName: name, selected: $selectedServices)
                            .padding(.leading, 22)
                    }
                }
            }
            Toggle("Seçmediğim repoları bir daha önerme", isOn: $ignoreRest)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
            SheetButtons(confirmTitle: "Ekle") { apply(candidates) }
        }
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
        let name = URL(fileURLWithPath: path).lastPathComponent
        SheetChrome(
            title: name,
            subtitle: services.isEmpty
                ? "Bu klasörde servis bulunamadı. Repoyu ekleyip sonra manuel servis tanımlayabilirsin."
                : "Eklenecek servisleri seç."
        ) {
            if !services.isEmpty {
                SheetList { ServicePickerList(services: services, repoName: name, selected: $selected) }
            }
            SkippedNote(discovery: discovery)
            SheetButtons(confirmTitle: "Repoyu ekle") {
                model.addRepo(path, services: services.filter { selected.contains($0.id) })
            }
        }
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
        let name = URL(fileURLWithPath: path).lastPathComponent
        SheetChrome(
            title: "Keşfedilen servisler · \(model.repoTitle(path))",
            subtitle: services.isEmpty
                ? "Listede olmayan keşfedilmiş servis yok."
                : "Seçmediklerin bir daha öneri olarak gösterilmez; bu ekrandan her zaman ekleyebilirsin."
        ) {
            if !services.isEmpty {
                SheetList { ServicePickerList(services: services, repoName: name, selected: $selected) }
            }
            SkippedNote(discovery: model.discoveries[path])
            SheetButtons(confirmTitle: "Kaydet") {
                model.acceptSuggestions(path, selected: services.filter { selected.contains($0.id) })
            }
        }
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
        SheetChrome(title: "Manuel servis", subtitle: model.repoTitle(path)) {
            VStack(alignment: .leading, spacing: 10) {
                field("Ad") { TextField("", text: $name, prompt: Text("örn. legacy-ear")).fieldStyle() }
                field("Komut") {
                    TextField("", text: $command, prompt: Text("örn. mvn spring-boot:run")).fieldStyle(monospaced: true)
                }
                field("Çalışma klasörü") { TextField("", text: $cwd).fieldStyle() }
                field("Port (opsiyonel)") { TextField("", text: $port).fieldStyle().frame(maxWidth: 120) }
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
        .frame(width: 480)
        .onAppear { cwd = path }
    }

    private func field<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 110, alignment: .leading)
            control()
        }
    }
}
