import AppKit
import DevLauncherCore
import Observation
import SwiftUI

/// App-wide state: configuration, one supervisor per service, discovery results and port polling.
@MainActor @Observable
final class AppModel {
    private(set) var config: AppConfig
    private(set) var shell: ShellEnvironment?
    private(set) var supervisors: [String: ServiceSupervisor] = [:]
    private(set) var discoveries: [String: RepoDiscovery] = [:]
    private(set) var suggestions: [String: [DiscoveredService]] = [:]
    private(set) var unmatched: [String: [DiscoveredService]] = [:]
    private(set) var newRepoCandidates: [URL] = []
    private(set) var isScanning = false
    var selection: String?

    @ObservationIgnored let integration = SystemIntegration()
    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let runtimeStore: RuntimeStateStore
    @ObservationIgnored private var configWarning: String?
    @ObservationIgnored private var pendingOrphans: [RuntimeRecord] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastSlowPoll = Date.distantPast
    @ObservationIgnored private var didBootstrap = false

    init(directory: URL = ConfigStore.defaultDirectory) {
        configStore = ConfigStore(directory: directory)
        runtimeStore = RuntimeStateStore(directory: directory)
        let loaded = configStore.load()
        config = loaded.config
        configWarning = loaded.warning
        ensureSupervisors()
    }

    // MARK: Lifecycle

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        if let configWarning { Alerts.info("Ayarlar sıfırlandı", configWarning) }
        await reloadShell()
        await rescan()
        let orphans = RuntimeStateStore.liveOrphans(runtimeStore.load())
            .filter { supervisors[$0.serviceID] != nil }
        if !orphans.isEmpty {
            pendingOrphans = orphans
            let names = orphans.map { displayName($0.serviceID) }.joined(separator: ", ")
            let adopt = Alerts.confirm(
                "\(orphans.count) servis önceki oturumdan çalışıyor",
                "\(names)\n\nSahiplenirsen durumlarını izleyip durdurabilirsin, ancak loglarını göremezsin.",
                confirm: "Sahiplen",
                cancel: "Durdur"
            )
            resolveOrphans(adopt: adopt)
        }
        startPolling()
    }

    func reloadShell() async {
        shell = await Task.detached { ShellEnvironment.capture() }.value
    }

    private func resolveOrphans(adopt: Bool) {
        let records = pendingOrphans
        pendingOrphans = []
        for record in records {
            if adopt {
                supervisors[record.serviceID]?.adopt(record)
            } else if !RuntimeStateStore.liveOrphans([record]).isEmpty {
                // Re-checked after the prompt: the pid may have been reused while it was open.
                let pgid = record.pgid
                Task.detached { await ProcessRunner.terminateGroup(pgid) }
            }
        }
        persistRuntimeState()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.pollPorts()
            }
        }
    }

    /// Every 2 s while something is starting, otherwise every 10 s.
    private func pollPorts() async {
        let active = supervisors.values.filter { $0.pgid != nil }
        guard !active.isEmpty else { return }
        let starting = active.contains { $0.status == .starting }
        guard starting || Date().timeIntervalSince(lastSlowPoll) >= 10 else { return }
        lastSlowPoll = Date()
        let snapshot = await Task.detached { PortProbe.snapshot() }.value
        for supervisor in active { supervisor.refresh(with: snapshot) }
    }

    private func ensureSupervisors() {
        for service in config.repos.flatMap(\.services) where supervisors[service.id] == nil {
            let supervisor = ServiceSupervisor(
                id: service.id,
                fileLog: LogFileWriter(url: LogFileWriter.url(forService: service.id))
            )
            supervisor.onStatusChange = { [weak self] in self?.statusChanged($0) }
            supervisors[service.id] = supervisor
        }
    }

    private func statusChanged(_ supervisor: ServiceSupervisor) {
        persistRuntimeState()
        if case .crashed(let exit) = supervisor.status, config.settings.crashNotifications {
            integration.notifyCrash(service: displayName(supervisor.id), detail: exit.description)
        }
    }

    private func persistRuntimeState() {
        runtimeStore.save(supervisors.values.compactMap(\.runtimeRecord) + pendingOrphans)
    }

    // MARK: Lookups

    func service(_ id: String) -> ServiceConfig? { config.service(id: id) }
    func displayName(_ id: String) -> String { service(id)?.effective.name ?? id }
    func repoName(of id: String) -> String { config.repo(containing: id)?.name ?? "" }
    func status(_ id: String) -> ServiceStatus { supervisors[id]?.status ?? .stopped }
    var activeCount: Int { supervisors.values.filter { $0.status.isActive }.count }
    var hasCrash: Bool { supervisors.values.contains { $0.status.isCrashed } }
    var pinnedIDs: [String] { config.pinnedOrder.filter { service($0) != nil } }
    func isPinned(_ id: String) -> Bool { config.pinnedOrder.contains(id) }

    func setupRequirement(_ id: String) -> SetupRequirement? {
        guard let service = service(id), let shell else { return nil }
        return LaunchPlanner.setupRequirement(for: service.effective, searchPath: shell.variables["PATH"])
    }

    // MARK: Service actions

    func start(_ id: String, force: Bool = false) {
        guard let service = service(id), let supervisor = supervisors[id], !supervisor.status.isActive else { return }
        guard let shell else {
            Alerts.info("Henüz hazır değil", "Shell ortamı yükleniyor, birkaç saniye sonra tekrar dene.")
            return
        }
        let definition = service.effective
        guard !force, let port = definition.portHint else {
            launch(definition, on: supervisor, shell: shell)
            return
        }
        Task {
            let snapshot = await Task.detached { PortProbe.snapshot() }.value
            if let owner = PortProbe.owners(ofPort: port, in: snapshot).first {
                let proceed = Alerts.confirm(
                    "\(port) portu kullanımda",
                    "\(describe(owner)) bu portu dinliyor. Yine de başlatılsın mı?",
                    confirm: "Yine de başlat",
                    cancel: "İptal"
                )
                guard proceed else { return }
            }
            launch(definition, on: supervisor, shell: shell)
        }
    }

    private func launch(_ definition: ServiceDefinition, on supervisor: ServiceSupervisor, shell: ShellEnvironment) {
        let plan: LaunchPlan
        do {
            plan = try LaunchPlanner.plan(definition, shell: shell.variables)
        } catch {
            supervisor.appendSystem(["❌ başlatılamadı: \(error)"])
            Alerts.info("\(definition.name) başlatılamadı", "\(error)")
            return
        }
        do {
            try supervisor.start(plan, expectsPort: definition.portHint != nil)
        } catch {
            Alerts.info("\(definition.name) başlatılamadı", "\(error)")
        }
    }

    private func describe(_ owner: ListeningSocket) -> String {
        if let supervisor = supervisors.values.first(where: { $0.pgid == owner.pgid }) {
            return displayName(supervisor.id)
        }
        return "\(owner.command) (pid \(owner.pid))"
    }

    func stop(_ id: String) {
        guard let supervisor = supervisors[id] else { return }
        Task { await supervisor.stop() }
    }

    func restart(_ id: String) {
        guard let supervisor = supervisors[id] else { return }
        Task {
            await supervisor.stop()
            for _ in 0..<60 where supervisor.status.isActive {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            start(id, force: true)
        }
    }

    func stopAll() async {
        let active = supervisors.values.filter { $0.status.isActive }
        await withTaskGroup(of: Void.self) { group in
            for supervisor in active {
                group.addTask { await supervisor.stop() }
            }
        }
        for _ in 0..<120 where activeCount > 0 {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func runSetup(_ id: String) {
        guard let requirement = setupRequirement(id), let shell, let supervisor = supervisors[id] else { return }
        do {
            guard let request = try LaunchPlanner.setupRequest(requirement, shell: shell.variables) else { return }
            try supervisor.runSetup(request)
        } catch {
            Alerts.info("Kurulum başlatılamadı", "\(error)")
        }
    }

    // MARK: Config edits

    func togglePin(_ id: String) {
        mutate { config in
            if let index = config.pinnedOrder.firstIndex(of: id) {
                config.pinnedOrder.remove(at: index)
            } else {
                config.pinnedOrder.append(id)
            }
        }
    }

    func movePinned(from source: IndexSet, to destination: Int) {
        var ids = pinnedIDs
        ids.move(fromOffsets: source, toOffset: destination)
        mutate { $0.pinnedOrder = ids }
    }

    func updateOverrides(_ id: String, _ overrides: ServiceOverrides) {
        mutate { config in
            for r in config.repos.indices {
                if let s = config.repos[r].services.firstIndex(where: { $0.id == id }) {
                    config.repos[r].services[s].overrides = overrides
                }
            }
        }
    }

    func removeService(_ id: String) {
        guard supervisors[id]?.status.isActive != true else {
            Alerts.info("Servis çalışıyor", "Kaldırmadan önce servisi durdur.")
            return
        }
        mutate { config in
            for r in config.repos.indices {
                guard let removed = config.repos[r].services.first(where: { $0.id == id }) else { continue }
                config.repos[r].services.removeAll { $0.id == id }
                if removed.source.kind != .manual, !config.repos[r].declinedSources.contains(removed.source) {
                    config.repos[r].declinedSources.append(removed.source)
                }
            }
            config.pinnedOrder.removeAll { $0 == id }
        }
        supervisors[id] = nil
        if selection == id { selection = nil }
        refreshSuggestions()
    }

    // MARK: Repos

    func rescan() async {
        isScanning = true
        defer { isScanning = false }
        let roots = config.roots.map { URL(fileURLWithPath: $0) }
        let known = config.repos.map(\.path)
        let ignored = Set(config.ignoredRepos)
        let (candidates, found) = await Task.detached { () -> ([URL], [String: RepoDiscovery]) in
            let knownSet = Set(known)
            let candidates = roots
                .flatMap { RepoScanner.candidateRepos(in: $0) }
                .filter { !knownSet.contains($0.path) && !ignored.contains($0.path) }
            var found: [String: RepoDiscovery] = [:]
            for path in known + candidates.map(\.path) {
                found[path] = RepoScanner.discover(repo: URL(fileURLWithPath: path))
            }
            return (candidates, found)
        }.value
        newRepoCandidates = candidates
        discoveries = found
        mutate { config in
            for index in config.repos.indices {
                if let discovery = found[config.repos[index].path] {
                    config.repos[index] = ConfigMerger.merge(discovery, into: config.repos[index]).repo
                }
            }
        }
        refreshSuggestions()
    }

    func discover(_ url: URL) -> RepoDiscovery {
        let discovery = RepoScanner.discover(repo: url)
        discoveries[url.path] = discovery
        return discovery
    }

    func addRepo(_ path: String, services selected: [DiscoveredService]) {
        guard config.repoIndex(path: path) == nil else { return }
        let offered = discoveries[path]?.services ?? []
        mutate { config in
            let repo = ConfigMerger.accept(selected, offered: offered, into: RepoConfig(path: path), takenIDs: config.allServiceIDs)
            config.repos.append(repo)
            config.repos.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            config.ignoredRepos.removeAll { $0 == path }
        }
        newRepoCandidates.removeAll { $0.path == path }
        refreshSuggestions()
    }

    func ignoreRepos(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        mutate { config in
            for path in paths where !config.ignoredRepos.contains(path) { config.ignoredRepos.append(path) }
        }
        newRepoCandidates.removeAll { paths.contains($0.path) }
    }

    func removeRepo(_ path: String) {
        guard let repo = config.repos.first(where: { $0.path == path }) else { return }
        if repo.services.contains(where: { supervisors[$0.id]?.status.isActive == true }) {
            Alerts.info("Repo'da çalışan servis var", "Kaldırmadan önce servisleri durdur.")
            return
        }
        let ids = Set(repo.services.map(\.id))
        mutate { config in
            config.repos.removeAll { $0.path == path }
            config.pinnedOrder.removeAll { ids.contains($0) }
        }
        for id in ids { supervisors[id] = nil }
        if let selection, ids.contains(selection) { self.selection = nil }
        refreshSuggestions()
    }

    func acceptSuggestions(_ path: String, selected: [DiscoveredService]) {
        guard let index = config.repoIndex(path: path) else { return }
        let offered = unmatched[path] ?? []
        mutate { config in
            config.repos[index] = ConfigMerger.accept(selected, offered: offered, into: config.repos[index], takenIDs: config.allServiceIDs)
        }
        refreshSuggestions()
    }

    func addManualService(_ path: String, definition: ServiceDefinition) {
        guard let index = config.repoIndex(path: path) else { return }
        mutate { config in
            let base = "\(config.repos[index].name)/\(Slug.make(definition.name))"
            let id = Slug.unique(base, taken: config.allServiceIDs)
            config.repos[index].services.append(ServiceConfig(id: id, source: .manual, discovered: definition))
        }
    }

    private func refreshSuggestions() {
        var newSuggestions: [String: [DiscoveredService]] = [:]
        var newUnmatched: [String: [DiscoveredService]] = [:]
        for repo in config.repos {
            guard let discovery = discoveries[repo.path] else { continue }
            let outcome = ConfigMerger.merge(discovery, into: repo)
            newSuggestions[repo.path] = outcome.suggestions
            newUnmatched[repo.path] = outcome.unmatched
        }
        suggestions = newSuggestions
        unmatched = newUnmatched
    }

    // MARK: Settings

    func addRoot(_ path: String) async {
        mutate { if !$0.roots.contains(path) { $0.roots.append(path) } }
        await rescan()
    }

    func removeRoot(_ path: String) async {
        mutate { $0.roots.removeAll { $0 == path } }
        await rescan()
    }

    func setCrashNotifications(_ enabled: Bool) {
        mutate { $0.settings.crashNotifications = enabled }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try integration.setLaunchAtLogin(enabled)
            mutate { $0.settings.launchAtLogin = enabled }
        } catch {
            Alerts.info("Login ayarı değiştirilemedi", error.localizedDescription)
        }
    }

    private func mutate(_ change: (inout AppConfig) -> Void) {
        change(&config)
        do {
            try configStore.save(config)
        } catch {
            Alerts.info("Ayarlar kaydedilemedi", error.localizedDescription)
        }
        ensureSupervisors()
    }
}
