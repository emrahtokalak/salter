# Multi-language Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Şalter discovers runnable services for Go, Rust, Node/TS, Python, Java and .NET repos from `.vscode/launch.json` and from project manifests.

**Architecture:** `LaunchConfigTranslator` dispatches per launch type (python, go, node, lldb; java/coreclr skipped). New `ManifestDetector`s (Go, Rust, Java, .NET) run only for ecosystems launch.json produced no service for. `RepoScanner` orchestrates: launch.json → package.json (with node dedup) → manifest detectors.

**Tech Stack:** Swift 6 toolchain (language mode v5), SwiftPM, Swift Testing. No external dependencies.

**Spec:** `docs/superpowers/specs/2026-11-02-multi-language-discovery-design.md`

## Global Constraints

- No new SPM dependencies (TOML reader is hand-written).
- User-visible strings (skip reasons, warnings) in Turkish, matching existing tone.
- Existing `ServiceSource` values for launch.json/package.json must not change; all existing tests keep passing.
- New services: cwd = repo root, envFile = `<repo>/.env`, `supportsReload = false`.
- Manifest source name format `"<ecosystem>:<relative target>"`, deterministic (sort all directory listings).
- Excluded directories for manifest scans: hidden, `vendor`, `node_modules`, `target`, `build`, `bin`, `obj`, `dist`, `testdata`. Max depth 4.
- Run tests with `make test` (optionally `FILTER=<Suite>`); never plain `swift test` (SDK pin lives in the Makefile).

## Review Focus

1. Go launch.json that contains only test/`${fileDirname}` configs must not block go.mod detection → test in Task 6 (`goModUsedWhenLaunchJsonHasOnlyGoTests`).
2. Repo path containing spaces → Go relative program path and commands stay correct arrays → test in Task 3 (`goProgramRelativeToCwdWithSpaces`).
3. Rescan stability: two scans of the same repo give identical ids/sources (filesystem order independence) → test in Task 5 (`detectionIsDeterministic`).
4. `cmd/<x>` containing only `_test.go` or a non-main package yields no service → test in Task 5 (`ignoresNonMainAndTestOnlyDirs`).
5. Cargo.toml with comments, inline `# ...` after values and multi-line `members` arrays → test in Task 7 (`parsesCommentsAndMultilineArrays`).

---

### Task 1: `ServiceSource.manifest` and tolerant kind decoding

**Files:**
- Modify: `Sources/SalterCore/Model/ServiceModels.swift`
- Test: `Tests/SalterCoreTests/ModelTests.swift`

**Interfaces:**
- Produces: `ServiceSource.Kind.manifest`; `static func manifest(_ target: String) -> ServiceSource`; `Kind` decodes unknown raw values as `.manual`.

- [ ] **Step 1: Write failing tests**

```swift
@Test func manifestSourceRoundTrips() throws {
    let s = ServiceSource.manifest("go:cmd/api")
    #expect(s.kind == .manifest && s.name == "go:cmd/api")
    let back = try JSONDecoder().decode(ServiceSource.self, from: JSONEncoder().encode(s))
    #expect(back == s)
}

@Test func unknownSourceKindDecodesAsManual() throws {
    let s = try JSONDecoder().decode(ServiceSource.self, from: Data(#"{"kind":"future","name":"x"}"#.utf8))
    #expect(s.kind == .manual)
    #expect(s.name == "x")
}
```

- [ ] **Step 2: Run** `make test FILTER=ModelTests` — expect compile failure (`manifest` missing).
- [ ] **Step 3: Implement.** Add `case manifest` to `Kind`; give `Kind` a custom `init(from:)` that reads a single string and falls back to `.manual`; add the `manifest(_:)` factory.
- [ ] **Step 4: Run** `make test FILTER=ModelTests` — PASS.
- [ ] **Step 5: Commit** `feat: manifest service source and tolerant source-kind decoding`

### Task 2: Parse the extra launch.json fields

**Files:**
- Modify: `Sources/SalterCore/Discovery/LaunchConfig.swift`
- Test: `Tests/SalterCoreTests/LaunchJsonParserTests.swift`

**Interfaces:**
- Produces new `LaunchConfig` properties: `mode: String?`, `buildFlags: [String]` (string → `ShellWords.split`, list kept), `runtimeExecutable: String?`, `runtimeArgs: [String]`, `cargoArgs: [String]?` (nil when no `cargo` object; from `cargo.args`), `preLaunchTask: String?`.

- [ ] **Step 1: Failing test** `parsesGoNodeAndCargoFields`: one config `{ "name":"g", "type":"go", "mode":"debug", "buildFlags":"-tags dev", "preLaunchTask":"gen" }` → `mode == "debug"`, `buildFlags == ["-tags","dev"]`, `preLaunchTask == "gen"`, `cargoArgs == nil`; second `{ "name":"n", "runtimeExecutable":"npm", "runtimeArgs":["run","dev"] }` → fields set; third `{ "name":"r", "cargo": { "args": ["build","--bin=srv"] } }` → `cargoArgs == ["build","--bin=srv"]`.
- [ ] **Step 2: Run** `make test FILTER=LaunchJsonParserTests` — FAIL (compile).
- [ ] **Step 3: Implement** the properties and their parsing in `config(from:)`.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat: parse go/node/cargo launch fields`

### Task 3: Ecosystems, translator dispatch and Go launch configs

**Files:**
- Create: `Sources/SalterCore/Discovery/Ecosystem.swift`
- Modify: `Sources/SalterCore/Model/ServiceModels.swift` (`TranslationResult`), `Sources/SalterCore/Discovery/LaunchConfigTranslator.swift`
- Create fixture: `Tests/SalterCoreTests/Fixtures/classifier-go/launch.json` (verbatim copy of the user's file)
- Test: `Tests/SalterCoreTests/LaunchConfigTranslatorTests.swift`

**Interfaces:**
- Produces: `public enum Ecosystem: String, Sendable, CaseIterable { case go, rust, node, python, java, dotnet }` with `static func forLaunchType(_ type: String) -> Ecosystem?` (`go`→go, `lldb`/`codelldb`→rust, `node`/`pwa-node`→node, `debugpy`/`python`→python, `java`→java, `coreclr`→dotnet).
- `TranslationResult` gains `warnings: [String]` and `ecosystems: Set<Ecosystem>` (ecosystems that produced ≥1 service), both defaulted in `init` so existing call sites compile.
- `LaunchConfigTranslator.Candidate` gains `ecosystem: Ecosystem`. `candidate(from:repo:)` keeps the common checks (request, test, variables) then switches on type to `pythonCandidate`, `goCandidate` (this task), `nodeCandidate`/`rustCandidate` (Task 4). Python behaviour is unchanged.
- Skip reasons: test → `"test konfigürasyonu"` (Go: `mode == "test"`); missing program → `"program tanımlı değil"`.
- `preLaunchTask` → warning `"<name>: preLaunchTask '<task>' çalıştırılmıyor"` (only for configs that become services).

- [ ] **Step 1: Failing tests**

```swift
@Test func intentClassifierGoRunAndDebugMerge() throws {
    let r = try translate("classifier-go")
    #expect(r.services.count == 1)
    let s = try #require(r.services.first)
    #expect(s.id == "classifier-go/run")
    #expect(s.source == .launchJson("Run"))
    #expect(s.definition.command == ["go", "run", "./cmd/classifier"])
    #expect(s.definition.cwd == "/w/classifier-go")
    #expect(s.definition.envFile == "/w/classifier-go/.env")
    #expect(!s.definition.supportsReload)
    #expect(r.skipped.map(\.name) == ["Debug Tests (current package)"])
    #expect(r.ecosystems == [.go])
}

@Test func goExecModeBuildFlagsAndPreLaunchTask() // exec: command == ["/w/x/bin/api", "-port", "9000"], portHint 9000;
// debug with buildFlags "-tags dev", program "${workspaceFolder}" → ["go","run","-tags","dev","."];
// preLaunchTask "gen" → r.warnings == ["A: preLaunchTask 'gen' çalıştırılmıyor"]

@Test func goProgramRelativeToCwdWithSpaces() // repo "/w/my repo", cwd "${workspaceFolder}/svc",
// program "${workspaceFolder}/svc/cmd/a" → ["go","run","./cmd/a"]; program outside cwd → absolute path
```

- [ ] **Step 2: Run** `make test FILTER=LaunchConfigTranslatorTests` — FAIL.
- [ ] **Step 3: Implement.** Go: `mode == "exec"` → `[program] + args`; otherwise `["go","run"] + buildFlags + [rel] + args` where `rel` is `"."` when program == cwd, `"./" + suffix` when program is under cwd, else the absolute program. Port hint: `--port`/`-port` (with `=` forms) then `env.PORT`.
- [ ] **Step 4: Run** full `make test` — PASS (existing Python tests unchanged).
- [ ] **Step 5: Commit** `feat: translate Go launch configs`

### Task 4: Node and Rust launch configs; java/coreclr skip

**Files:**
- Modify: `Sources/SalterCore/Discovery/LaunchConfigTranslator.swift`
- Test: `Tests/SalterCoreTests/LaunchConfigTranslatorTests.swift`

**Interfaces:** Consumes Task 3 dispatch. Skip reasons (exact):
- java / coreclr → `"proje dosyasından çalıştırılıyor"` (does not count in `ecosystems`).
- node `.ts` program without runtimeExecutable → `"TypeScript programı için runtimeExecutable gerekli"`.
- lldb without cargo block → `"cargo bloğu yok; Cargo.toml kullanılıyor"`; cargo args containing `test` → `"test konfigürasyonu"`.

- [ ] **Step 1: Failing tests** (inline JSON via `LaunchJsonParser.parse(Data(...))`):
  - `nodeRuntimeExecutable`: `runtimeExecutable "npm"`, `runtimeArgs ["run","dev"]` → `["npm","run","dev"]`, ecosystems `[.node]`.
  - `nodeProgram`: `program "${workspaceFolder}/server.js"`, args `["--port","4000"]` → `["node","/w/x/server.js","--port","4000"]`, portHint 4000.
  - `nodeTypeScriptWithoutRuntimeSkipped`.
  - `rustCargoBlock`: `cargo.args ["build","--bin=srv","--package=api"]`, args `["-v"]` → `["cargo","run","--bin=srv","--package=api","--","-v"]`; no args → no `--`.
  - `rustWithoutCargoSkipped`, `rustCargoTestSkipped`.
  - `javaAndCoreclrSkipped`: both skipped with the exact reason, `ecosystems.isEmpty`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** `nodeCandidate`, `rustCandidate` (cargo args minus `build`/`run`), java/coreclr skip.
- [ ] **Step 4: Run** `make test` — PASS.
- [ ] **Step 5: Commit** `feat: translate node and CodeLLDB cargo launch configs`

### Task 5: Manifest detector infrastructure and Go detector

**Files:**
- Create: `Sources/SalterCore/Discovery/ManifestDetector.swift` (protocol + `ProjectFiles` helper), `Sources/SalterCore/Discovery/GoDetector.swift`
- Test: `Tests/SalterCoreTests/GoDetectorTests.swift` (temp-dir repos, like `RepoScannerTests.write`)

**Interfaces:**
- Produces:
  ```swift
  public protocol ManifestDetector {
      static var ecosystem: Ecosystem { get }
      static func detect(repo: URL) -> TranslationResult
  }
  enum ProjectFiles {
      static let excludedDirectories: Set<String>   // Global Constraints list
      /// Files under `repo` (depth ≤ maxDepth, excluded/hidden dirs skipped), sorted by relative path.
      static func files(in repo: URL, maxDepth: Int = 4, matching: (URL) -> Bool) -> [URL]
      static func relativePath(_ url: URL, to repo: URL) -> String
      static func service(repo: URL, name: String, target: String, command: [String], portHint: Int?) -> DiscoveredService
      // id "<repo>/<Slug.make(name)>", source .manifest(target), cwd repo, envFile <repo>/.env
  }
  enum GoDetector: ManifestDetector { static func packageClause(_ source: String) -> String? }
  ```
- Go rules per spec: requires root `go.mod`; each `cmd/<name>/` with a non-`_test.go` file declaring `package main` → `go run ./cmd/<name>`, name `<name>`, target `go:cmd/<name>`; root `package main` → `go run .`, name = repo folder, target `go:.`. `packageClause` skips blank lines, `//` comments (incl. `//go:build`) and `/* */` blocks.

- [ ] **Step 1: Failing tests:** `detectsCmdBinaries` (cmd/api + cmd/worker → two services, sorted, commands/targets exact), `detectsRootMain`, `ignoresNonMainAndTestOnlyDirs` (cmd/lib with `package lib`, cmd/x with only `x_test.go` → none), `requiresGoMod`, `detectionIsDeterministic` (two calls equal), `packageClauseSkipsBuildTagsAndComments`.
- [ ] **Step 2: Run** `make test FILTER=GoDetectorTests` — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat: Go manifest detection`

### Task 6: RepoScanner orchestration

**Files:**
- Modify: `Sources/SalterCore/Discovery/RepoScanner.swift`
- Test: `Tests/SalterCoreTests/RepoScannerTests.swift`

**Interfaces:**
- `RepoScanner.detectors: [any ManifestDetector.Type]` — `[GoDetector.self]` now; Tasks 7–9 append.
- Order: launch.json → package.json → each detector whose `ecosystem` ∉ launch `ecosystems`. Launch `warnings` appended to `RepoDiscovery.warnings`.
- Node dedup: a launch.json service whose `command` and `cwd` equal the package.json service's is dropped and recorded as skipped `SkippedConfig(name: <launch config name>, reason: "package.json '<script>' ile aynı")`.

- [ ] **Step 1: Failing tests:** `goLaunchJsonSuppressesGoMod` (launch go service + go.mod/cmd/api → only the launch service), `goModUsedWhenLaunchJsonHasOnlyGoTests` (only a `mode: test` config → manifest service `go run ./cmd/api` present, skip recorded), `nodeLaunchDuplicateOfPackageJsonDropped` (wiki-web shape: `runtimeExecutable npm`, `runtimeArgs ["run","dev"]`, env `NODE_ENV` + package.json `dev` → one service, kind `.packageJson`, skipped reason exact), `preLaunchTaskWarningSurfaces`.
- [ ] **Step 2: Run** `make test FILTER=RepoScannerTests` — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `make test` — PASS.
- [ ] **Step 5: Commit** `feat: combine launch.json, package.json and manifest discovery`

### Task 7: Minimal TOML reader and Rust detector

**Files:**
- Create: `Sources/SalterCore/Discovery/MiniTOML.swift`, `Sources/SalterCore/Discovery/RustDetector.swift`
- Modify: `RepoScanner.detectors`
- Test: `Tests/SalterCoreTests/MiniTOMLTests.swift`, `Tests/SalterCoreTests/RustDetectorTests.swift`

**Interfaces:**
- `struct MiniTOML { var tables: [String: [String: TOMLValue]]; var arrayTables: [String: [[String: TOMLValue]]]; static func parse(_ text: String) -> MiniTOML }`; `enum TOMLValue: Equatable { case string(String), strings([String]), bool(Bool), other }`. Supports `[t]`, `[[t]]`, `key = "v"` / `'v'`, booleans, string arrays (single- or multi-line, trailing commas), `#` comments outside strings; anything else → `.other`. Never throws.
- Rust rules per spec. Source target `rust:<package>/<bin>`, name = bin.

- [ ] **Step 1: Failing tests:**
  - MiniTOML: `parsesTablesAndArrayTables`, `parsesCommentsAndMultilineArrays` (`members = [\n "a", # c\n "crates/*",\n]`).
  - Rust: `singleBinaryUsesPlainCargoRun` (package `api`, src/main.rs → `["cargo","run"]`), `multipleBinsInOnePackage` (src/main.rs + src/bin/tool.rs + `[[bin]] name="srv" path="src/srv.rs"` → three services, `["cargo","run","--bin",<bin>]`), `workspaceWithGlobMembers` (`members=["crates/*"]`, crates/a bin + crates/b lib → one service `["cargo","run","-p","a"]`), `autobinsFalseIgnoresSrcBin`, `libOnlyYieldsNothing`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**, register `RustDetector.self`.
- [ ] **Step 4: Run** `make test` — PASS.
- [ ] **Step 5: Commit** `feat: Rust (Cargo) manifest detection`

### Task 8: Java detector (Maven / Gradle)

**Files:**
- Create: `Sources/SalterCore/Discovery/JavaDetector.swift`; modify `RepoScanner.detectors`
- Test: `Tests/SalterCoreTests/JavaDetectorTests.swift`

**Interfaces:** Rules per spec. Runner = absolute `<repo>/mvnw` / `<repo>/gradlew` if present, else `mvn` / `gradle`. Names: `spring-boot`, `exec`, `bootRun`, `run`. Targets `java:pom.xml`, `java:build.gradle` (or `build.gradle.kts`). No plugin → skipped `SkippedConfig(name: "pom.xml"|"build.gradle…", reason: "çalıştırma eklentisi bulunamadı (spring-boot / exec)")` (Gradle: `"(spring-boot / application)"`). Gradle `application` detection: `id 'application'`, `id("application")`, `apply plugin: 'application'`, or a bare `application` line inside `plugins {}`.

- [ ] **Step 1: Failing tests:** `mavenSpringBootWithWrapper` (command `["<repo>/mvnw","spring-boot:run"]`, portHint from `server.port=8085`), `mavenExecWithoutWrapper` (`["mvn","exec:java"]`), `mavenWithoutPluginSkipped`, `gradleKtsApplication` (`["gradle","run"]`), `gradleSpringBootYamlPort` (`server:\n  port: 9090` → 9090), `springBootDefaultsTo8080`.
- [ ] **Step 2: Run** — FAIL. **Step 3:** implement + register. **Step 4:** `make test` — PASS.
- [ ] **Step 5: Commit** `feat: Java (Maven/Gradle) manifest detection`

### Task 9: .NET detector

**Files:**
- Create: `Sources/SalterCore/Discovery/DotnetDetector.swift`; modify `RepoScanner.detectors`
- Test: `Tests/SalterCoreTests/DotnetDetectorTests.swift`

**Interfaces:** `*.csproj` via `ProjectFiles.files`. Runnable: `Sdk="Microsoft.NET.Sdk.Web"`/`.Worker` or `<OutputType>Exe</OutputType>`; excluded when `<IsTestProject>true`, file name ends `Tests`/`.Test`/`Test`, or references `Microsoft.NET.Test.Sdk`. Command `["dotnet","run","--project",<relative csproj>]`, name = file name sans extension, target `dotnet:<relative csproj>`. Port: `<csproj dir>/Properties/launchSettings.json` (JSONCReader) — profiles sorted by key, first with `commandName == "Project"`, `applicationUrl` split on `;`, first URL's port.

- [ ] **Step 1: Failing tests:** `webProjectWithLaunchSettingsPort` (`src/Api/Api.csproj`, `"applicationUrl": "https://localhost:7001;http://localhost:5001"` → 7001), `consoleExe`, `testProjectsExcluded`, `classLibraryIgnored`.
- [ ] **Step 2: Run** — FAIL. **Step 3:** implement + register. **Step 4:** `make test` — PASS.
- [ ] **Step 5: Commit** `feat: .NET manifest detection`

### Task 10: Real-repo check and README

**Files:** Modify `README.md` (supported sources section).

- [ ] **Step 1:** Temporary, uncommitted test calling `RepoScanner.discover(repo:)` on `/Users/dev/Projects/acme/classifier-go` (and the other acme repos, printing results). Expected: one service "Run", command `go run ./cmd/classifier`; no other repo's existing services changed. Delete the test afterwards.
- [ ] **Step 2:** README: list launch.json types and manifest files Şalter understands, and that hot reload exists only for uvicorn.
- [ ] **Step 3:** `make test` — PASS. Commit `docs: document supported languages`.
