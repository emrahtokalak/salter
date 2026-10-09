import AppKit

/// Modal alerts that work whether or not the main window is open (e.g. from the menu bar).
@MainActor
enum Alerts {
    static func info(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Tamam")
        NSApp.activate()
        alert.runModal()
    }

    /// Returns true when the user picks `confirm`.
    static func confirm(_ title: String, _ message: String, confirm: String, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
