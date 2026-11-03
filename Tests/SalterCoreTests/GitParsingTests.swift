import Foundation
import Testing
@testable import SalterCore

@Suite struct GitParsingTests {
    @Test func statusBranchUpstreamAheadBehind() {
        let s = GitStatus.parse(porcelainV2: """
        # branch.oid 1234567890abcdef1234567890abcdef12345678
        # branch.head develop
        # branch.upstream origin/develop
        # branch.ab +1 -3
        """)
        #expect(s.branch == "develop")
        #expect(s.commit == "1234567")
        #expect(s.upstream == "origin/develop")
        #expect(s.ahead == 1)
        #expect(s.behind == 3)
        #expect(s.changedFiles.isEmpty)
        #expect(!s.isDetached)
    }

    @Test func statusDetached() {
        let s = GitStatus.parse(porcelainV2: "# branch.oid abcdef1234567\n# branch.head (detached)\n")
        #expect(s.branch == nil)
        #expect(s.isDetached)
        #expect(s.commit == "abcdef1")
    }

    @Test func statusNoUpstream() {
        let s = GitStatus.parse(porcelainV2: "# branch.oid abcdef1234567\n# branch.head main\n")
        #expect(s.upstream == nil)
        #expect(s.ahead == 0)
        #expect(s.behind == 0)
    }

    @Test func statusUpstreamWithoutABIsGone() {
        let s = GitStatus.parse(porcelainV2: "# branch.oid abcdef1234567\n# branch.head x\n# branch.upstream origin/x\n")
        #expect(s.upstream == "origin/x")
        #expect(s.upstreamGone)
        let live = GitStatus.parse(porcelainV2: "# branch.head x\n# branch.upstream origin/x\n# branch.ab +0 -0\n")
        #expect(!live.upstreamGone)
    }

    @Test func statusTrackedVsUntracked() {
        let s = GitStatus.parse(porcelainV2: """
        # branch.head main
        1 .M N... 100644 100644 100644 aaaa bbbb src/app.py
        2 R. N... 100644 100644 100644 aaaa bbbb R100 new name.py\told.py
        u UU N... 100644 100644 100644 100644 aaaa bbbb cccc conflict.txt
        ? untracked.txt
        ! ignored.log
        """)
        #expect(s.changedFiles == ["src/app.py", "new name.py", "conflict.txt"])
    }

    @Test func statusNonASCIIPath() {
        let s = GitStatus.parse(porcelainV2: "1 .M N... 100644 100644 100644 aaaa bbbb doküman/özet.md\n")
        #expect(s.changedFiles == ["doküman/özet.md"])
    }

    @Test func branchListSplitsLocalAndRemoteOnly() {
        let b = GitBranchList.parse(refs: """
        refs/heads/main
        refs/heads/feature/x
        refs/remotes/origin/HEAD
        refs/remotes/origin/main
        refs/remotes/origin/feature/y
        refs/remotes/upstream/feature/y
        """)
        #expect(b.local == ["feature/x", "main"])
        #expect(b.remoteOnly == [RemoteBranch(remote: "origin", name: "feature/y")])
    }
}
