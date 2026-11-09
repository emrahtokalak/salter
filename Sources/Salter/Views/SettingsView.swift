import AppKit
import SalterCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                group("Taranan klasörler") {
                    Text("Şalter bu klasörlerin altındaki projeleri tarar, yeni repo bulunca haber verir. Tek bir projeyi eklemek için kenar çubuğundaki + menüsünden “Repo ekle…” seçeneğini kullan.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.config.roots.isEmpty {
                        Text("Henüz taranan klasör yok. Projelerinin bulunduğu üst klasörü (örn. ~/Projects) ekle.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(model.config.roots, id: \.self) { root in
                        HStack(spacing: 8) {
                            Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.text3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((root as NSString).abbreviatingWithTildeInPath)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(model.repoCount(inRoot: root)) repo ekli")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.text3)
                            }
                            Spacer()
                            Button("Finder'da göster") { model.integration.reveal(root) }
                                .buttonStyle(QuietButtonStyle(height: 24, tint: Theme.text2))
                            Button("Kaldır") { Task { await model.removeRoot(root) } }
                                .buttonStyle(QuietButtonStyle(height: 24, tint: Theme.err))
                                .help("Bu klasörü taramayı bırak; ekli repolar listede kalır.")
                        }
                    }
                    Button("Taranacak klasör ekle…") { RepoActions.addRootFromPanel(model) }
                        .buttonStyle(QuietButtonStyle(height: 24))
                }
                group("Genel") {
                    Toggle("Login'de başlat", isOn: Binding(
                        get: { model.integration.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    Toggle("Servis çökünce bildirim gönder", isOn: Binding(
                        get: { model.config.settings.crashNotifications },
                        set: { model.setCrashNotifications($0) }
                    ))
                    Toggle("Güncellemeleri günde bir kontrol et", isOn: Binding(
                        get: { model.config.settings.updateChecks },
                        set: { model.setUpdateChecks($0) }
                    ))
                    updateStatus
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                group("Shell ortamı") {
                    if let shell = model.shell {
                        if let error = shell.error {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                                Text(error).foregroundStyle(Theme.text2)
                            }
                            .font(.system(size: 12))
                        } else {
                            Text("PATH: " + (shell.variables["PATH"] ?? ""))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.text2)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Button("Yeniden yükle") { Task { await model.reloadShell() } }.buttonStyle(QuietButtonStyle(height: 24))
                }
                group("Dosyalar") {
                    HStack(spacing: 8) {
                        Button("Ayar dosyasını göster") {
                            model.integration.reveal(ConfigStore.defaultDirectory.appendingPathComponent("config.json").path)
                        }
                        Button("Log klasörünü göster") { model.integration.reveal(LogFileWriter.defaultDirectory.path) }
                    }
                    .buttonStyle(QuietButtonStyle(height: 24))
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .frame(width: 520, height: 520)
    }

    @ViewBuilder private var updateStatus: some View {
        let updates = model.updates
        HStack(spacing: 8) {
            Button("Şimdi kontrol et") { updates.checkNow() }
                .buttonStyle(QuietButtonStyle(height: 24))
                .disabled(updates.checking || updates.current == nil)
            if updates.checking {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            Group {
                if updates.current == nil {
                    Text("Sürüm bilgisi yok (paketlenmemiş build)")
                } else if let release = updates.available {
                    HStack(spacing: 4) {
                        Text("Şalter \(release.version.description) mevcut.")
                        Button("İndir") { model.integration.open(release.pageURL) }
                            .buttonStyle(PlainTextButtonStyle(color: Theme.accent))
                    }
                } else if updates.manualResult == .failed {
                    Text("Kontrol edilemedi (bağlantı yok mu?)").foregroundStyle(Theme.warn)
                } else if updates.manualResult == .upToDate {
                    Text("Güncelsin (\(updates.current?.description ?? ""))")
                } else if let last = updates.lastCheck {
                    Text("Sürüm \(updates.current?.description ?? "") · son kontrol \(last.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Sürüm \(updates.current?.description ?? "")")
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.text3)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            Card {
                VStack(alignment: .leading, spacing: 10) { content() }
            }
        }
    }

}
