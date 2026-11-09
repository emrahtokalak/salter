import Foundation
import Testing
@testable import SalterCore

@Suite struct UpdateCheckTests {
    @Test func parsesVersions() {
        #expect(AppVersion("1.2.3")?.parts == [1, 2, 3])
        #expect(AppVersion("v1.10")?.parts == [1, 10])
        #expect(AppVersion("V2")?.parts == [2])
        #expect(AppVersion("v.1.1.0")?.parts == [1, 1, 0])
        #expect(AppVersion(".1.1") == nil)
        #expect(AppVersion("1.2.0-beta.1")?.parts == [1, 2, 0])
        #expect(AppVersion("1.2+5")?.parts == [1, 2])
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    @Test func comparesNumerically() throws {
        let v = { (s: String) in try #require(AppVersion(s)) }
        #expect(try v("1.10.0") > v("1.9.9"))
        #expect(try v("1.1") == v("1.1.0"))
        #expect(try v("v1.1.0") < v("1.1.1"))
        #expect(try !(v("2.0") < v("2.0.0")))
    }

    @Test func readsReleaseFromRedirect() throws {
        let url = try #require(URL(string: "https://github.com/emrahtokalak/salter/releases/tag/v1.2.0"))
        let release = try #require(ReleaseChecker.release(fromRedirect: url))
        #expect(release.tag == "v1.2.0")
        #expect(release.version.description == "1.2.0")
        #expect(release.pageURL == url)
        let dotted = try #require(URL(string: "https://github.com/emrahtokalak/salter/releases/tag/v.1.1.0"))
        #expect(ReleaseChecker.release(fromRedirect: dotted)?.version.description == "1.1.0")
    }

    @Test(arguments: ["https://github.com/a/b/releases", "https://github.com/login", "https://github.com/a/b/releases/tag/nightly"])
    func ignoresRedirectWithoutRelease(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(ReleaseChecker.release(fromRedirect: url) == nil)
    }

    @Test func dueOncePerDay() {
        let now = Date()
        #expect(ReleaseChecker.isDue(lastCheck: nil, now: now))
        #expect(!ReleaseChecker.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(ReleaseChecker.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
        #expect(ReleaseChecker.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    @Test func announcesOnlyNewerUnskipped() throws {
        let url = try #require(URL(string: "https://github.com/a/b/releases/tag/v1.2.0"))
        let release = try #require(ReleaseChecker.release(fromRedirect: url))
        let current = try #require(AppVersion("1.1.0"))
        #expect(ReleaseChecker.announce(release, current: current, skipped: nil))
        #expect(!ReleaseChecker.announce(release, current: current, skipped: "1.2.0"))
        #expect(!ReleaseChecker.announce(release, current: current, skipped: "v1.2"))
        #expect(ReleaseChecker.announce(release, current: current, skipped: "1.1.5"))
        let same = try #require(AppVersion("1.2.0"))
        #expect(!ReleaseChecker.announce(release, current: same, skipped: nil))
    }

    /// Hits github.com; run with `SALTER_NETWORK_TESTS=1 make test FILTER=UpdateCheckTests`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SALTER_NETWORK_TESTS"] != nil))
    func fetchesLatestReleaseFromGitHub() async throws {
        let release = try await ReleaseChecker.fetchLatest()
        #expect(release.pageURL.host == "github.com")
        #expect(release.version >= AppVersion("1.1.0")!)
    }
}
