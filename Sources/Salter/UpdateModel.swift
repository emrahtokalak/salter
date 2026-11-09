import Foundation
import Observation
import SalterCore

/// Daily check for a newer GitHub release; shows a banner and sends one notification per version.
@MainActor @Observable
final class UpdateModel {
    enum ManualResult: Equatable {
        case upToDate
        case failed
    }

    /// A newer release the user has not skipped.
    private(set) var available: ReleaseInfo?
    private(set) var checking = false
    /// Outcome of the last "Şimdi kontrol et", shown in Settings.
    private(set) var manualResult: ManualResult?
    private(set) var lastCheck: Date?

    /// nil when not running from a bundle with a version (e.g. `swift run`): checks are off.
    let current: AppVersion? = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        .flatMap(AppVersion.init)

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored var notify: (ReleaseInfo) -> Void = { _ in }

    private enum Key {
        static let lastCheck = "update.lastCheck"
        static let skipped = "update.skippedVersion"
        static let notified = "update.notifiedVersion"
        /// Last release found, so the banner survives a relaunch before the next daily check.
        static let latestPage = "update.latestPage"
    }

    /// How often the loop wakes up to see whether a day has passed; the request itself is daily.
    static let wakeInterval: TimeInterval = 3 * 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
    }

    /// Starts or stops the daily check. The first one waits a little so it does not compete with startup.
    func setEnabled(_ enabled: Bool) {
        loop?.cancel()
        loop = nil
        guard enabled, current != nil else {
            available = nil
            return
        }
        restoreSaved()
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                if ReleaseChecker.isDue(lastCheck: self.lastCheck) { await self.check(manual: false) }
                try? await Task.sleep(nanoseconds: UInt64(Self.wakeInterval * 1_000_000_000))
            }
        }
    }

    private func restoreSaved() {
        guard let current, let page = defaults.url(forKey: Key.latestPage),
              let release = ReleaseChecker.release(fromRedirect: page),
              ReleaseChecker.announce(release, current: current, skipped: defaults.string(forKey: Key.skipped)) else { return }
        available = release
    }

    func checkNow() {
        Task { await check(manual: true) }
    }

    /// Hides this version until a newer one appears.
    func skip() {
        guard let available else { return }
        defaults.set(available.version.description, forKey: Key.skipped)
        self.available = nil
    }

    private func check(manual: Bool) async {
        guard let current, !checking else { return }
        checking = true
        if manual { manualResult = nil }
        defer { checking = false }
        guard let release = try? await ReleaseChecker.fetchLatest() else {
            // Quiet for the daily check (offline, VPN, captive portal); not recorded, so the next wake-up retries.
            if manual { manualResult = .failed }
            return
        }
        recordCheck()
        defaults.set(release.pageURL, forKey: Key.latestPage)
        // A manual check shows a skipped version again.
        let skipped = manual ? nil : defaults.string(forKey: Key.skipped)
        guard ReleaseChecker.announce(release, current: current, skipped: skipped) else {
            available = nil
            if manual { manualResult = .upToDate }
            return
        }
        if manual { defaults.removeObject(forKey: Key.skipped) }
        available = release
        let version = release.version.description
        if defaults.string(forKey: Key.notified) != version {
            defaults.set(version, forKey: Key.notified)
            notify(release)
        }
    }

    private func recordCheck() {
        lastCheck = Date()
        defaults.set(lastCheck, forKey: Key.lastCheck)
    }
}
