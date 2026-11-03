import SalterCore
import SwiftUI

/// A selectable service row in the sidebar.
struct SidebarRow<Extra: View>: View {
    @Environment(AppModel.self) private var model
    let id: String
    let title: String
    var indent = false
    /// Repo path whose new-service suggestions are badged on this row (flat single-service repos).
    var suggestions: String?
    var sheet: Binding<SheetRoute?>?
    let onRename: (String) -> Void
    @ViewBuilder var extraMenu: () -> Extra
    @State private var hovering = false

    var body: some View {
        let status = model.status(id)
        let selected = model.selection == id
        HStack(spacing: 8) {
            StatusDot(status: status)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let path = suggestions, let count = model.suggestions[path]?.count, count > 0 {
                Button("\(count) yeni") { sheet?.wrappedValue = .suggestions(path) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                    .help("Keşfedilen yeni servisler")
            }
            if model.service(id)?.sourceMissing == true {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warn)
                    .help("Kaynakta artık yok")
            }
            if hovering {
                StartStopButton(id: id)
            } else if let port = status.ports.first {
                Text(":\(String(port))")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(.leading, indent ? 26 : 8)
        .padding(.trailing, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Theme.selection : hovering ? Theme.selection.opacity(0.5) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selection = id }
        .onHover { hovering = $0 }
        .contextMenu {
            ServiceContextMenu(id: id, onRename: { onRename(id) })
            extraMenu()
        }
    }
}

extension SidebarRow where Extra == EmptyView {
    init(id: String, title: String, indent: Bool = false, onRename: @escaping (String) -> Void) {
        self.init(id: id, title: title, indent: indent, suggestions: nil, sheet: nil, onRename: onRename) { EmptyView() }
    }
}

struct StartStopButton: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        Group {
            switch model.status(id) {
            case .starting, .running:
                Button { model.stop(id) } label: { Image(systemName: "stop.fill") }
                    .help("Durdur")
            case .stopping:
                ProgressView().controlSize(.mini)
            case .crashed:
                Button { model.restart(id) } label: { Image(systemName: "arrow.clockwise") }
                    .help("Yeniden başlat")
            case .stopped:
                Button { model.start(id) } label: { Image(systemName: "play.fill") }
                    .help("Başlat")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10))
        .foregroundStyle(Theme.text2)
        .frame(width: 18, height: 18)
        .contentShape(Rectangle())
    }
}

struct ServiceContextMenu: View {
    @Environment(AppModel.self) private var model
    let id: String
    var onRename: (() -> Void)?

    var body: some View {
        if model.status(id).isActive {
            Button("Durdur") { model.stop(id) }
            Button("Yeniden başlat") { model.restart(id) }
        } else {
            Button("Başlat") { model.start(id) }
        }
        Button(model.isPinned(id) ? "Sabitlemeyi kaldır" : "Sabitle") { model.togglePin(id) }
        if let onRename {
            Button("Yeniden adlandır…", action: onRename)
        }
    }
}
