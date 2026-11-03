import Foundation
import Testing
@testable import SalterCore

@Suite struct GitFailureTests {
    func classify(_ stderr: String) -> GitFailure { GitFailure.classify(stderr: stderr, timedOut: false) }

    @Test func localChangesOnMerge() {
        let f = classify("error: Your local changes to the following files would be overwritten by merge:\n\tsrc/a.py\n\tsrc/b.py\nPlease commit your changes or stash them before you merge.\nAborting\n")
        #expect(f == .localChanges(["src/a.py", "src/b.py"]))
        #expect(f.message.contains("src/a.py, src/b.py"))
    }

    @Test func localChangesOnCheckout() {
        let f = classify("error: Your local changes to the following files would be overwritten by checkout:\n\ta.txt\nPlease commit your changes or stash them before you switch branches.\nAborting")
        #expect(f == .localChanges(["a.txt"]))
    }

    @Test func untrackedOnCheckout() {
        let f = classify("error: The following untracked working tree files would be overwritten by checkout:\n\tnew.txt\nPlease move or remove them before you switch branches.\nAborting")
        #expect(f == .untrackedWouldBeOverwritten(["new.txt"]))
    }

    @Test func divergedFastForward() {
        #expect(classify("fatal: Not possible to fast-forward, aborting.") == .diverged)
        #expect(classify("fatal: Not possible to fast-forward, aborting.").message == "Yerel ve uzak branch ayrışmış; birleştirmeyi VS Code ya da terminalden yap.")
    }

    @Test func noUpstreamConfigured() {
        #expect(classify("fatal: no upstream configured for branch 'x'") == .noUpstream)
    }

    @Test func networkFailures() {
        let samples = [
            "fatal: Could not read from remote repository.",
            "ssh: Could not resolve hostname git.example: nodename nor servname provided",
            "git@host: Permission denied (publickey).",
            "fatal: unable to access 'https://h/r.git/': Could not resolve host: h",
            "fatal: Authentication failed for 'https://h/r.git/'",
            "fatal: could not read Username for 'https://h': terminal prompts disabled",
            "fatal: '/nope' does not appear to be a git repository",
        ]
        for sample in samples {
            #expect(classify(sample) == .network(sample))
            #expect(classify(sample).message == "Uzak sunucuya bağlanılamadı")
            #expect(classify(sample).detail == sample)
        }
    }

    @Test func timeoutWins() {
        #expect(GitFailure.classify(stderr: "anything", timedOut: true) == .timeout)
        #expect(GitFailure.timeout.message == "Uzak sunucuya bağlanılamadı (zaman aşımı)")
    }

    @Test func unknownIsOther() {
        #expect(classify("fatal: something odd") == .other("fatal: something odd"))
        #expect(classify("fatal: something odd").detail == "fatal: something odd")
    }
}
