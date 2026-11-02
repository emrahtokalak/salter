import AppKit
import ServiceManagement
import UserNotifications

/// macOS services that only work inside the signed .app bundle; no-ops (or errors) under `swift run`.
@MainActor
final class SystemIntegration {
    enum IntegrationError: LocalizedError {
        case notBundled

        var errorDescription: String? {
            "Bu özellik yalnızca Salter.app olarak çalışırken kullanılabilir (make install)."
        }
    }

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    func requestNotificationPermission() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCrash(service: String, detail: String) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(service) çöktü"
        content.body = detail
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    var launchAtLoginEnabled: Bool {
        isBundled && SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        guard isBundled else { throw IntegrationError.notBundled }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openBrowser(port: Int) {
        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
