import AppKit
import SalterCore
import SwiftUI

@main
struct SalterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Şalter", id: "main") {
            MainWindow()
                .environment(delegate.model)
                .frame(minWidth: 820, minHeight: 480)
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            MenuBarView().environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(delegate.model)
        }
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if model.hasCrash {
            Image(systemName: "exclamationmark.triangle.fill")
        } else if model.activeCount > 0 {
            Image(systemName: "lightswitch.on")
        } else {
            Image(systemName: "lightswitch.off")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.integration.requestNotificationPermission()
        Task { await model.bootstrap() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let count = model.activeCount
        guard count > 0 else { return .terminateNow }
        let stop = Alerts.confirm(
            "\(count) servis çalışıyor",
            "Çıkmadan önce hepsi durdurulacak.",
            confirm: "Hepsini durdur ve çık",
            cancel: "İptal"
        )
        guard stop else { return .terminateCancel }
        Task {
            await model.stopAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
