import AppKit
import DevLauncherCore
import SwiftUI

enum SheetRoute: Identifiable {
    case newRepos
    case addRepo(String)
    case suggestions(String)
    case manualService(String)

    var id: String {
        switch self {
        case .newRepos: return "new"
        case .addRepo(let path): return "add:\(path)"
        case .suggestions(let path): return "suggest:\(path)"
        case .manualService(let path): return "manual:\(path)"
        }
    }
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: SheetRoute?

    var body: some View {
        NavigationSplitView {
            Sidebar(sheet: $sheet)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            if let id = model.selection, model.service(id) != nil {
                ServiceDetailView(id: id).id(id)
            } else {
                ContentUnavailableView(
                    "Bir servis seç",
                    systemImage: "bolt.horizontal.circle",
                    description: Text("Soldan bir servis seçerek loglarını ve ayarlarını görebilirsin.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { addRepoFromPanel() } label: { Label("Repo ekle", systemImage: "folder.badge.plus") }
                Button { Task { await model.rescan() } } label: { Label("Yeniden tara", systemImage: "arrow.clockwise") }
                    .disabled(model.isScanning)
                Button { Task { await model.stopAll() } } label: { Label("Tümünü durdur", systemImage: "stop.circle") }
                    .disabled(model.activeCount == 0)
            }
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .newRepos: NewReposSheet()
            case .addRepo(let path): AddRepoSheet(path: path)
            case .suggestions(let path): SuggestionsSheet(path: path)
            case .manualService(let path): ManualServiceSheet(path: path)
            }
        }
    }

    private func addRepoFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ekle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard model.config.repoIndex(path: url.path) == nil else {
            Alerts.info("Repo zaten listede", url.lastPathComponent)
            return
        }
        _ = model.discover(url)
        sheet = .addRepo(url.path)
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var sheet: SheetRoute?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            if !model.newRepoCandidates.isEmpty {
                Button { sheet = .newRepos } label: {
                    Label("\(model.newRepoCandidates.count) yeni repo bulundu", systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
            }
            Section("Sabitlenenler") {
                if model.pinnedIDs.isEmpty {
                    Text("Bir servise sağ tıklayıp “Sabitle” de.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.pinnedIDs, id: \.self) { id in
                    ServiceRow(id: id, showRepo: true).tag(id)
                }
                .onMove { model.movePinned(from: $0, to: $1) }
            }
            ForEach(model.config.repos, id: \.path) { repo in
                Section {
                    ForEach(repo.services.filter { !model.isPinned($0.id) }) { service in
                        ServiceRow(id: service.id).tag(service.id)
                    }
                } header: {
                    RepoHeader(repo: repo, sheet: $sheet)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct RepoHeader: View {
    @Environment(AppModel.self) private var model
    let repo: RepoConfig
    @Binding var sheet: SheetRoute?

    var body: some View {
        HStack {
            Text(repo.name)
            let count = model.suggestions[repo.path]?.count ?? 0
            if count > 0 {
                Button { sheet = .suggestions(repo.path) } label: { Text("\(count) yeni").font(.caption2) }
                    .buttonStyle(.borderless)
                    .help("Keşfedilen yeni servisler")
            }
            Spacer()
            Menu {
                Button("Keşfedilen servisler…") { sheet = .suggestions(repo.path) }
                Button("Manuel servis ekle…") { sheet = .manualService(repo.path) }
                Divider()
                Button("Finder'da göster") { model.integration.reveal(repo.path) }
                Button("Repoyu kaldır", role: .destructive) { model.removeRepo(repo.path) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
