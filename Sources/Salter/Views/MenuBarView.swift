import AppKit
import SalterCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Şalter").font(.headline)
                Spacer()
                if model.activeCount > 0 {
                    Text("\(model.activeCount) çalışıyor").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if model.pinnedIDs.isEmpty {
                Text("Sabitlenmiş servis yok. Ana pencerede bir servise sağ tıklayıp “Sabitle” diyebilirsin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.pinnedIDs, id: \.self) { id in
                        MenuServiceRow(id: id)
                    }
                }
                .padding(.vertical, 6)
            }
            Divider()
            HStack {
                Button("Pencereyi aç") { openMainWindow() }
                Spacer()
                Button("Tümünü durdur") { Task { await model.stopAll() } }
                    .disabled(model.activeCount == 0)
                Button("Çık") { NSApp.terminate(nil) }
            }
            .padding(10)
        }
        .frame(width: 360)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct MenuServiceRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let id: String

    var body: some View {
        let status = model.status(id)
        HStack(spacing: 8) {
            StatusDot(status: status)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(id)).lineLimit(1)
                Text(model.repoName(of: id) + " · " + status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let port = status.ports.first {
                Button(":\(port)") { model.integration.openBrowser(port: port) }.buttonStyle(.link)
            }
            Button {
                model.selection = id
                openWindow(id: "main")
                NSApp.activate()
            } label: {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .help("Logu göster")
            StartStopButton(id: id)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
