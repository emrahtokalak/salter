# UI Redesign (Linear style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle Şalter's main window, menu-bar popover and sheets in a Linear-like visual language. Add display-name rules with aliases, readable parsed logs, and per-service resource cards.

**Architecture:** All logic lives in SalterCore as pure, tested code:
- `ServiceNaming`/`DisplayNames` (names),
- `LogLineParser` (log rows),
- `ResourceHistory`/`ResourceFormat`/`LibprocTable` (resources).

The Salter app target consumes them:
- a `Theme` file holds tokens, button styles and the status dot;
- `AppModel` caches `DisplayNames` and owns a `ResourceMonitor`;
- the views are rewritten one screen per task.

**Tech Stack:** Swift 6 toolchain (language mode v5), SwiftUI on macOS 14 and Swift Testing, built with Command Line Tools only. Sparklines are drawn with `Path`; there is no Swift Charts dependency.

**Spec:** `docs/superpowers/specs/2026-11-02-ui-redesign-design.md` (mockup: `docs/superpowers/specs/assets/2026-11-02-ui-redesign-mockup.html`)

## Global Constraints

- The word "Debug" (any case, as a word) must not appear in any UI string the app renders itself. The only exception is log *content* coming from services (e.g. a `DEBUG` level column).
- No emoji in names or in UI copy.
- UI copy is Turkish, as today.
- Dark tokens:

  | Token | Value |
  |---|---|
  | bg | `#0f1011` |
  | panel | `#141517` |
  | line | `#23252a` |
  | selection | `#1f2024` |
  | text | `#ededed` |
  | text2 | `#8a8f98` |
  | text3 | `#62666d` |
  | accent | `#5e6ad2` |
  | ok | `#4cb782` |
  | warn | `#f2c94c` |
  | err | `#eb5757` |

- Light tokens (my ruling, spec leaves them to the builder):

  | Token | Value |
  |---|---|
  | bg | `#ffffff` |
  | panel | `#f7f7f8` |
  | line | `#e6e6e8` |
  | selection | `#ececef` |
  | text | `#1b1c1f` |
  | text2 | `#6b6f76` |
  | text3 | `#9a9da3` |
  | accent | `#5e6ad2` |
  | ok | `#2f9e69` |
  | warn | `#c99a12` |
  | err | `#d64545` |

- Typography:

  | Element | Font |
  |---|---|
  | Body | 13pt |
  | Secondary | 12pt |
  | Section labels | 11pt medium, text3 |
  | Detail title | 17pt semibold |
  | Command and log | SF Mono 11.5–12pt |
  | Numbers | `monospacedDigit()` |

- Row corner radius 6pt, card radius 8pt.
- Buttons are 28pt tall with a 1px `line` border. Only "Başlat" (and sheet confirm and "Kaydet") are filled accent.
- The status dot is 7pt; when running it has a 3pt ok-colored halo at 15% opacity.
- Sampling runs every 2 s with a window of 300 s.
- `swift-tools-version 6.0`, `platforms: [.macOS(.v14)]`, no new package dependencies.
- Always test with `make test [FILTER=...]` and build with `make build`. Never use plain `swift test`.

## Review Focus

1. A multi-service repo whose launch names are only emoji, or only "Debug"/"Run", must never produce an empty or duplicate sidebar label. The rows should read "repo · 1", "repo · 2".
2. JSON-looking lines that are not objects must stay plain text and must not crash the parser:
   - `[1,2]`
   - truncated `{"a":`
   - `{"msg": 42}`
   - `{"msg": null}`
   - ANSI-prefixed JSON
3. A process that exits between `proc_listpgrppids` and `proc_pidinfo`, or a pid reused with a smaller CPU time, must not produce negative or huge CPU%.
4. Adopted services (no log stream, pgid only) still get resource cards. Stopped services show "—" without layout jumps.
5. A repo whose services are all pinned, or that has no services, must keep its repo context menu reachable in "Repolar".

---

### Task 1: Display names (`ServiceNaming`, `DisplayNames`)

**Files:**
- Create: `Sources/SalterCore/Model/ServiceNaming.swift`
- Test: `Tests/SalterCoreTests/ServiceNamingTests.swift`

**Interfaces:**
- Produces:
  - `public enum ServiceNaming { static func clean(_ raw: String) -> String; static func label(_ raw: String) -> String; static func breadcrumb(repoPath: String, roots: [String]) -> String; static func discoveredNames(_ services: [DiscoveredService], repoName: String) -> [String: String] }`
  - `public struct ServiceName: Equatable, Sendable { public var full: String; public var inGroup: String }`
  - `public struct DisplayNames: Equatable, Sendable { public init(config: AppConfig); public var services: [String: ServiceName]; public var repos: [String: String] /* by repo path */ }`

- [ ] **Step 1: Write the failing tests.** `@Suite struct ServiceNamingTests`. Add a helper `svc(_ id: String, _ name: String, kind: ServiceSource.Kind = .launchJson, alias: String? = nil) -> ServiceConfig` and a helper `repo(_ path: String, _ services: [ServiceConfig]) -> RepoConfig`.

  Tests for `clean` and `label`:

  ```swift
  @Test func cleanStripsEmojiDebugRunAndSeparators() {
      #expect(ServiceNaming.clean("🚀 Debug FastAPI") == "FastAPI")
      #expect(ServiceNaming.clean("Debug BFF") == "BFF")
      #expect(ServiceNaming.clean("API: uvicorn (debug)") == "API: uvicorn")
      #expect(ServiceNaming.clean("Run") == "")
      #expect(ServiceNaming.clean("Python: Debug Tests") == "Python: Tests")
      #expect(ServiceNaming.clean("Debug: Main") == "Main")
      #expect(ServiceNaming.clean("Runner") == "Runner")          // whole words only
      #expect(ServiceNaming.clean("  Order  Worker ") == "Order Worker")
  }
  @Test func labelFallsBackWhenCleanIsEmpty() {
      #expect(ServiceNaming.label("Debug API") == "API")
      #expect(ServiceNaming.label("Run") == "launch.json yapılandırması")
  }
  ```

  Tests for `DisplayNames(config:)`:

  - `singleServiceRepoUsesRepoName`
    - Input: `/p/acme/classifier-go` with one service "Run".
    - Expect: full and inGroup are both "classifier-go", and `repos[path] == "classifier-go"`.
  - `multiServiceRepoAddsCleanedSuffix`
    - Input: storefront with "Debug BFF" and "🚀 Debug Order Worker".
    - Expect: full "storefront · BFF", inGroup "BFF"; and "storefront · Order Worker".
  - `emptySuffixUsesPosition`
    - Input: services "Run" and "Debug".
    - Expect: "r · 1" and "r · 2".
  - `duplicateSuffixGetsNumbered`
    - Input: "Debug FastAPI" and "Run FastAPI".
    - Expect: inGroup "FastAPI" and "FastAPI 2".
  - `aliasWins`
    - Input: alias "Intent" in a multi-service repo.
    - Expect: full and inGroup are both "Intent".
  - `blankAliasIsIgnored`
    - Input: alias "  ".
    - Expect: the computed name.
  - `manualNameIsUsedAsIs`
    - Input: `.manual` service named "legacy-ear Run" in a 2-service repo.
    - Expect: full "legacy-ear Run".
  - `crossRepoCollisionAddsParentFolder`
    - Input: `/p/acme/api` and `/p/personal/api`, one service each.
    - Expect: full "api (acme)" and "api (personal)"; repo titles get the same suffix.
  - `aliasCollidingWithOtherRepoAddsParentFolder`
    - Input: alias "api" in `/p/x/foo` and repo `/p/y/api` with a single service.
    - Expect: "api (x)" and "api (y)".

  Tests for `breadcrumb` and `discoveredNames`:

  - `breadcrumbUsesRootFolderName`
    - `breadcrumb(repoPath: "/u/Projects/acme/x", roots: ["/u/Projects/acme"]) == "acme / x"`.
    - With no matching root, the parent folder name is used: `"/u/other/y"` gives "other / y".
  - `discoveredNamesFollowSameRules`
    - One discovered service gives the repo name.
    - Two discovered services give the cleaned suffixes (inGroup form).

- [ ] **Step 2: Run** `make test FILTER=ServiceNamingTests`. Expected: build FAIL, `cannot find 'ServiceNaming' in scope`.

- [ ] **Step 3: Implement.**

  `clean`:
  1. Drop every scalar with `properties.isEmoji && (isEmojiPresentation || value > 0x238C)`, plus variation selectors and ZWJ.
  2. Remove `\((?i:debug)\)`.
  3. Remove the whole words `(?i)\b(debug|run)\b`.
  4. Collapse whitespace runs.
  5. Trim the characters ` :-·` at both ends, and collapse `": "` artefacts such as "Python:  Tests".

  `DisplayNames`, per repo:
  1. Alias = trimmed non-empty `overrides.name`, or `discovered.name` for `.manual`.
  2. If there is no alias and the repo has a single service, use the repo name.
  3. Otherwise the suffix is `clean(discovered.name)`. An empty suffix becomes the 1-based position. Suffixes are then deduplicated in order with " 2", " 3", and so on.
  4. Then group all `full` values. For any value shared by services from more than one repo, append ` (<repo parent folder name>)` to `full`, and to `inGroup` when inGroup == full.
  5. Repo titles: when two repo names are equal, append the same ` (<parent>)`.

- [ ] **Step 4: Run** `make test FILTER=ServiceNamingTests`. Expected: all pass.

- [ ] **Step 5: Commit.** `git add Sources/SalterCore/Model/ServiceNaming.swift Tests/SalterCoreTests/ServiceNamingTests.swift && git commit -m "feat: service display-name rules with aliases"`

### Task 2: The "Ad" field edits the alias

**Files:**
- Modify: `Sources/SalterCore/Model/OverrideEditor.swift` (`fields(of:)`, `apply`)
- Test: `Tests/SalterCoreTests/OverrideEditorTests.swift`

**Interfaces:**
- Produces: `OverrideEditor.Fields.name` now means *alias*: it is `overrides.name ?? ""`. When `apply` sees the name changed, it sets `o.name = trimmed.isEmpty ? nil : trimmed`.

- [ ] **Step 1: Tests.**
  - Add `nameFieldShowsAliasOnly`. A service without an alias gives `fields.name == ""`; with alias "X" it gives "X".
  - Add `clearingNameRemovesAlias`. Edit the name to "  " and expect `overrides.name == nil`.
  - Add `settingNameStoresTrimmedAlias`. Edit " Intent " and expect "Intent".
  - In `editsEqualToDiscoveredClearTheOverride`, replace `edited.name = "api"` with `edited.name = ""`. The `overrides.name == nil` expectation stays.
- [ ] **Step 2: Run** `make test FILTER=OverrideEditorTests`. Expected: FAIL in `nameFieldShowsAliasOnly` (it gets "api").
- [ ] **Step 3: Implement** the semantics above.
- [ ] **Step 4: Run** `make test FILTER=OverrideEditorTests`. Expected: pass.
- [ ] **Step 5: Commit.** `feat: settings name field edits the alias`

### Task 3: Log line parsing (`LogLineParser`)

**Files:**
- Create: `Sources/SalterCore/Logs/LogLineParser.swift`
- Test: `Tests/SalterCoreTests/LogLineParserTests.swift`

**Interfaces:**
- Produces:
  - `public enum LogLevel: String, Sendable { case trace, debug, info, warn, error; public var label: String /* "TRACE","DEBUG","INFO","WARN","ERROR" */ }`
  - `public struct LogField: Equatable, Sendable { public var key: String; public var value: String }`
  - `public struct ParsedLogLine: Equatable, Sendable { public var time: Date?; public var level: LogLevel?; public var message: String; public var fields: [LogField]; public var isStructured: Bool }`
  - `public enum LogLineParser { public static func parse(_ text: String) -> ParsedLogLine }`

- [ ] **Step 1: Tests.**

  JSON lines:

  - `jsonExtractsMessageLevelTimeAndFields`
    - Input: `{"@timestamp":"2026-11-02T20:27:37.123Z","level":"info","message":"application_started","method":"hybrid"}`
    - Expect: `isStructured`, message "application_started", level `.info`.
    - Expect: time == `ISO8601("2026-11-02T20:27:37.123Z")`.
    - Expect: fields == `[method=hybrid]`.
  - `jsonFieldVariants`
    - `msg` + `log_level: "WARNING"` gives `.warn`.
    - `severity: "ERROR"` gives `.error`.
    - `ts: 1793651994.5` (epoch seconds) gives that Date.
    - `time: 1793651994500` (epoch ms, > 1e11) gives that Date.
    - Pino numeric `level: 50` gives `.error`; 30 gives `.info`; 40 gives `.warn`; 20 gives `.debug`; 10 gives `.trace`.
  - `jsonDropsFieldsEqualToMessage`
    - Input: `{"msg":"x","event_type":"x","a":1}`
    - Expect: fields == `[a=1]`.
  - `jsonNestedValuesRenderAsCompactJSON`
    - Input: `{"msg":"x","ctx":{"k":1}}`
    - Expect: the field value is `{"k":1}`.
  - `jsonFieldsSortedByKey` (keys sorted ascending)
  - `nonObjectOrInvalidJSONIsPlain`
    - Inputs: `[1,2]`, `{"a":`, `{"msg": 42}`, `{"msg": null}`.
    - Expect: the first two are `isStructured == false` with message equal to the input.
    - Expect: for the last two, `isStructured == true` with message `"42"`/`""`, and the 42/null value is not repeated as a field.
  - `ansiPrefixedJSONIsParsed`
    - Input: `"\u{1B}[0m{\"msg\":\"hi\"}"`
    - Expect: message "hi".

  Logfmt lines:

  - `logfmtSlogLine`
    - Input: `time=2026-11-02T23:27:37.000+03:00 level=WARN msg="search failed" dropped_total=2`
    - Expect: structured, `.warn`, message "search failed", fields `[dropped_total=2]`, and the time parsed.
  - `textWithEqualsButNoMsgIsPlain`
    - Input: `a=b c=d`
    - Expect: `isStructured == false`.

  Plain-text level detection (all `isStructured == false`, `time == nil`, message unchanged):

  | Test | Input | Expected level |
  |---|---|---|
  | `uvicornPrefix` | `INFO:     Started server process [123]` | `.info` |
  | `bracketLevel` | `[WARN] slow` | `.warn` |
  | `springBootToken` | `2026-11-02 23:27:37.123  ERROR 1234 --- [main] o.s.Foo : boom` | `.error` |
  | `levelEqualsInText` | `foo level=debug bar` | `.debug` |
  | `tokenAfter60CharsIgnored` | 70 x's then ` ERROR` | `nil` |
  | `noLevel` | `GET /health 200` | `nil` |
  | `wordInsideIdentifierIgnored` | `ERRORS_TOTAL=3` | `nil` |

- [ ] **Step 2: Run** `make test FILTER=LogLineParserTests`. Expected: build FAIL, `cannot find 'LogLineParser'`.

- [ ] **Step 3: Implement.**
  1. Strip ANSI with `ANSIParser.strip` for detection only.
  2. If the stripped, trimmed text starts with `{`, try `JSONSerialization` with `.fragmentsAllowed` off. It must yield `[String: Any]`; anything else is plain.
  3. Key lists:
     - message: `message`, `msg`
     - level: `level`, `log_level`, `severity`, `levelname`
     - time: `@timestamp`, `timestamp`, `time`, `ts`
  4. Level synonyms:
     - `warning` → warn
     - `err`, `fatal`, `critical`, `panic` → error
     - `information` → info
     - numbers: ≥50 error, ≥40 warn, ≥30 info, ≥20 debug, else trace
  5. Time parsing:
     - ISO8601 with and without fractional seconds;
     - numbers > 1e11 are ms, otherwise seconds.
  6. Logfmt:
     - Tokenize `key=value` with double-quoted values (`\"` escapes).
     - The line is logfmt only if every token is `key=value` and the line has a `msg` or `message` key.
  7. Plain level detection, in this order (case-insensitive):
     1. leading `LEVEL:`
     2. `[LEVEL]`
     3. `level=LEVEL`
     4. a standalone token in the first 60 characters, bounded by non-alphanumeric and non-underscore characters

- [ ] **Step 4: Run** `make test FILTER=LogLineParserTests`. Expected: pass.

- [ ] **Step 5: Commit.** `feat: parse JSON, logfmt and plain log lines into time/level/message`

### Task 4: Resource sampling core

**Files:**
- Create: `Sources/SalterCore/Process/ResourceSampler.swift`
- Create: `Sources/SalterCore/Process/ResourceFormat.swift`
- Test: `Tests/SalterCoreTests/ResourceSamplerTests.swift`

**Interfaces:**
- Produces:
  - `public struct ProcessSample: Equatable, Sendable { public var pid: pid_t; public var cpuNanos: UInt64; public var residentBytes: UInt64 }`
  - `public protocol ProcessTable: Sendable { func pids(inGroup pgid: pid_t) -> [pid_t]; func sample(_ pid: pid_t) -> ProcessSample? }`
  - `public extension ProcessTable { func samples(group: pid_t) -> [ProcessSample] }`
  - `public struct LibprocTable: ProcessTable { public init() }`
  - `public struct ResourcePoint: Equatable, Sendable { public var date: Date; public var cpuPercent: Double?; public var memoryBytes: UInt64; public var processCount: Int; public var mainPID: pid_t? }`
  - `public struct ResourceHistory: Equatable, Sendable { public static let window: TimeInterval = 300; public private(set) var points: [ResourcePoint]; public init(); public mutating func record(_ samples: [ProcessSample], mainPID: pid_t?, at date: Date); public var latest: ResourcePoint? }`
  - `public enum ResourceFormat { static func cpu(_ percent: Double) -> String; static func memory(_ bytes: UInt64) -> String; static func duration(_ seconds: TimeInterval) -> String }`

- [ ] **Step 1: Tests.** Use `t0 = Date(timeIntervalSince1970: 1000)` and `s(pid, cpuSeconds, mb)`.

  `ResourceHistory`:

  | Test | Expected |
  |---|---|
  | `firstRecordHasNoCPU` | `points.count == 1`; cpuPercent nil; memory equals the sum; processCount equals the number of samples |
  | `cpuPercentIsCPUDeltaOverWallTime` | pid1 1 s at t0, then 2 s at t0+2 gives 50.0 |
  | `multipleProcessesCanExceed100` | two pids each +2 s over 2 s gives 200.0 |
  | `newPidCountsForMemoryNotCPU` | pid2 appears at t1: CPU uses only pid1's delta; memory and count include pid2 |
  | `cpuTimeGoingBackwardsCountsZero` | a reused pid gives cpuPercent 0, not negative |
  | `vanishedPidIsIgnored` | — |
  | `pointsOlderThanWindowAreTrimmed` | record at t0, t0+200, t0+400: the first is gone |

  Then:

  - `formatting`
    - `cpu(3.42) == "%3,4"`, `cpu(27.6) == "%28"`, `cpu(0) == "%0"`.
    - `memory(412 << 20) == "412 MB"`, `memory(1610612736) == "1,5 GB"`.
    - Durations:

      | Input | Output |
      |---|---|
      | `35` | "35 sn" |
      | `240` | "4 dk" |
      | `7500` | "2 sa 5 dk" |
      | `90000` | "1 g 1 sa" |
  - `libprocSeesOwnProcessGroup` (live)
    - `LibprocTable().pids(inGroup: getpgrp())` contains `getpid()`.
    - Busy-loop about 0.3 s between two `sample(getpid())` calls.
    - The cpuNanos delta is between 0.1e9 and 3e9. This catches Mach-tick vs nanosecond mistakes.
    - `residentBytes > 1 << 20`.

- [ ] **Step 2: Run** `make test FILTER=ResourceSamplerTests`. Expected: build FAIL.

- [ ] **Step 3: Implement.**
  - `LibprocTable.pids`:
    - Call `proc_listpgrppids(pgid, buffer, bytes)`. It returns a pid **count**, not bytes; verify with the live test.
    - Grow the buffer (start at 64) when it comes back full.
  - `LibprocTable.sample`:
    - Read `proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &proc_taskinfo, size)` and expect `== size`.
    - `cpuNanos = (pti_total_user + pti_total_system) * numer / denom` from `mach_timebase_info`, computed once.
    - `residentBytes = pti_resident_size`.
  - `ResourceHistory` keeps the previous `[pid_t: UInt64]` and the previous date privately.
    - CPU% = Σ max(0, cur − prev) over pids present in both, ÷ wall elapsed, × 100.
    - A negative delta counts 0.
  - `ResourceFormat` uses a `tr_TR` comma decimal and a leading `%`:
    - CPU below 10 has 1 decimal, otherwise none.
    - Memory: MB is an integer below 1024 MB, GB has 1 decimal.
    - Duration shows the largest two units (g/sa/dk/sn), with only one unit below 1 h when minutes are 0. 240 → "4 dk".

- [ ] **Step 4: Run** `make test FILTER=ResourceSamplerTests`. Expected: pass. Then run `make test`: whole suite green.

- [ ] **Step 5: Commit.** `feat: process-group resource sampling and formatting`

### Task 5: Theme foundation and AppModel naming and resources wiring

**Files:**
- Create: `Sources/Salter/Views/Theme.swift`
- Create: `Sources/Salter/ResourceMonitor.swift`
- Modify: `Sources/Salter/Views/StatusStyle.swift` (status colors → tokens, `StatusDot` 7pt + halo, add `ServiceStatus.pillLabel(since:)`)
- Modify: `Sources/Salter/AppModel.swift`

**Interfaces:**
- Consumes:
  - `DisplayNames`, `ServiceNaming.breadcrumb` (Task 1)
  - `ResourceHistory`, `LibprocTable`, `ResourceFormat` (Task 4)
- Produces:
  - `enum Theme { static let bg, panel, line, selection, text, text2, text3, accent, ok, warn, err: Color }`. Each is dynamic light/dark via `NSColor(name:dynamicProvider:)` keyed on `appearance.bestMatch(from: [.darkAqua, .aqua])`.
  - `struct QuietButtonStyle: ButtonStyle`: 28pt, 12.5pt text, 1px `Theme.line` border, hover/pressed `Theme.selection`.
  - `struct PrimaryButtonStyle: ButtonStyle`: accent fill, white text.
  - `struct SectionLabel: View { init(_ title: String) }`.
  - `struct Card<Content: View>: View`: 8pt radius, 1px line, panel fill.
  - `AppModel` additions:
    - `private(set) var names: DisplayNames`, recomputed in `init` and `mutate`;
    - `displayName(_:)` returns `names.services[id]?.full ?? id`;
    - `inGroupName(_ id: String) -> String`;
    - `repoTitle(_ path: String) -> String`;
    - `breadcrumb(of id: String) -> String`;
    - `setAlias(_ id: String, _ alias: String)`: trimmed, empty → nil, via the `updateOverrides` path;
    - `let resources = ResourceMonitor()`, started in `bootstrap()`.
  - `@MainActor @Observable final class ResourceMonitor`:
    - `private(set) var histories: [String: ResourceHistory]`;
    - `func start(supervisors: @escaping @MainActor () -> [ServiceSupervisor])`.
    - Every 2 s it samples each supervisor with a pgid, off-main (`Task.detached { LibprocTable().samples(group:) }`).
    - It resets a history when that service's pgid changes, and removes it when the pgid is nil.
    - `func latest(_ id: String) -> ResourcePoint?`.
- Rulings carried from the spec:
  - Sampling continues for every active service, not just the selected one. That is a few syscalls per 2 s, and history stays full.
  - `AppModel.launch` alerts use `displayName(id)` instead of `definition.name`.

- [ ] **Step 1:** Write `Theme.swift` and update `StatusStyle.swift`.
  - Status colors: stopped → text3, starting/stopping → warn, running → ok, crashed → err.
  - `pillLabel(since startedAt: Date?, now: Date)` gives:
    - "Çalışıyor · 4 dk", using `ResourceFormat.duration`;
    - "Durdu";
    - "Başlatılıyor…";
    - "Durduruluyor…";
    - "Çöktü (kod)".
- [ ] **Step 2:** `ResourceMonitor.swift` and the AppModel additions.
- [ ] **Step 3: Run** `make build`. Expected: `Build complete!`. Then run `make test`: all green.
- [ ] **Step 4: Commit.** `feat: theme tokens, display-name cache and resource monitor`

### Task 6: Main window and sidebar

**Files:**
- Modify: `Sources/Salter/Views/MainWindow.swift`
- Modify: `Sources/Salter/Views/ServiceRow.swift`

**Interfaces:**
- Consumes:
  - `Theme`, `SectionLabel`, `StatusDot`
  - `model.displayName`, `inGroupName`, `repoTitle`, `setAlias`
- Produces: `struct RepoMenu: View { let repo: RepoConfig; @Binding var sheet: SheetRoute? }`, the repo actions as menu items, reused by the group row and the flat row.

- [ ] **Step 1: Rewrite the `Sidebar`.**
  - Use `List(selection:)` with `.scrollContentBackground(.hidden)` and `.background(Theme.panel)`. This removes the vibrancy.
  - Keep `.listStyle(.sidebar)` only if it still shows `Theme.panel`; otherwise use `.plain` with custom row insets.
  - Rows:
    - 6pt-radius selection is `Theme.selection`.
    - A row is `StatusDot` · name (13pt, text) · port (`:8080`, 11.5pt text3, monospacedDigit) · `questionmark.circle` (warn) if `sourceMissing`.
    - There is no permanent play/stop button. Show `StartStopButton` only on hover (`.onHover`).
  - "Sabitlenenler" has a `SectionLabel`, full names and `onMove`. Keep the empty hint text in 12pt text3.
  - "Repolar" has a `SectionLabel` with a trailing "+" button that calls the existing NSOpenPanel flow, moved from the toolbar. For each repo:
    - With exactly 1 service that is unpinned: a flat row showing the full name, tagged with the id. Its context menu is the service menu, then `Divider()`, then `RepoMenu`.
    - Otherwise: a `DisclosureGroup`. The label is `repoTitle` (12.5pt text2) plus a suggestions count badge ("N yeni", text3) when > 0. The children are the unpinned services by `inGroupName`. The context menu is `RepoMenu`. A group with no visible children still renders (Review Focus 5).
  - The new-repos card goes in `.safeAreaInset(edge: .bottom)`: a 1px-bordered 8pt card reading "**N** yeni repo bulundu" and "İncele →", which sets `sheet = .newRepos`.
- [ ] **Step 2: Rename.**
  - `ServiceContextMenu` gains "Yeniden adlandır…", which sets a `renaming: String?` state on the Sidebar.
  - `.alert("Yeniden adlandır", isPresented:)` contains:
    - a `TextField`, prefilled with the current alias or the display name;
    - "Kaydet", which calls `setAlias`;
    - "İptal".
  - Message: "Boş bırakırsan varsayılan ad kullanılır."
- [ ] **Step 3: Window.**
  - The detail empty state uses `Theme.bg`, the text "Bir servis seç" (text2) and a 12pt text3 subtitle.
  - The toolbar keeps "Yeniden tara" and "Tümünü durdur" as plain icon buttons.
  - The `navigationSplitViewColumnWidth` minimum is 220, ideal 260.
- [ ] **Step 4: Run** `make build`. Expected: success. `grep -rn "sparkles\|ellipsis.circle" Sources/Salter/Views/MainWindow.swift` returns nothing.
- [ ] **Step 5: Commit.** `feat: Linear-style sidebar with repo groups and rename`

### Task 7: Detail header, resource cards and tabs

**Files:**
- Modify: `Sources/Salter/Views/ServiceDetailView.swift`
- Create: `Sources/Salter/Views/ResourceCards.swift`

**Interfaces:**
- Consumes:
  - `model.resources.histories[id]`
  - `ResourceFormat`
  - `pillLabel`
  - `model.breadcrumb(of:)`
  - `QuietButtonStyle`, `PrimaryButtonStyle`, `Card`
- Produces: `struct Sparkline: View { let values: [Double]; let color: Color }`, a `Path` polyline scaled to max(values, 1), with a 12% opacity fill.

- [ ] **Step 1: Header**, with 22pt horizontal and 18pt top padding on `Theme.bg`:
  - The breadcrumb line (12pt text3).
  - A row with:
    - title: displayName, 17pt semibold;
    - status pill: capsule, status color text, 10% fill, 25% border;
    - "sahiplenildi" chip when adopted (text3, 1px line);
    - one port button per port (`localhost:8080 ↗`, 12pt text2, 1px line);
    - Spacer;
    - pin icon button, 28×28 Quiet;
    - "Yeniden başlat" and "Durdur" (Quiet) when active, otherwise "Başlat" (Primary, ⌘R).
  - The command in SF Mono 12pt text2, selectable, `lineLimit(2)`.
  - The existing banners restyled: 8pt card with a warn left icon and 12pt text inside the header padding.
  - A pill timer refresh via `TimelineView(.periodic(from: .now, by: 30))`.
- [ ] **Step 2: `ResourceCards`**, an HStack of 4 equal `Card`s, each 11pt text3 title plus 17pt value:
  - CPU: `ResourceFormat.cpu` plus a sparkline of cpuPercent (accent).
  - Bellek: `memory` plus a sparkline (ok).
  - Süreçler: `processCount` with "PID <mainPID>" in text3.
  - Çalışma süresi: `duration(now − startedAt)`.
  - When the service is not active or has no point, show "—" with the same height (fixed 64pt).
  - `mainPID` = `supervisor.runtimeRecord?.pid`, passed in by `ResourceMonitor` at record time.
- [ ] **Step 3: Tabs.** Replace the segmented Picker with an `UnderlineTabs` HStack:
  - "Log" and "Ayarlar", 12.5pt.
  - The selected tab is text color with a 2pt bottom bar; the others are text2.
  - A 1px `Theme.line` divider goes below.
- [ ] **Step 4: Run** `make build`. Expected: success.
- [ ] **Step 5: Commit.** `feat: detail header with status pill, resource cards and underline tabs`

### Task 8: Log view

**Files:**
- Modify: `Sources/Salter/Views/LogView.swift`

**Interfaces:**
- Consumes: `LogLineParser.parse`, `LogLevel.label`, `ANSIRender.attributed`

- [ ] **Step 1: Toolbar**, 8pt vertical and 22pt horizontal padding, followed by a line divider:
  - A search field: 1px-bordered, 6pt radius, max 320pt, placeholder "Logda ara…".
  - "Otomatik kaydır" as a small checkbox, Spacer, "<N> satır" (12pt text3), then "Log dosyası" and "Temizle" as Quiet small buttons.
- [ ] **Step 2: Rows** (`LogLineView`), SF Mono 11.5pt with line height ≈1.65 (`lineSpacing(4)`) on `Theme.bg`:
  - System lines (`kind == .system`) are centered text3 text: "— <text> · HH:mm:ss —".
  - Other lines are an HStack(alignment: .firstTextBaseline):
    - time `HH:mm:ss` (text3, fixed width): `parsed.time ?? line.date`, local time;
    - level label, width 44, colored:

      | Level | Color |
      |---|---|
      | info | `#6b9bd2` |
      | warn | `Theme.warn` |
      | error | `Theme.err` |
      | debug/trace | text3 |
      | none | blank |
    - message: structured lines show plain text in `#c9cbcf` (dark) or text (light), followed by fields joined as `key=value` in text3; plain lines use `ANSIRender.attributed(line.text)`.
  - Parse inside the row view (lazy, only visible rows). The search filter stays on raw `ANSIParser.strip(text)`.
  - Use one static `DateFormatter("HH:mm:ss")`.
- [ ] **Step 3: Run** `make build`. Expected: success.
- [ ] **Step 4: Commit.** `feat: log rows with time and level columns`

### Task 9: Service settings tab

**Files:**
- Modify: `Sources/Salter/Views/ServiceSettingsForm.swift`

**Interfaces:**
- Consumes: Task 2 alias semantics (`fields.name` is the alias), `model.displayName`

- [ ] **Step 1:** Replace `Form(.grouped)` with a ScrollView of stacked groups on `Theme.bg`, max width 640, 22pt padding. Each group has a `SectionLabel` and a `Card` of rows: a label column of 140pt (12pt text2) and the control.
  - **Genel:**
    - "Ad": `TextField` with the prompt set to the computed name. The footnote reads "Takma ad; boş bırakırsan varsayılan ad kullanılır." (11pt text3).
    - "Komut" (mono), "Çalışma klasörü", "Port", and the reload toggle when supported.
  - **Ortam değişkenleri:** Env dosyası, the extra-variables editor (mono, 1px border) and the discovered-variables disclosure.
  - Footer row:
    - left: "Keşfedilen değerlere dön" (Quiet);
    - right: "Kaydedildi" (text3) and "Kaydet" (Primary, ⌘S);
    - below: "Değişiklikler bir sonraki başlatmada geçerli olur." (11pt text3).
  - **Tehlikeli bölge:** a card with an err-tinted 1px border holding "Servisi kaldır" (err text, Quiet).
  - Text fields use `.textFieldStyle(.plain)` with a 1px line border, 6pt radius and 28pt height.
- [ ] **Step 2: Run** `make build`. Expected: success.
- [ ] **Step 3: Commit.** `feat: grouped service settings`

### Task 10: Menu bar popover

**Files:**
- Modify: `Sources/Salter/Views/MenuBarView.swift`

- [ ] **Step 1:** Width 320 on `Theme.bg`.
  - Header: "Şalter" (13pt semibold) plus "N çalışıyor" (12pt text3), padding 14/12/8.
  - Rows, with 6pt horizontal margin and 6pt radius, hovered `Theme.selection`:
    - `StatusDot` · full display name · port (11.5pt text3) or "çöktü" for crashed;
    - one action button: ■ `stop.fill` when active, ▶ `play.fill` when stopped, ↻ `arrow.clockwise` (restart) when crashed. Text3 icons, borderless.
  - Tapping the row (`.contentShape(Rectangle()).onTapGesture`) sets `model.selection = id`, opens the "main" window and activates the app.
  - The log button and the second (repo · status) line are removed.
  - Footer: a line divider, then "Pencereyi aç", "Tümünü durdur" (disabled at 0) and "Çık" as 12pt text2 plain buttons.
  - The empty state reads "Sabitlenmiş servis yok. Ana pencerede bir servise sağ tıklayıp “Sabitle” diyebilirsin." (12pt text3).
- [ ] **Step 2: Run** `make build`. Expected: success.
- [ ] **Step 3: Commit.** `feat: compact menu bar popover`

### Task 11: Sheets, app settings and the "Debug" sweep

**Files:**
- Modify: `Sources/Salter/Views/RepoSheets.swift`
- Modify: `Sources/Salter/Views/SettingsView.swift`
- Modify: `Sources/SalterCore/Discovery/LaunchConfigTranslator.swift:34`
- Test: `Tests/SalterCoreTests/LaunchConfigTranslatorTests.swift:145`
- Test: `Tests/SalterCoreTests/RepoScannerTests.swift:86`

**Interfaces:**
- Consumes: `ServiceNaming.discoveredNames`, `ServiceNaming.label`, `Theme`, the button styles

- [ ] **Step 1: Tests first.**
  - In `LaunchConfigTranslatorTests`, add `preLaunchTaskWarningUsesCleanLabel`. A config named "Debug API" with preLaunchTask "gen" warns "API: preLaunchTask 'gen' çalıştırılmıyor".
  - Update `RepoScannerTests.preLaunchTaskWarningSurfaces` to expect "launch.json yapılandırması: preLaunchTask 'gen' çalıştırılmıyor".
  - Run `make test FILTER=preLaunchTask`. Expected: FAIL.
- [ ] **Step 2:** Use `ServiceNaming.label(config.name)` in the warning. Run the same filter. Expected: pass.
- [ ] **Step 3: Sheets.**
  - Sheet chrome is `Theme.bg`, a 17pt semibold title, a 12pt text2 subtitle and 20pt padding.
  - `SheetButtons` use Quiet "İptal" and Primary confirm.
  - `ServicePickerList` shows `ServiceNaming.discoveredNames(services, repoName:)` instead of `definition.name`.
  - `SkippedNote` shows `ServiceNaming.label(name)`.
  - The title "Keşfedilen servisler · <repo>" stays.
  - Lists use `.scrollContentBackground(.hidden)` inside a 1px-bordered card.
- [ ] **Step 4: App settings window.** Same grouped-card style as Task 9 (Taranan klasörler, Genel, Shell ortamı, Dosyalar), at 520×520.
- [ ] **Step 5: Sweep.** `grep -rniw "debug" Sources/Salter` must return no UI string literal; matches in identifiers or comments are OK.
- [ ] **Step 6: Run** `make build`, then `make test`. Expected: success, all tests green.
- [ ] **Step 7: Commit.** `feat: restyle sheets and app settings; no Debug wording`

### Task 12: Visual verification and install

- [ ] **Step 1:** Run `make install`, then `open ~/Applications/Salter.app` (quit the running instance first: `osascript -e 'quit app "Salter"'`).
- [ ] **Step 2:** Capture screenshots with `screencapture -x -l <windowID>`, getting the window id via `osascript`/`GetWindowList` (or `screencapture -x` for the full screen). Do this for the main window in dark and light (`defaults write -g AppleInterfaceStyle`; do **not** change the user's global theme; if light cannot be checked without that, record it as not verified). Compare against the mockup: no vibrancy, tokens visible, names cleaned, log columns, resource cards.
- [ ] **Step 3:** Fix visible defects found. Each fix is a commit `fix(ui): …`.
