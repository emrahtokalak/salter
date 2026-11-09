import AppKit
import SalterCore
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
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            Group {
                if let id = model.selection, model.service(id) != nil {
                    ServiceDetailView(id: id).id(id)
                } else {
                    VStack(spacing: 6) {
                        Text("Bir servis seç").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
                        Text("Soldan bir servis seçerek loglarını ve ayarlarını görebilirsin.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.bg)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.startPinned() } label: { Label("Sabitlenenleri başlat", systemImage: "play.circle") }
                    .help("Sabitlenenleri başlat")
                    .disabled(model.startablePinnedIDs.isEmpty)
                Button { Task { await model.stopAll() } } label: { Label("Tümünü durdur", systemImage: "stop.circle") }
                    .help("Tümünü durdur")
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
}

@MainActor
enum RepoActions {
    static func addFromPanel(_ model: AppModel, sheet: Binding<SheetRoute?>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Repoyu ekle"
        panel.message = "Tek bir projenin klasörünü seç (içinde launch.json, package.json, go.mod … olan klasör)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard model.config.repoIndex(path: url.path) == nil else {
            Alerts.info("Repo zaten listede", url.lastPathComponent)
            return
        }
        _ = model.discover(url)
        sheet.wrappedValue = .addRepo(url.path)
    }

    /// Adds a parent folder whose subfolders are scanned for projects.
    static func addRootFromPanel(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Taranacak klasör olarak ekle"
        panel.message = "Projelerinin bulunduğu üst klasörü seç (örn. ~/Projects). Şalter altındaki projeleri bulup sana sunar."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !model.config.roots.contains(url.path) else {
            Alerts.info("Klasör zaten taranıyor", url.path)
            return
        }
        Task { await model.addRoot(url.path) }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var sheet: SheetRoute?
    @State private var collapsed: Set<String> = []
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                sectionHeader("Sabitlenenler")
                if model.pinnedIDs.isEmpty {
                    Text("Bir servise sağ tıklayıp “Sabitle” de.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                ForEach(model.pinnedIDs, id: \.self) { id in
                    SidebarRow(id: id, title: model.displayName(id), onRename: rename)
                        .draggable(id)
                        .dropDestination(for: String.self) { items, _ in movePinned(items.first, before: id) }
                }
                HStack(spacing: 0) {
                    sectionHeader("Repolar")
                    Spacer()
                    Group {
                        Button { Task { await model.rescan() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .rotationEffect(.degrees(model.isScanning ? 360 : 0))
                                .animation(
                                    model.isScanning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                                    value: model.isScanning
                                )
                        }
                        .buttonStyle(PlainTextButtonStyle(color: Theme.text3))
                        .disabled(model.isScanning)
                        .help("Yeniden tara")
                        Menu {
                            Button("Repo ekle…") { RepoActions.addFromPanel(model, sheet: $sheet) }
                            Button("Taranacak klasör ekle…") { RepoActions.addRootFromPanel(model) }
                            Divider()
                            SettingsLink { Text("Taranan klasörler…") }
                        } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 6)
                        .help("Repo ya da taranacak klasör ekle")
                    }
                    .padding(.top, 8)
                }
                ForEach(model.config.repos, id: \.path) { repo in
                    repoEntry(repo)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Theme.panel)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let release = model.updates.available {
                    UpdateBanner(release: release).padding(.horizontal, 8).padding(.top, 8)
                }
                newReposCard
            }
            .background(Theme.panel)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(-1) }
        .onKeyPress(.downArrow) { moveSelection(1) }
        .alert("Yeniden adlandır", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Ad", text: $renameText, prompt: Text(renaming.map { model.displayName($0) } ?? ""))
            Button("Kaydet") {
                if let renaming, renameText != (model.service(renaming)?.overrides.name ?? "") {
                    model.setAlias(renaming, renameText)
                }
                renaming = nil
            }
            Button("İptal", role: .cancel) { renaming = nil }
        } message: {
            Text("Boş bırakırsan varsayılan ad kullanılır.")
        }
    }

    // MARK: Pieces

    private func sectionHeader(_ title: String) -> some View {
        SectionLabel(title)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func repoEntry(_ repo: RepoConfig) -> some View {
        let visible = repo.services.filter { !model.isPinned($0.id) }
        if repo.services.count == 1, let only = visible.first {
            SidebarRow(id: only.id, title: model.displayName(only.id), suggestions: repo.path, sheet: $sheet, onRename: rename) {
                Divider()
                RepoMenu(repo: repo, sheet: $sheet)
            }
        } else {
            RepoGroupRow(
                repo: repo,
                title: model.repoTitle(repo.path),
                expanded: !collapsed.contains(repo.path),
                hasChildren: !visible.isEmpty,
                sheet: $sheet
            ) {
                if collapsed.contains(repo.path) { collapsed.remove(repo.path) } else { collapsed.insert(repo.path) }
            }
            if !collapsed.contains(repo.path) {
                ForEach(visible) { service in
                    SidebarRow(id: service.id, title: model.inGroupName(service.id), indent: true, onRename: rename)
                }
            }
        }
    }

    @ViewBuilder
    private var newReposCard: some View {
        let count = model.newRepoCandidates.count
        if count > 0 {
            Button { sheet = .newRepos } label: {
                HStack {
                    Text("\(Text("\(count)").foregroundStyle(Theme.text).fontWeight(.medium)) yeni repo bulundu")
                    Spacer()
                    Text("İncele →")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(Theme.panel)
        }
    }

    // MARK: Actions

    private func rename(_ id: String) {
        renameText = model.service(id)?.overrides.name ?? ""
        renaming = id
    }

    private func movePinned(_ dragged: String?, before target: String) -> Bool {
        let ids = model.pinnedIDs
        guard let dragged, let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target), from != to else {
            return false
        }
        model.movePinned(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
        return true
    }

    /// Selectable rows in display order, for arrow-key navigation.
    private var visibleIDs: [String] {
        var ids = model.pinnedIDs
        for repo in model.config.repos {
            let visible = repo.services.filter { !model.isPinned($0.id) }.map(\.id)
            if repo.services.count == 1 || !collapsed.contains(repo.path) { ids += visible }
        }
        return ids
    }

    private func moveSelection(_ step: Int) -> KeyPress.Result {
        let ids = visibleIDs
        guard !ids.isEmpty else { return .ignored }
        guard let current = model.selection, let index = ids.firstIndex(of: current) else {
            model.selection = step > 0 ? ids.first : ids.last
            return .handled
        }
        model.selection = ids[max(0, min(ids.count - 1, index + step))]
        return .handled
    }
}

struct RepoGroupRow: View {
    @Environment(AppModel.self) private var model
    let repo: RepoConfig
    let title: String
    let expanded: Bool
    /// False when every service is pinned (or there are none); the row then only carries the repo menu.
    let hasChildren: Bool
    @Binding var sheet: SheetRoute?
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.text3)
                .frame(width: 12)
                .opacity(hasChildren ? 1 : 0)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
            let count = model.suggestions[repo.path]?.count ?? 0
            if count > 0 {
                Button("\(count) yeni") { sheet = .suggestions(repo.path) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                    .help("Keşfedilen yeni servisler")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.selection.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if hasChildren { toggle() } }
        .onHover { hovering = $0 }
        .contextMenu { RepoMenu(repo: repo, sheet: $sheet) }
    }
}

struct RepoMenu: View {
    @Environment(AppModel.self) private var model
    let repo: RepoConfig
    @Binding var sheet: SheetRoute?

    var body: some View {
        Button("Keşfedilen servisler…") { sheet = .suggestions(repo.path) }
        Button("Manuel servis ekle…") { sheet = .manualService(repo.path) }
        Divider()
        Button("Finder'da göster") { model.integration.reveal(repo.path) }
        Button("Repoyu kaldır", role: .destructive) { model.removeRepo(repo.path) }
    }
}
