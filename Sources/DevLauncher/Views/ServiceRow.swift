import DevLauncherCore
import SwiftUI

struct ServiceRow: View {
    @Environment(AppModel.self) private var model
    let id: String
    var showRepo = false

    var body: some View {
        let status = model.status(id)
        HStack(spacing: 8) {
            StatusDot(status: status)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(id)).lineLimit(1)
                if showRepo {
                    Text(model.repoName(of: id)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let port = status.ports.first {
                Text(":\(port)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if model.service(id)?.sourceMissing == true {
                Image(systemName: "questionmark.circle").foregroundStyle(.orange).help("Kaynakta artık yok")
            }
            StartStopButton(id: id)
        }
        .contextMenu { ServiceContextMenu(id: id) }
    }
}

struct StartStopButton: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        switch model.status(id) {
        case .starting, .running:
            Button { model.stop(id) } label: { Image(systemName: "stop.fill") }
                .buttonStyle(.borderless)
                .help("Durdur")
        case .stopping:
            ProgressView().controlSize(.small)
        case .stopped, .crashed:
            Button { model.start(id) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .help("Başlat")
        }
    }
}

struct ServiceContextMenu: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        if model.status(id).isActive {
            Button("Durdur") { model.stop(id) }
            Button("Yeniden başlat") { model.restart(id) }
        } else {
            Button("Başlat") { model.start(id) }
        }
        Button(model.isPinned(id) ? "Sabitlemeyi kaldır" : "Sabitle") { model.togglePin(id) }
    }
}
