import AppKit
import SalterCore
import SwiftUI

/// Branch, sync state, local changes and pull for the service's repo. Hidden outside git repos.
struct GitRow: View {
    @Environment(AppModel.self) private var model
    let serviceID: String
    @State private var showPicker = false
    @State private var showDetail = false

    var body: some View {
        if let tree = model.gitTree(serviceID) {
            let status = tree.status
            HStack(spacing: 10) {
                Button { showPicker = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
                        if let status, let branch = status.branch {
                            Text(branch).lineLimit(1).truncationMode(.middle)
                        } else if let commit = status?.commit {
                            Text(commit).font(.system(size: 12, design: .monospaced))
                            Text("ayrık HEAD").foregroundStyle(Theme.text3)
                        } else {
                            Text("—")
                        }
                    }
                    .frame(maxWidth: 260)
                }
                .buttonStyle(QuietButtonStyle(height: 24))
                .disabled(tree.busy)
                .help("Branch değiştir")
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    BranchPicker(serviceID: serviceID) { showPicker = false }
                        .environment(model)
                }

                if let status {
                    Text(syncText(status))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.text3)
                        .help(tree.lastFetch.map { "son kontrol \(ResourceFormat.duration(Date().timeIntervalSince($0))) önce" } ?? "henüz kontrol edilmedi")
                    if !status.changedFiles.isEmpty {
                        Text("● \(status.changedFiles.count) değişiklik")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.warn)
                            .help(Self.fileList(status.changedFiles))
                    }
                }

                Button { model.gitPull(serviceID) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down").font(.system(size: 10, weight: .semibold))
                        Text("Çek")
                    }
                }
                .buttonStyle(QuietButtonStyle(height: 24))
                .disabled(tree.busy || status?.upstream == nil || status?.isDetached != false)
                .help(status?.upstream.map { "\($0) üzerinden çek (yalnızca ileri sarma)" } ?? "Bu branch'in upstream'i yok")

                if tree.busy || tree.fetching {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                }
                if let message = tree.message {
                    messageView(message)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)
        }
    }

    private func syncText(_ status: GitStatus) -> String {
        guard status.upstream != nil else { return "upstream yok" }
        if status.ahead == 0 && status.behind == 0 { return "güncel" }
        var parts: [String] = []
        if status.behind > 0 { parts.append("↓\(status.behind)") }
        if status.ahead > 0 { parts.append("↑\(status.ahead)") }
        return parts.joined(separator: " ")
    }

    static func fileList(_ files: [String]) -> String {
        let shown = files.prefix(10).joined(separator: "\n")
        return files.count > 10 ? shown + "\n… +\(files.count - 10)" : shown
    }

    @ViewBuilder
    private func messageView(_ message: GitModel.Message) -> some View {
        HStack(spacing: 6) {
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(message.isError ? Theme.err : Theme.text2)
                .lineLimit(2)
                .textSelection(.enabled)
            if let detail = message.detail {
                Button("Ayrıntı") { showDetail = true }
                    .buttonStyle(PlainTextButtonStyle(color: Theme.text3))
                    .popover(isPresented: $showDetail) {
                        ScrollView {
                            Text(detail)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.text2)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: 420, height: 180)
                        .background(Theme.bg)
                    }
            }
            if message.isError, let path = model.repoPath(of: serviceID) {
                Button { model.git.dismissMessage(repoPath: path) } label: { Image(systemName: "xmark") }
                    .buttonStyle(PlainTextButtonStyle(color: Theme.text3))
                    .help("Kapat")
            }
        }
    }
}

/// Searchable list of local and remote-only branches.
struct BranchPicker: View {
    @Environment(AppModel.self) private var model
    let serviceID: String
    let close: () -> Void
    @State private var query = ""

    var body: some View {
        let tree = model.gitTree(serviceID)
        let status = tree?.status
        let dirty = status?.changedFiles ?? []
        let branches = tree?.branches ?? GitBranchList()
        let local = branches.local.filter(matches)
        let remote = branches.remoteOnly.filter { matches($0.name) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.text3)
                TextField("Branch ara…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if tree?.fetching == true {
                    ProgressView().controlSize(.small).scaleEffect(0.7).help("Uzak branch'ler alınıyor…")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            Rectangle().fill(Theme.line).frame(height: 1)
            if !dirty.isEmpty {
                Text("\(dirty.count) dosyada kaydedilmemiş değişiklik var; önce commit'le ya da geri al.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warn.opacity(0.08))
                    .help(GitRow.fileList(dirty))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if !local.isEmpty {
                        SectionLabel("Yerel").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                        ForEach(local, id: \.self) { name in
                            let current = name == status?.branch
                            BranchRow(name: name, remote: nil, current: current, disabled: !current && !dirty.isEmpty) {
                                if !current { model.gitSwitch(serviceID, to: .local(name)) }
                                close()
                            }
                        }
                    }
                    if !remote.isEmpty {
                        SectionLabel("Uzak").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                        ForEach(remote, id: \.self) { branch in
                            BranchRow(name: branch.name, remote: branch.remote, current: false, disabled: !dirty.isEmpty) {
                                model.gitSwitch(serviceID, to: .remote(branch))
                                close()
                            }
                        }
                    }
                    if local.isEmpty && remote.isEmpty {
                        Text(query.isEmpty ? "Branch bulunamadı" : "Eşleşen branch yok")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                            .padding(12)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 300)
        .background(Theme.bg)
        .onAppear { model.gitRefresh(serviceID, fetchMaxAge: 30) }
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }
}

private struct BranchRow: View {
    let name: String
    let remote: String?
    let current: Bool
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .opacity(current ? 1 : 0)
                    .frame(width: 12)
                Text(name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let remote, remote != "origin" {
                    Text(remote).font(.system(size: 11)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering && !disabled ? Theme.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
    }
}
