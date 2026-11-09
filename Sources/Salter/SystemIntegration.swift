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
    private let notificationDelegate = NotificationDelegate()

    func requestNotificationPermission() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Clicking the notification opens `page` (the release page).
    func notifyUpdate(version: String, page: URL) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Şalter \(version) çıktı"
        content.body = "İndirme sayfasını açmak için tıkla."
        content.userInfo = [NotificationDelegate.urlKey: page.absoluteString]
        let request = UNNotificationRequest(identifier: "update-\(version)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
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

    static let vsCodeBundleID = "com.microsoft.VSCode"

    var hasVSCode: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.vsCodeBundleID) != nil
    }

    /// Opens the folder in VS Code; falls back to Finder when VS Code is not installed.
    func openInEditor(_ path: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.vsCodeBundleID) else {
            reveal(path)
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Opens the URL a notification carries (update notifications); others just bring nothing up.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let urlKey = "url"

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let link = response.notification.request.content.userInfo[Self.urlKey] as? String, let url = URL(string: link) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
}
