import AppKit
import SalterCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Şalter").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if model.activeCount > 0 {
                    Text("\(model.activeCount) çalışıyor").font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            if model.pinnedIDs.isEmpty {
                Text("Sabitlenmiş servis yok. Ana pencerede bir servise sağ tıklayıp “Sabitle” diyebilirsin.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            } else {
                VStack(spacing: 1) {
                    ForEach(model.pinnedIDs, id: \.self) { id in
                        MenuServiceRow(id: id) { openMainWindow(selecting: id) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 4) {
                Button("Pencereyi aç") { openMainWindow(selecting: nil) }
                Spacer()
                Button("Tümünü durdur") { Task { await model.stopAll() } }
                    .disabled(model.activeCount == 0)
                Button("Çık") { NSApp.terminate(nil) }
            }
            .buttonStyle(PlainTextButtonStyle())
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .background(Theme.bg)
    }

    private func openMainWindow(selecting id: String?) {
        if let id { model.selection = id }
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct MenuServiceRow: View {
    @Environment(AppModel.self) private var model
    let id: String
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let status = model.status(id)
        HStack(spacing: 8) {
            StatusDot(status: status)
            Text(model.displayName(id))
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            if status.isCrashed {
                Text("çöktü").font(.system(size: 11.5)).foregroundStyle(Theme.err)
            } else if let port = status.ports.first {
                Text(":\(String(port))").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text3)
            }
            StartStopButton(id: id)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.selection : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .help("Ana pencerede aç")
    }
}
