import SalterCore
import SwiftUI

/// "Şalter x.y.z çıktı" with İndir / Atla; shown in the sidebar and the menu-bar panel.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    let release: ReleaseInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.accent)
            Text("Şalter \(Text(release.version.description).foregroundStyle(Theme.text).fontWeight(.medium)) çıktı")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Atla") { model.updates.skip() }
                .buttonStyle(PlainTextButtonStyle(color: Theme.text3))
                .help("Bu sürümü bir daha gösterme")
            Button("İndir") { model.integration.open(release.pageURL) }
                .buttonStyle(PlainTextButtonStyle(color: Theme.accent))
                .help(release.pageURL.absoluteString)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.25)))
    }
}
