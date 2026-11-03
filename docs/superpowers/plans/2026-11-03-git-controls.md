# Git Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the repo's branch in the service detail screen and let the user switch branches (local or remote) and pull, with polite handling of local changes and a restart prompt.

**Architecture:**
- **SalterCore/Git** holds:
  - pure parsers (`GitStatus`, `GitBranchList`);
  - an error classifier (`GitFailure`);
  - a process runner with timeout and cancellation (`GitRunner`);
  - `GitRepo`, which composes git commands into `pull` / `switchTo` outcomes.
- **App target:**
  - `GitModel` (@Observable) keeps per-working-tree state and throttles fetches;
  - an `AppModel` extension orchestrates log lines and the restart prompt;
  - `GitRow` and `BranchPicker` views sit in the detail header.

**Tech Stack:** Swift 6 toolchain (language mode v5), SwiftUI on macOS 14 and Swift Testing, built with CLT only. The `git` CLI runs via the existing `ProcessRunner.spawn`.

**Spec:** `docs/superpowers/specs/2026-11-03-git-controls-design.md`

## Global Constraints

- All git commands run with the user's shell env plus:
  - `GIT_TERMINAL_PROMPT=0`;
  - `GIT_ASKPASS` and `SSH_ASKPASS` removed;
  - `GIT_SSH_COMMAND="ssh -o BatchMode=yes"` unless already set;
  - `LC_ALL=C`, so stderr is stable for classification;
  - `GIT_OPTIONAL_LOCKS=0`.
- Every invocation passes `-c core.quotePath=false`.
- Network step (fetch) timeout: 60 s. Local steps (merge, switch, status, for-each-ref, rev-parse, rev-list) have no timeout.
- Pull = `git fetch` followed by `git merge --ff-only @{u}`. Never a plain `git pull`.
- Throttles:
  - background fetch on detail open: at most once per 300 s per working tree;
  - on picker open: at most once per 30 s.
- A background fetch disables nothing, fails silently, and is cancelled (process group killed) when the user starts a pull or switch in that tree.
- One user operation per working tree at a time. State is keyed by `git rev-parse --show-toplevel`.
- Only *tracked* modifications block a switch; untracked files do not.
- UI copy is Turkish. Required strings (verbatim):

  | Case | Copy |
  |---|---|
  | Switch blocked by local changes | "N dosyada kaydedilmemiş değişiklik var; önce commit'le ya da geri al." |
  | Pull with new commits | "N yeni commit çekildi" |
  | Pull, nothing new | "Zaten güncel" |
  | Pull would overwrite local changes | "Yerel değişiklikler çekilecek dosyalarla çakışıyor: <files>" |
  | Branches diverged | "Yerel ve uzak branch ayrışmış; birleştirmeyi VS Code ya da terminalden yap." |
  | Network or auth failure | "Uzak sunucuya bağlanılamadı" |
  | Timeout | "Uzak sunucuya bağlanılamadı (zaman aşımı)" |
  | Restart prompt | "<repo> güncellendi. Çalışan N servis yeniden başlatılsın mı?", buttons "Yeniden başlat" / "Sonra" |
  | Log line after pull | "git pull: N yeni commit" |
  | Log line after switch | "branch: <name>" |
  | No upstream | "upstream yok" |
  | Detached HEAD label | "ayrık HEAD" |
  | Up to date | "güncel" |
- Linear design language (`Theme`, `QuietButtonStyle`, …) from the UI redesign. "Debug" never appears in UI copy.
- Test with `make test [FILTER=...]` and build with `make build`. To run the app use `make app` + `open build/Salter.app`; unsigned binaries are killed by machine policy.

## Review Focus

1. **Paths:** paths with spaces or non-ASCII characters (Turkish names) in status and branch output must parse correctly. `core.quotePath=false` and porcelain v2 handle this, and a test pins it.
2. **Hangs:** a remote that asks for credentials or is unreachable must never hang. Pin it with a test whose fetch targets a non-existent local path; it must fail fast with a classified failure, not hang.
3. **Background fetch vs user action:** a background fetch in flight when the user hits Çek must not make the pull fail with a lock error. The fetch is cancelled first (`GitModel`).
4. **Shared working tree:** for a repo with two services, both detail screens reflect busy state and the new branch, and the restart prompt counts both.
5. **Repo is not a git repo** (or `git` is missing): the row is hidden and nothing errors. A test covers `GitRepo.open` returning nil for a plain directory.

---

### Task 1: Status and branch parsing

**Files:**
- Create: `Sources/SalterCore/Git/GitStatus.swift`
- Test: `Tests/SalterCoreTests/GitParsingTests.swift`

**Interfaces:**
- Produces:
  - `public struct GitStatus: Equatable, Sendable { public var branch: String?; public var commit: String?; public var upstream: String?; public var ahead: Int; public var behind: Int; public var changedFiles: [String]; public var isDetached: Bool { branch == nil } ; public static func parse(porcelainV2: String) -> GitStatus }`
    - `commit` is the short (7-char) oid.
    - `changedFiles` holds tracked changes only (record types `1`, `2`, `u`; for `2` the new path).
  - `public struct RemoteBranch: Equatable, Hashable, Sendable { public var remote: String; public var name: String }`
  - `public struct GitBranchList: Equatable, Sendable { public var local: [String]; public var remoteOnly: [RemoteBranch]; public static func parse(refs: String) -> GitBranchList }`
    - The input is the output of `git for-each-ref --format=%(refname) refs/heads refs/remotes`.
    - `local` is sorted.
    - `remoteOnly` excludes `*/HEAD` and names that exist locally, dedupes by name (first remote wins), and is sorted by name.

- [ ] **Step 1: Tests.**

  | Test | Input | Expect |
  |---|---|---|
  | `statusBranchUpstreamAheadBehind` | `# branch.oid 1234567890abcdef…`, `# branch.head develop`, `# branch.upstream origin/develop`, `# branch.ab +1 -3` | branch "develop", commit "1234567", upstream "origin/develop", ahead 1, behind 3, changedFiles empty |
  | `statusDetached` | `# branch.head (detached)` | `branch == nil`, `isDetached` |
  | `statusNoUpstream` | no upstream or ab lines | `upstream == nil`, ahead 0, behind 0 |
  | `statusTrackedVsUntracked` | `1 .M N... 100644 100644 100644 a b src/app.py`, `2 R. N... 100644 100644 100644 a b R100 new name.py\told.py`, `u UU N... 1 2 3 4 a b c conflict.txt`, `? untracked.txt`, `! ignored.log` | changedFiles == ["src/app.py", "new name.py", "conflict.txt"] |
  | `statusNonASCIIPath` | `1 .M N... 100644 100644 100644 a b doküman/özet.md` | changedFiles == ["doküman/özet.md"] |
  | `branchListSplitsLocalAndRemoteOnly` | refs: `refs/heads/main`, `refs/heads/feature/x`, `refs/remotes/origin/HEAD`, `refs/remotes/origin/main`, `refs/remotes/origin/feature/y`, `refs/remotes/upstream/feature/y` | local == ["feature/x", "main"]; remoteOnly == [RemoteBranch(remote: "origin", name: "feature/y")] |

- [ ] **Step 2: Run** `make test FILTER=GitParsingTests`. Expected: build FAIL, `cannot find 'GitStatus'`.
- [ ] **Step 3: Implement.** For record type `1` the path is everything after the 8th space-separated field. Type `2` has 9 fields before the path, and the path is cut at `\t`. Type `u` has 10.
- [ ] **Step 4: Run** `make test FILTER=GitParsingTests`. Expected: pass.
- [ ] **Step 5: Commit.** `feat: parse git status and branch refs`

### Task 2: Failure classification

**Files:**
- Create: `Sources/SalterCore/Git/GitFailure.swift`
- Test: `Tests/SalterCoreTests/GitFailureTests.swift`

**Interfaces:**
- Produces:
  - `public enum GitFailure: Equatable, Sendable { case localChanges([String]); case untrackedWouldBeOverwritten([String]); case diverged; case noUpstream; case network(String); case timeout; case other(String) }`
  - `public var message: String` holds the Turkish copy:
    - `localChanges(files)` → "Yerel değişiklikler çekilecek dosyalarla çakışıyor: a, b";
    - `untrackedWouldBeOverwritten` → "Takip edilmeyen dosyalar üzerine yazılacağı için branch değiştirilemedi: a, b";
    - `noUpstream` → "Bu branch'in uzak karşılığı (upstream) yok.";
    - `other(raw)` → "Git işlemi başarısız oldu.";
    - the remaining cases use the Global Constraints copy.
  - `public var detail: String?` is the raw stderr for `network` and `other`.
  - `public static func classify(stderr: String, timedOut: Bool) -> GitFailure`

- [ ] **Step 1: Tests**, one per sample. File lists are taken from the tab-indented lines.

  | Test | stderr | Expect |
  |---|---|---|
  | `localChangesOnMerge` | `"error: Your local changes to the following files would be overwritten by merge:\n\tsrc/a.py\n\tsrc/b.py\nPlease commit your changes or stash them before you merge.\nAborting\n"` | `.localChanges(["src/a.py", "src/b.py"])`; message contains "src/a.py, src/b.py" |
  | `localChangesOnCheckout` | same with "by checkout:" | `.localChanges` |
  | `untrackedOnCheckout` | `"error: The following untracked working tree files would be overwritten by checkout:\n\tnew.txt\nPlease move or remove them before you switch branches.\nAborting"` | `.untrackedWouldBeOverwritten(["new.txt"])` |
  | `divergedFastForward` | `"fatal: Not possible to fast-forward, aborting."` | `.diverged` |
  | `noUpstreamConfigured` | `"fatal: no upstream configured for branch 'x'"` | `.noUpstream` |
  | `networkFailures` | each of: `"fatal: Could not read from remote repository."`, `"ssh: Could not resolve hostname git.example: nodename nor servname provided"`, `"git@host: Permission denied (publickey)."`, `"fatal: unable to access 'https://h/r.git/': Could not resolve host: h"`, `"fatal: Authentication failed for 'https://h/r.git/'"`, `"fatal: could not read Username for 'https://h': terminal prompts disabled"`, `"fatal: '/nope' does not appear to be a git repository"` | `.network` |
  | `timeoutWins` | `classify(stderr: "anything", timedOut: true)` | `.timeout` |
  | `unknownIsOther` | `"fatal: something odd"` | `.other("fatal: something odd")` |

- [ ] **Step 2: Run** `make test FILTER=GitFailureTests`. Expected: build FAIL.
- [ ] **Step 3: Implement** by substring matching on the lowercased stderr, in the order of the table.
- [ ] **Step 4: Run** `make test FILTER=GitFailureTests`. Expected: pass.
- [ ] **Step 5: Commit.** `feat: classify git failures into Turkish messages`

### Task 3: Runner and repo actions

**Files:**
- Create: `Sources/SalterCore/Git/GitRunner.swift`
- Create: `Sources/SalterCore/Git/GitRepo.swift`
- Test: `Tests/SalterCoreTests/GitRepoTests.swift`, an integration test on temp repos

**Interfaces:**
- Consumes: `GitStatus.parse`, `GitBranchList.parse` (Task 1); `GitFailure.classify` (Task 2); `ProcessRunner.spawn`, `ProcessRunner.terminateGroup`.
- Produces:
  - `public struct GitResult: Equatable, Sendable { public var exitCode: Int32; public var stdout: String; public var stderr: String; public var timedOut: Bool; public var succeeded: Bool { exitCode == 0 && !timedOut } }`
  - `public enum GitRunner`:
    - `static func environment(shell: [String: String]) -> [String: String]` applies the Global Constraints.
    - `static func run(_ args: [String], in cwd: String, environment: [String: String], timeout: TimeInterval?) async -> GitResult`
      - The executable is `ProcessRunner.resolveExecutable("git", searchPath: env["PATH"]) ?? "/usr/bin/git"`, and the args are prefixed with `-c core.quotePath=false`.
      - On timeout or Task cancellation (`withTaskCancellationHandler`), run `terminateGroup(pgid, grace: 1)`. The result then has `timedOut = true` on timeout, or `exitCode = 130` on cancellation.
      - A spawn failure gives exitCode 127 with stderr set to the error description.
  - `public enum BranchTarget: Equatable, Sendable { case local(String); case remote(RemoteBranch) }`
  - `public enum GitOutcome: Equatable, Sendable { case switched(String); case pulled(newCommits: Int); case upToDate; case blocked(changedFiles: [String]); case failed(GitFailure) }`
  - `public struct GitRepo: Sendable { public let root: String; public let environment: [String: String] }`:
    - `static func open(_ path: String, environment: [String: String]) async -> GitRepo?` uses `rev-parse --show-toplevel`; nil when it fails.
    - `func status() async -> GitStatus?` runs `status --porcelain=v2 --branch`.
    - `func branches() async -> GitBranchList` runs `for-each-ref --format=%(refname) refs/heads refs/remotes`.
    - `func fetch(timeout: TimeInterval = 60) async -> GitResult` runs `fetch --prune`.
    - `func switchTo(_ target: BranchTarget) async -> GitOutcome`:
      - if `status()?.changedFiles` is non-empty, return `.blocked`;
      - `.local(n)` runs `switch n`;
      - `.remote(r)` runs `switch -c r.name --track r.remote/r.name`;
      - success returns `.switched(name)`, failure returns `.failed(classify)`.
    - `func pull() async -> GitOutcome`:
      1. If status has no upstream, return `.failed(.noUpstream)`.
      2. `old = rev-parse HEAD`.
      3. `fetch(timeout: 60)`; on failure return `.failed(classify)`.
      4. `merge --ff-only @{u}` with no timeout; on failure return `.failed(classify)`.
      5. `n = rev-list --count old..HEAD`; return `n == 0 ? .upToDate : .pulled(newCommits: n)`.
    - `static let fetchTimeout: TimeInterval = 60`

- [ ] **Step 1: Tests.**
  - Helper `TempRemote`:
    - `git init --bare -b main remote.git` and `git clone remote.git work` in `FileManager.temporaryDirectory/UUID`;
    - commits use the env `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_AUTHOR_NAME/EMAIL`, `GIT_COMMITTER_NAME/EMAIL`;
    - methods `commit(file:content:in:)` and `pushFromOther(branch:)`, which uses a second clone to create commits or branches on the remote.
  - Tests:

    | Test | Expect |
    |---|---|
    | `openReturnsNilForPlainDirectory` | — |
    | `openFindsToplevelFromSubfolder` | — |
    | `pullFastForwards` | the other clone pushes 2 commits; `pull()` gives `.pulled(newCommits: 2)`; then `pull()` gives `.upToDate` |
    | `pullBlockedByOverlappingLocalChange` | local modification of a file the other clone changed: `.failed(.localChanges([file]))`, and the working tree is unchanged |
    | `pullAllowedWithNonOverlappingChange` | local edit to another file: `.pulled` |
    | `pullDivergedFailsWithoutMerge` | local commit plus a remote commit: `.failed(.diverged)`, and HEAD is unchanged |
    | `pullWithoutUpstream` | — |
    | `switchBlockedByTrackedChange` | `.blocked(changedFiles: ["a.txt"])` |
    | `switchNotBlockedByUntracked` | — |
    | `switchToRemoteOnlyCreatesTracking` | the other clone pushes `feature/x`; `fetch`, then `branches().remoteOnly` contains it; `switchTo(.remote)` gives `.switched("feature/x")`; status.upstream == "origin/feature/x" |
    | `fetchFromMissingRemoteFailsFast` | set the remote url to `/nonexistent`; fetch is not succeeded within 10 s and classifies as `.network` |
    | `cancelledFetchKillsProcess` | start `run(["fetch"])` against a local fifo-blocked remote is complex, so instead start `run` of `["-c", "alias.slow=!sleep 30", "slow"]` in a Task, cancel after 0.3 s, and expect it to return within 3 s with `succeeded == false` |
    | `environmentDisablesPrompts` | `environment(shell: ["PATH": "/usr/bin", "GIT_ASKPASS": "x"])` has `GIT_TERMINAL_PROMPT == "0"`, no `GIT_ASKPASS`, and `GIT_SSH_COMMAND == "ssh -o BatchMode=yes"`; with an existing `GIT_SSH_COMMAND` the value is kept |
- [ ] **Step 2: Run** `make test FILTER=GitRepoTests`. Expected: build FAIL.
- [ ] **Step 3: Implement** `GitRunner` and `GitRepo`. Collect output via `ProcessRunner.spawn`'s line handler (`OutputKind` .stdout/.stderr), joined with `\n`. Bridge `onExit` to async with a checked continuation, and use a timeout Task that calls `terminateGroup`.
- [ ] **Step 4: Run** `make test FILTER=GitRepoTests`, then `make test`. Expected: all pass.
- [ ] **Step 5: Commit.** `feat: git runner and repo pull/switch actions`

### Task 4: GitModel and AppModel orchestration

**Files:**
- Create: `Sources/Salter/GitModel.swift`
- Create: `Sources/Salter/AppModel+Git.swift`

**Interfaces:**
- Consumes: `GitRepo`, `GitOutcome`, `GitStatus`, `GitBranchList`, `GitRunner.environment`.
- Produces:
  - `@MainActor @Observable final class GitModel`:
    - `struct Tree { var repo: GitRepo; var status: GitStatus?; var branches: GitBranchList?; var lastFetch: Date?; var fetching = false; var busy = false; var message: GitMessage? }`
    - `struct GitMessage: Equatable { var text: String; var detail: String?; var isError: Bool; var id = UUID() }`
    - `private(set) var trees: [String: Tree]` is keyed by toplevel; `private var rootForRepo: [String: String?]` maps a repo path to its toplevel or nil.
    - `func tree(forRepo path: String) -> Tree?`
    - `func refresh(repoPath: String, shell: [String: String]) async` opens the repo (caching the toplevel), then re-reads status and branches.
    - `func backgroundFetch(repoPath: String, shell: [String: String], maxAge: TimeInterval) async`:
      - skip if busy, already fetching, or `lastFetch` is younger than maxAge;
      - the fetch runs in a stored `Task` so it can be cancelled;
      - errors are silent;
      - refresh afterwards.
    - `func perform(repoPath: String, shell: [String: String], _ action: @Sendable (GitRepo) async -> GitOutcome) async -> GitOutcome?`:
      - cancel the stored background fetch and await its end;
      - set busy, run the action, refresh, clear busy;
      - set `message` from the outcome;
      - return nil if already busy.
    - `func dismissMessage(repoPath:)`
  - `AppModel` extension:
    - `let git = GitModel()` is a stored property added in `AppModel.swift`.
    - `func gitRefresh(_ serviceID: String, fetchMaxAge: TimeInterval?)`.
    - `func gitPull(_ serviceID: String)`.
    - `func gitSwitch(_ serviceID: String, to target: BranchTarget)`.
    - After `.pulled(n)` / `.switched(name)`:
      1. Append the log line to every supervisor whose repo's toplevel equals the tree root.
      2. Then, if any of those supervisors is active, call `Alerts.confirm(…restart prompt…)`. "Yeniden başlat" calls `restart(id)` for each active one.
- Rulings carried from the spec:
  - Message auto-hide: success messages clear after 5 s via a delayed Task that checks the message id. Errors stay until dismissed.
  - `.blocked(files)` produces the "N dosyada kaydedilmemiş değişiklik var…" message.
- [ ] **Step 1:** Implement both files and add `let git = GitModel()` to `AppModel`.
- [ ] **Step 2: Run** `make build`. Expected: `Build complete!`. Then run `make test`: all pass.
- [ ] **Step 3: Commit.** `feat: git state model and pull/switch orchestration`

### Task 5: Git row and branch picker

**Files:**
- Create: `Sources/Salter/Views/GitRow.swift`
- Modify: `Sources/Salter/Views/ServiceDetailView.swift` (insert `GitRow(serviceID:)` between the command line and the resource cards; refresh hooks)

**Interfaces:**
- Consumes: `model.git.tree(forRepo:)`, `gitRefresh`, `gitPull`, `gitSwitch`, `Theme` and the button styles.

- [ ] **Step 1: `GitRow`.** Hidden when there is no tree (not a git repo). Otherwise an HStack(spacing: 10):
  - **Branch button:** `QuietButtonStyle(height: 24)` with the label `Image(systemName: "arrow.triangle.branch")` plus the branch name, or the short commit followed by "ayrık HEAD" in text3. It opens a `.popover` with `BranchPicker`.
  - **Sync text:** 12pt text3, monospaced digits:
    - "upstream yok" when there is no upstream;
    - "güncel" when ahead and behind are both 0;
    - otherwise "↓behind ↑ahead", omitting a zero part.
    - Tooltip "son kontrol N önce" via `ResourceFormat.duration`.
  - **Dirty marker:** "● N değişiklik" in warn color, 12pt. Its `.help` lists up to 10 files, one per line.
  - **Çek:** `Image(systemName: "arrow.down")` + "Çek", Quiet 24. Disabled when there is no upstream, when detached, or when busy.
  - A `ProgressView().controlSize(.small)` when busy.
  - **Message:** 12pt; text2 for success, err for errors. Errors have a "×" dismiss button and a "Ayrıntı" disclosure (popover) showing `detail` monospaced when present.
- [ ] **Step 2: `BranchPicker`** (popover, width 300, max height 360, `Theme.bg`):
  - A search field. When the tree is dirty, a warn banner shows the blocked message, and all rows are disabled except the current one.
  - "Yerel" `SectionLabel` with rows that show a check icon for the current branch.
  - "Uzak" `SectionLabel` with remoteOnly rows (name, plus the remote in text3 when it isn't "origin").
  - A small spinner at the top while `fetching`.
  - Selecting a row calls `gitSwitch` and closes the popover. Selecting the current branch only closes it.
  - On appear: `gitRefresh(serviceID, fetchMaxAge: 30)`.
- [ ] **Step 3: Refresh hooks in `ServiceDetailView`:**
  - `.task(id: id) { model.gitRefresh(id, fetchMaxAge: 300) }`;
  - `.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))` calls `gitRefresh(id, fetchMaxAge: nil)`, which reads local state only.
- [ ] **Step 4: Run** `make build`. Expected: success.
- [ ] **Step 5: Commit.** `feat: git row with branch picker and pull in the detail header`

### Task 6: Verification and install

- [ ] **Step 1: Visual check.** Add a temporary, uncommitted snapshot hook (same approach as the UI redesign: `cacheDisplay` of the main window, select `classifier-go/run` and `storefront/debug-bff`). Build with `make app`, run with `open -W --env SALTER_SNAPSHOT_DIR=… build/Salter.app`, and look at the PNGs. **Do not pull or switch the user's real repos**; read-only status and fetch are fine. Then remove the hook (`git checkout`/`rm`).
- [ ] **Step 2:** Run `make test`. Expected: all pass. Commit any `fix(ui): …` changes.
