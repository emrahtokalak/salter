# DevLauncher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `~/Projects/acme` altındaki geliştirme servislerini keşfedip tek tıkla başlatan/durduran native macOS (SwiftUI) masaüstü + menu bar uygulaması.

**Architecture:** SPM paketi: UI'dan bağımsız `DevLauncherCore` kütüphanesi (keşif, env, süreç yönetimi, port tespiti, kalıcılık, loglar) + ince `DevLauncher` SwiftUI uygulaması (`Window` + `MenuBarExtra` + `Settings`). Servisler `posix_spawn` ile kendi process group'larında çalışır; durdurma tüm gruba SIGTERM → SIGKILL gönderir.

**Tech Stack:** Swift 6.3 toolchain (Swift 5 dil modu), SwiftUI + Observation (macOS 14+), Foundation/Darwin (`posix_spawn`, `libproc`), `/usr/sbin/lsof`, Swift Testing (Command Line Tools içindeki framework, `make test` ile).

**Spec:** `docs/superpowers/specs/2026-10-09-devlauncher-design.md`

## Global Constraints

- Minimum macOS 14; `swift-tools-version:6.0`; `swiftLanguageModes: [.v5]`; üçüncü parti bağımlılık yok.
- Testler yalnızca `make test` ile çalışır (CLT Swift Testing bayrakları Makefile'da). Tek suite: `make test FILTER=<SuiteName>`.
- Ayar dosyası: `~/Library/Application Support/DevLauncher/config.json`; runtime durumu: aynı klasörde `state.json`; yazımlar atomik.
- Dosya logları: `~/Library/Logs/DevLauncher/<slug(servis-id)>.log`, 10 MB'ta `.1`'e döner (en fazla 2 dosya). Bellekte servis başına 5.000 satır.
- Durdurma: `kill(-pgid, SIGTERM)` → 5 sn → `kill(-pgid, SIGKILL)`. **pgid ≤ 1 için asla kill çağrılmaz.**
- Shell ortamı: `/bin/zsh -ilc` ile bir kez yakalanır, 5 sn timeout; başarısızsa PATH = `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
- Env katmanları (düşük → yüksek): shell → envFile (yoksa `<repo>/.env`) → config `env` (+ kullanıcı override) → `PYTHONUNBUFFERED=1`, `FORCE_COLOR=1`.
- Bundle id: `com.etokalak.devlauncher`. UI metinleri Türkçe.

## Spec'ten bilinçli sapmalar

- **Otomatik kaydırma:** "Kullanıcı yukarı kaydırınca durur" davranışı yerine log araç çubuğunda bir "Otomatik kaydır" onay kutusu var. Kaydırma konumunu izlemek için gereken API (`onScrollGeometryChange`) macOS 15 gerektiriyor.
- **`portHint` olan servisler:** Bunlar, process grubunda bir port dinlenmeye başlayana kadar `starting` durumunda kalır. 3 saniye kuralı yalnızca port beklenmeyen servisler (worker'lar) için geçerli. Böylece yavaş açılan bir API, henüz hazır olmadan "çalışıyor" görünmez.
- **Kaynak alan adı:** Servis kaynağı (`ServiceSource`) için alan adı `configName` yerine `name` oldu.
- **Reddedilen kaynaklar:** `RepoConfig.declinedSources` eklendi. Önerilerden seçilmeyen servisler burada tutulur ve yeniden taramada tekrar önerilmez; ama "Keşfedilen servisler…" ekranından her zaman eklenebilir.

## Review Focus

1. **Boşluk ve Türkçe karakter içeren yollar ile argümanlar** (ör. `çalışma klasörü`, `ağ değer`) bozulmadan iletilmeli. Testi Task 7'de: `handlesPathsWithSpacesAndTurkishCharacters`.
2. **Satır sonu içermeyen çok uzun çıktı** (progress bar, tek satırlık JSON) belleği sınırsız büyütmemeli, logda görünmeli. Testi Task 7'de: `flushesVeryLongLinesWithoutNewline`.
3. **Repo klasörü diskten silinip yeniden tarandığında** servisler ve kullanıcı ayarları silinmemeli, "kaynakta yok" diye işaretlenmeli. Testi Task 6'da: `deletedRepoFolderMarksEverythingMissingWithoutDeleting`.
4. **Başlat butonuna hızlıca iki kez basılınca** ikinci bir process açılmamalı. Testi Task 11'de: `secondStartWhileRunningIsIgnored`.
5. **Gerçek hayattan `.env` dosyaları** (`export`, tırnaklı değerler, satır içi yorum, CRLF satır sonu) doğru okunmalı. Testi Task 5'te: `parsesCommonFormats`.

## File Structure

```
devlauncher/
  Package.swift
  Makefile
  README.md
  Resources/Info.plist, Resources/AppIcon.icns
  scripts/make-icon.swift
  Sources/DevLauncherCore/
    Discovery/JSONCReader.swift            JSONC → [String: Any]
    Discovery/LaunchConfig.swift           LaunchConfig + LaunchJsonParser
    Discovery/LaunchConfigTranslator.swift launch config → ServiceDefinition (filtre, birleştirme, reload)
    Discovery/PackageJsonTranslator.swift  package.json → ServiceDefinition
    Discovery/RepoScanner.swift            kök tarama + repo keşfi
    Model/ServiceModels.swift              ServiceDefinition/Overrides/Config/Source, DiscoveredService…
    Model/Slug.swift                       id üretimi
    Model/ShellWords.swift                 komut satırı split/join
    Environment/DotEnvParser.swift
    Environment/EnvResolver.swift
    Environment/ShellEnvironment.swift
    Config/AppConfig.swift                 AppConfig/RepoConfig/AppSettings
    Config/ConfigStore.swift               config.json okuma/yazma
    Config/ConfigMerger.swift              yeniden tarama birleştirme + öneri kabulü
    Process/ProcessTypes.swift             OutputKind, ExitStatus, SpawnRequest, ProcessRunnerError
    Process/LineBuffer.swift
    Process/ProcessInspector.swift         isAlive, startTime (libproc)
    Process/ProcessRunner.swift            posix_spawn, SpawnedProcess, terminateGroup
    Process/PortProbe.swift                lsof tabanlı port tespiti
    Logs/ANSIParser.swift
    Logs/LogBuffer.swift                   @Observable ring buffer
    Logs/LogFileWriter.swift               dosya log + rotasyon
    Runtime/LaunchPlanner.swift            SetupRequirement, LaunchPlan, plan()
    Runtime/RuntimeStateStore.swift        state.json + yetim tespiti
    Runtime/ServiceSupervisor.swift        servis durum makinesi
  Sources/DevLauncher/
    DevLauncherApp.swift                   @main, sahneler, AppDelegate
    AppModel.swift                         UI durumu + Core orkestrasyonu
    Alerts.swift, SystemIntegration.swift
    Views/StatusStyle.swift, ServiceRow.swift, MainWindow.swift, ServiceDetailView.swift,
          LogView.swift, ServiceSettingsForm.swift, RepoSheets.swift, MenuBarView.swift, SettingsView.swift
  Tests/DevLauncherCoreTests/
    Support/TestSupport.swift, Fixtures/<repo>/{launch.json,package.json}, *Tests.swift
```

Kod bloklarının ilk iki satırından birinde `File: <yol>` işareti var. Yürütücü bu işaretli satırı silip bloğu o yola yazar.

---

### Task 1: İskelet + JSONCReader

**Files:**
- Create: `Package.swift`, `Makefile`, `Sources/DevLauncher/main.swift` (geçici, Task 14'te silinir), `Tests/DevLauncherCoreTests/Fixtures/README.md`, `Tests/DevLauncherCoreTests/Support/TestSupport.swift`
- Create: `Sources/DevLauncherCore/Discovery/JSONCReader.swift`
- Modify: `.gitignore` (`build/` ekle)
- Test: `Tests/DevLauncherCoreTests/JSONCReaderTests.swift`

**Interfaces:**
- Produces: `JSONCReader.sanitize(_ data: Data) -> Data`, `JSONCReader.object(from: Data) throws -> [String: Any]`, `JSONCReader.Error { notAnObject, invalidJSON(String) }`; test yardımcıları `Fixtures.data(_:)`, `waitUntil(timeout:_:)` (`@MainActor`), `makeTempDirectory()`, `makeFakeExecutable(_:)`.

- [ ] **Step 1: Paket iskeletini yaz**

```swift
// swift-tools-version:6.0
// File: Package.swift
import PackageDescription

let package = Package(
    name: "DevLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DevLauncherCore"),
        .executableTarget(name: "DevLauncher", dependencies: ["DevLauncherCore"]),
        .testTarget(
            name: "DevLauncherCoreTests",
            dependencies: ["DevLauncherCore"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
```

```make
# File: Makefile
CLT := /Library/Developer/CommandLineTools
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
APP := build/DevLauncher.app

.PHONY: build test app install icon clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)',)

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/DevLauncher $(APP)/Contents/MacOS/DevLauncher
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign -s - --force --deep $(APP)

install: app
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/DevLauncher.app
	cp -R $(APP) $(HOME)/Applications/DevLauncher.app

icon:
	rm -rf build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build build
```

```swift
// File: Sources/DevLauncher/main.swift
// Placeholder until the SwiftUI app entry point lands (Task 14).
print("DevLauncher")
```

```markdown
<!-- File: Tests/DevLauncherCoreTests/Fixtures/README.md -->
Bu klasördeki dosyalar `~/Projects/acme` altındaki gerçek repolardan kopyalanmıştır
(`.vscode/launch.json` → `<repo>/launch.json`, `package.json` → `<repo>/package.json`).
Keşif/çeviri testleri bu dosyalara karşı çalışır.
```

```swift
// File: Tests/DevLauncherCoreTests/Support/TestSupport.swift
import Foundation
@testable import DevLauncherCore

/// Swift Testing also declares `ExitStatus`; prefer ours inside the test module.
typealias ExitStatus = DevLauncherCore.ExitStatus

enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` elapses.
@MainActor
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

/// A fresh, empty temporary directory.
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("devlauncher-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Creates an executable shell script named `name` in a new temp directory and returns the directory.
func makeFakeExecutable(_ name: String) throws -> URL {
    let dir = try makeTempDirectory()
    let file = dir.appendingPathComponent(name)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    return dir
}
```

`.gitignore` dosyasına `build/` satırını ekle.

- [ ] **Step 2: Failing test yaz**

```swift
// File: Tests/DevLauncherCoreTests/JSONCReaderTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct JSONCReaderTests {
    private func parse(_ text: String) throws -> [String: Any] {
        try JSONCReader.object(from: Data(text.utf8))
    }

    @Test func stripsLineAndBlockComments() throws {
        let obj = try parse("""
        {
          // line comment
          "a": 1, /* block
          comment */ "b": 2
        }
        """)
        #expect(obj["a"] as? Int == 1)
        #expect(obj["b"] as? Int == 2)
    }

    @Test func keepsCommentLikeTextInsideStrings() throws {
        let obj = try parse(#"{ "url": "http://x//y", "glob": "a/*b*/c", "q": "say \"//hi\"" }"#)
        #expect(obj["url"] as? String == "http://x//y")
        #expect(obj["glob"] as? String == "a/*b*/c")
        #expect(obj["q"] as? String == #"say "//hi""#)
    }

    @Test func removesTrailingCommasEvenAfterComments() throws {
        let obj = try parse("""
        { "list": [1, 2, // two
        ], "o": { "k": "v", }, }
        """)
        #expect(obj["list"] as? [Int] == [1, 2])
        #expect((obj["o"] as? [String: Any])?["k"] as? String == "v")
    }

    @Test func keepsCommasInsideStrings() throws {
        let obj = try parse(#"{ "s": "a, ]" }"#)
        #expect(obj["s"] as? String == "a, ]")
    }

    @Test func rejectsInvalidJSON() {
        #expect(throws: JSONCReader.Error.self) { try parse(#"{ "a": }"#) }
        #expect(throws: JSONCReader.Error.notAnObject) { try parse("[1]") }
    }
}
```

- [ ] **Step 3: Testin fail ettiğini doğrula**

Run: `make test FILTER=JSONCReaderTests`
Expected: Derleme hatası, `cannot find 'JSONCReader' in scope` (veya Core target'ında kaynak dosya olmadığı için hata).

- [ ] **Step 4: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Discovery/JSONCReader.swift
import Foundation

/// Reads JSON with comments (JSONC), the format VS Code uses for launch.json.
public enum JSONCReader {
    public enum Error: Swift.Error, Equatable {
        case notAnObject
        case invalidJSON(String)
    }

    /// Removes `//` and `/* */` comments and trailing commas; string literals are left untouched.
    public static func sanitize(_ data: Data) -> Data {
        Data(removeTrailingCommas(removeComments([UInt8](data))))
    }

    public static func object(from data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: sanitize(data))
        } catch {
            throw Error.invalidJSON(error.localizedDescription)
        }
        guard let object = value as? [String: Any] else { throw Error.notAnObject }
        return object
    }

    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let slash = UInt8(ascii: "/")
    private static let star = UInt8(ascii: "*")
    private static let newline = UInt8(ascii: "\n")
    private static let comma = UInt8(ascii: ",")
    private static let closeBrace = UInt8(ascii: "}")
    private static let closeBracket = UInt8(ascii: "]")

    private static func removeComments(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(input.count)
        var i = 0
        var inString = false
        while i < input.count {
            let c = input[i]
            if inString {
                out.append(c)
                if c == backslash, i + 1 < input.count {
                    out.append(input[i + 1])
                    i += 2
                    continue
                }
                if c == quote { inString = false }
                i += 1
                continue
            }
            if c == quote {
                inString = true
                out.append(c)
                i += 1
                continue
            }
            if c == slash, i + 1 < input.count, input[i + 1] == slash {
                i += 2
                while i < input.count, input[i] != newline { i += 1 }
                continue
            }
            if c == slash, i + 1 < input.count, input[i + 1] == star {
                i += 2
                while i < input.count, !(input[i] == star && i + 1 < input.count && input[i + 1] == slash) {
                    i += 1
                }
                i += 2
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func removeTrailingCommas(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(input.count)
        var i = 0
        var inString = false
        while i < input.count {
            let c = input[i]
            if inString {
                out.append(c)
                if c == backslash, i + 1 < input.count {
                    out.append(input[i + 1])
                    i += 2
                    continue
                }
                if c == quote { inString = false }
                i += 1
                continue
            }
            if c == quote {
                inString = true
                out.append(c)
                i += 1
                continue
            }
            if c == comma {
                var j = i + 1
                while j < input.count, isWhitespace(input[j]) { j += 1 }
                if j < input.count, input[j] == closeBrace || input[j] == closeBracket {
                    i += 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func isWhitespace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }
}
```

- [ ] **Step 5: Testlerin geçtiğini doğrula**

Run: `make test FILTER=JSONCReaderTests`
Expected: `5 tests ... passed`. Ayrıca `make build` başarılı olmalı.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: SPM skeleton, Makefile and JSONC reader"
```

---

### Task 2: Servis modelleri, Slug, ShellWords

**Files:**
- Create: `Sources/DevLauncherCore/Model/ServiceModels.swift`, `Sources/DevLauncherCore/Model/Slug.swift`, `Sources/DevLauncherCore/Model/ShellWords.swift`
- Test: `Tests/DevLauncherCoreTests/ModelTests.swift`

**Interfaces:**
- Produces:
  - `PackageManager { npm, yarn, pnpm }`
  - `ServiceSource(kind: .launchJson|.packageJson|.manual, name: String?)` + `.launchJson(_:)`, `.packageJson(_:)`, `.manual`
  - `ServiceDefinition(name:command:cwd:envFile:env:supportsReload:reloadEnabled:reloadArgs:portHint:)` + `launchCommand: [String]`
  - `ServiceOverrides` (tüm alanlar opsiyonel, `isEmpty`)
  - `ServiceConfig(id:source:discovered:overrides:sourceMissing:)` + `effective`
  - `DiscoveredService(id:source:definition:)`, `SkippedConfig(name:reason:)`, `TranslationResult(services:skipped:)`
  - `Slug.make(_:) -> String`, `Slug.unique(_:taken:) -> String`
  - `ShellWords.split(_:) -> [String]`, `ShellWords.join(_:) -> String`

- [ ] **Step 1: Failing test yaz**

```swift
// File: Tests/DevLauncherCoreTests/ModelTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct ModelTests {
    func definition() -> ServiceDefinition {
        ServiceDefinition(
            name: "API",
            command: ["/r/.venv/bin/python", "-m", "uvicorn", "app:app"],
            cwd: "/r",
            envFile: "/r/.env",
            env: ["A": "1"],
            supportsReload: true,
            reloadEnabled: false,
            reloadArgs: ["--reload", "--reload-dir", "src"],
            portHint: 8010
        )
    }

    @Test func launchCommandAppendsReloadArgsOnlyWhenEnabled() {
        var d = definition()
        #expect(d.launchCommand == d.command)
        d.reloadEnabled = true
        #expect(d.launchCommand == d.command + ["--reload", "--reload-dir", "src"])
        d.supportsReload = false
        #expect(d.launchCommand == d.command)
    }

    @Test func effectiveAppliesOverrides() {
        var cfg = ServiceConfig(id: "r/api", source: .launchJson("API"), discovered: definition())
        #expect(cfg.effective == definition())
        #expect(cfg.overrides.isEmpty)
        cfg.overrides.name = "My API"
        cfg.overrides.env = ["A": "2", "B": "3"]
        cfg.overrides.envFile = ""
        cfg.overrides.reloadEnabled = true
        cfg.overrides.portHint = 9000
        let e = cfg.effective
        #expect(e.name == "My API")
        #expect(e.env == ["A": "2", "B": "3"])
        #expect(e.envFile == nil)
        #expect(e.reloadEnabled)
        #expect(e.portHint == 9000)
        #expect(e.command == definition().command)
        #expect(!cfg.overrides.isEmpty)
    }

    @Test func overridesRoundTripThroughJSON() throws {
        var cfg = ServiceConfig(id: "r/api", source: .launchJson("API"), discovered: definition())
        cfg.overrides.command = ["x"]
        let decoded = try JSONDecoder().decode(ServiceConfig.self, from: JSONEncoder().encode(cfg))
        #expect(decoded == cfg)
    }

    @Test func slugs() {
        #expect(Slug.make("🚀 Debug FastAPI") == "debug-fastapi")
        #expect(Slug.make("API: uvicorn (debug)") == "api-uvicorn-debug")
        #expect(Slug.make("***") == "service")
        #expect(Slug.unique("dev", taken: ["dev", "dev-2"]) == "dev-3")
        #expect(Slug.unique("x", taken: []) == "x")
    }

    @Test func shellWordsRoundTrip() {
        let words = ["python", "-m", "app", "--name", "hello world", "it's", ""]
        #expect(ShellWords.split(ShellWords.join(words)) == words)
        #expect(ShellWords.split(#"a "b c" 'd e' f\ g"#) == ["a", "b c", "d e", "f g"])
        #expect(ShellWords.join(["--port", "8010", "/a/b.py"]) == "--port 8010 /a/b.py")
        #expect(ShellWords.split("   ").isEmpty)
    }
}
```

- [ ] **Step 2: Testin fail ettiğini doğrula**

Run: `make test FILTER=ModelTests`
Expected: Derleme hatası, `cannot find 'ServiceDefinition' in scope`.

- [ ] **Step 3: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Model/ServiceModels.swift
import Foundation

public enum PackageManager: String, Codable, CaseIterable, Sendable {
    case npm, yarn, pnpm
}

/// Where a service definition came from; used to match services across rescans.
public struct ServiceSource: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case launchJson, packageJson, manual
    }

    public var kind: Kind
    /// launch.json configuration name or package.json script name.
    public var name: String?

    public init(kind: Kind, name: String? = nil) {
        self.kind = kind
        self.name = name
    }

    public static func launchJson(_ configName: String) -> ServiceSource {
        ServiceSource(kind: .launchJson, name: configName)
    }

    public static func packageJson(_ script: String) -> ServiceSource {
        ServiceSource(kind: .packageJson, name: script)
    }

    public static let manual = ServiceSource(kind: .manual)
}

/// Everything needed to run a service.
public struct ServiceDefinition: Codable, Equatable, Sendable {
    public var name: String
    /// Executable and arguments, without reload arguments.
    public var command: [String]
    public var cwd: String
    /// Absolute path of the env file to load; nil when the service has none.
    public var envFile: String?
    public var env: [String: String]
    public var supportsReload: Bool
    public var reloadEnabled: Bool
    /// Appended to `command` when reload is enabled, e.g. ["--reload", "--reload-dir", "src"].
    public var reloadArgs: [String]
    public var portHint: Int?

    public init(
        name: String,
        command: [String],
        cwd: String,
        envFile: String? = nil,
        env: [String: String] = [:],
        supportsReload: Bool = false,
        reloadEnabled: Bool = false,
        reloadArgs: [String] = [],
        portHint: Int? = nil
    ) {
        self.name = name
        self.command = command
        self.cwd = cwd
        self.envFile = envFile
        self.env = env
        self.supportsReload = supportsReload
        self.reloadEnabled = reloadEnabled
        self.reloadArgs = reloadArgs
        self.portHint = portHint
    }

    public var launchCommand: [String] {
        supportsReload && reloadEnabled ? command + reloadArgs : command
    }
}

/// User edits layered over a discovered definition; nil means "use discovered".
public struct ServiceOverrides: Codable, Equatable, Sendable {
    public var name: String?
    public var command: [String]?
    public var cwd: String?
    /// Empty string disables the env file.
    public var envFile: String?
    /// Merged over the discovered env.
    public var env: [String: String]?
    public var reloadEnabled: Bool?
    public var portHint: Int?

    public init() {}

    public var isEmpty: Bool { self == ServiceOverrides() }
}

public struct ServiceConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var source: ServiceSource
    public var discovered: ServiceDefinition
    public var overrides: ServiceOverrides
    public var sourceMissing: Bool

    public init(
        id: String,
        source: ServiceSource,
        discovered: ServiceDefinition,
        overrides: ServiceOverrides = ServiceOverrides(),
        sourceMissing: Bool = false
    ) {
        self.id = id
        self.source = source
        self.discovered = discovered
        self.overrides = overrides
        self.sourceMissing = sourceMissing
    }

    public var effective: ServiceDefinition {
        var d = discovered
        if let v = overrides.name { d.name = v }
        if let v = overrides.command { d.command = v }
        if let v = overrides.cwd { d.cwd = v }
        if let v = overrides.envFile { d.envFile = v.isEmpty ? nil : v }
        if let v = overrides.env { d.env.merge(v) { _, new in new } }
        if let v = overrides.reloadEnabled { d.reloadEnabled = v }
        if let v = overrides.portHint { d.portHint = v }
        return d
    }
}

public struct DiscoveredService: Equatable, Sendable {
    public var id: String
    public var source: ServiceSource
    public var definition: ServiceDefinition

    public init(id: String, source: ServiceSource, definition: ServiceDefinition) {
        self.id = id
        self.source = source
        self.definition = definition
    }
}

public struct SkippedConfig: Equatable, Sendable {
    public var name: String
    public var reason: String

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

public struct TranslationResult: Equatable, Sendable {
    public var services: [DiscoveredService]
    public var skipped: [SkippedConfig]

    public init(services: [DiscoveredService], skipped: [SkippedConfig]) {
        self.services = services
        self.skipped = skipped
    }
}
```

```swift
// File: Sources/DevLauncherCore/Model/Slug.swift
import Foundation

public enum Slug {
    /// Lowercase ASCII letters and digits joined by single dashes.
    public static func make(_ text: String) -> String {
        var out = ""
        var lastWasDash = true
        for scalar in text.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "service" : out
    }

    /// Returns `base`, or `base-2`, `base-3`… so that the result is not in `taken`.
    public static func unique(_ base: String, taken: Set<String>) -> String {
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}
```

```swift
// File: Sources/DevLauncherCore/Model/ShellWords.swift
import Foundation

/// POSIX-shell-like word splitting and quoting, used for editing commands as one line.
public enum ShellWords {
    public static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var hasWord = false
        var quote: Character?
        var escaping = false
        for ch in line {
            if escaping {
                current.append(ch)
                escaping = false
                hasWord = true
                continue
            }
            if let q = quote {
                if ch == q {
                    quote = nil
                } else if ch == "\\" && q == "\"" {
                    escaping = true
                } else {
                    current.append(ch)
                }
                continue
            }
            switch ch {
            case "\\":
                escaping = true
                hasWord = true
            case "\"", "'":
                quote = ch
                hasWord = true
            case " ", "\t", "\n":
                if hasWord {
                    words.append(current)
                    current = ""
                    hasWord = false
                }
            default:
                current.append(ch)
                hasWord = true
            }
        }
        if hasWord { words.append(current) }
        return words
    }

    public static func join(_ words: [String]) -> String {
        words.map(quote).joined(separator: " ")
    }

    private static let safe = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=@%+,"
    )

    static func quote(_ word: String) -> String {
        if word.isEmpty { return "''" }
        if word.unicodeScalars.allSatisfy({ safe.contains($0) }) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `make test FILTER=ModelTests`
Expected: `5 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: service models, slug and shell-word helpers"
```

---
### Task 3: launch.json parser + translator (fixture'larla)

**Files:**
- Create: `Sources/DevLauncherCore/Discovery/LaunchConfig.swift`, `Sources/DevLauncherCore/Discovery/LaunchConfigTranslator.swift`
- Create: `Tests/DevLauncherCoreTests/Fixtures/<repo>/launch.json` (6 repo, gerçek dosyalardan kopya)
- Test: `Tests/DevLauncherCoreTests/LaunchJsonParserTests.swift`, `Tests/DevLauncherCoreTests/LaunchConfigTranslatorTests.swift`

**Interfaces:**
- Consumes: `JSONCReader.object(from:)`, `ShellWords.split`, `Slug`, `ServiceDefinition`, `DiscoveredService`, `TranslationResult`, `SkippedConfig`, `ServiceSource.launchJson`.
- Produces:
  - `LaunchConfig` (name, type, request, module, program, python, args, cwd, env, envFile, purpose, variables)
  - `LaunchJsonParser.parse(_ data: Data) throws -> [LaunchConfig]`
  - `LaunchConfigTranslator.translate(_ configs: [LaunchConfig], repo: URL) -> TranslationResult`
  - `LaunchConfigTranslator.splitReloadArgs(_:) -> (args: [String], extras: [String], hadReload: Bool)` (internal)
  - Servis id formatı: `"<repo klasör adı>/<slug(config adı)>"`

- [ ] **Step 1: Fixture'ları kopyala**

```bash
cd ~/Projects/devlauncher
F=Tests/DevLauncherCoreTests/Fixtures
T=~/Projects/acme
for r in gateway-api docs-api flow-api media-pipeline analytics-worker storefront; do
  mkdir -p "$F/$r" && cp "$T/$r/.vscode/launch.json" "$F/$r/launch.json"
done
ls $F/*/launch.json | wc -l   # 6
```

- [ ] **Step 2: Failing testleri yaz**

```swift
// File: Tests/DevLauncherCoreTests/LaunchJsonParserTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct LaunchJsonParserTests {
    @Test func parsesJsoncWithTrailingCommas() throws {
        let configs = try LaunchJsonParser.parse(Fixtures.data("flow-api/launch.json"))
        #expect(configs.map(\.name) == ["🚀 Debug FastAPI", "🔧 Debug Main (CLI)"])
        #expect(configs[0].python == "${workspaceFolder}/.venv/bin/python")
        #expect(configs[0].program == "${workspaceFolder}/src/app/main.py")
        #expect(configs[0].type == "debugpy")
        #expect(configs[0].request == "launch")
    }

    @Test func collectsVariablesAndPurpose() throws {
        let configs = try LaunchJsonParser.parse(Fixtures.data("docs-api/launch.json"))
        let current = try #require(configs.first { $0.name == "Tests: current file" })
        #expect(current.variables == ["workspaceFolder", "file"])
        let debugTest = try #require(configs.first { $0.name == "Tests: debug-test (Testing panel)" })
        #expect(debugTest.purpose == ["debug-test"])
    }

    @Test func acceptsStringArgsAndNumericEnv() throws {
        let json = #"{ "configurations": [ { "name": "A", "args": "--port 8000 --name 'x y'", "env": { "N": 3 } }, { "noName": true } ] }"#
        let configs = try LaunchJsonParser.parse(Data(json.utf8))
        #expect(configs.count == 1)
        #expect(configs[0].args == ["--port", "8000", "--name", "x y"])
        #expect(configs[0].env == ["N": "3"])
    }

    @Test func missingConfigurationsYieldsEmptyList() throws {
        #expect(try LaunchJsonParser.parse(Data("{}".utf8)).isEmpty)
    }
}
```

```swift
// File: Tests/DevLauncherCoreTests/LaunchConfigTranslatorTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct LaunchConfigTranslatorTests {
    func translate(_ repo: String) throws -> TranslationResult {
        let configs = try LaunchJsonParser.parse(Fixtures.data("\(repo)/launch.json"))
        return LaunchConfigTranslator.translate(configs, repo: URL(fileURLWithPath: "/w/\(repo)"))
    }

    @Test func aihubBffUvicornWithReload() throws {
        let r = try translate("gateway-api")
        #expect(r.skipped.isEmpty)
        #expect(r.services.count == 1)
        let s = try #require(r.services.first)
        #expect(s.id == "gateway-api/python-debugger-fastapi")
        #expect(s.source == .launchJson("Python Debugger: FastAPI"))
        let d = s.definition
        #expect(d.command == ["/w/gateway-api/.venv/bin/python", "-m", "uvicorn", "app.app:app", "--host", "0.0.0.0", "--port", "8002"])
        #expect(d.cwd == "/w/gateway-api")
        #expect(d.envFile == "/w/gateway-api/.env")
        #expect(d.env == ["PYTHONPATH": "/w/gateway-api/src/python"])
        #expect(d.supportsReload)
        #expect(d.reloadEnabled)
        #expect(d.reloadArgs == ["--reload"])
        #expect(d.portHint == 8002)
    }

    @Test func docsApiMergesReloadVariantAndSkipsTests() throws {
        let r = try translate("docs-api")
        #expect(r.services.count == 1)
        let d = try #require(r.services.first).definition
        #expect(d.name == "API: uvicorn (debug)")
        #expect(d.command == ["/w/docs-api/.venv/bin/python", "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8010"])
        #expect(d.reloadEnabled)
        #expect(d.reloadArgs == ["--reload", "--reload-dir", "src"])
        #expect(d.env == ["PYTHONPATH": "/w/docs-api/src"])
        #expect(Set(r.skipped.map(\.name)) == ["Tests: all", "Tests: current file", "Tests: debug-test (Testing panel)"])
    }

    @Test func flowApiIdenticalProgramConfigsMergeIntoOne() throws {
        let r = try translate("flow-api")
        #expect(r.services.count == 1)
        let s = try #require(r.services.first)
        #expect(s.id == "flow-api/debug-fastapi")
        #expect(s.definition.name == "🚀 Debug FastAPI")
        #expect(s.definition.command == ["/w/flow-api/.venv/bin/python", "/w/flow-api/src/app/main.py"])
        #expect(!s.definition.supportsReload)
        #expect(s.definition.portHint == nil)
    }

    @Test func mediaPipelineKeepsAllWorkers() throws {
        let r = try translate("media-pipeline")
        #expect(r.services.count == 11)
        #expect(r.skipped.isEmpty)
        #expect(Set(r.services.map(\.id)).count == 11)
        let transcode = try #require(r.services.first { $0.definition.name == "Temporal: Process Transcode Worker" })
        #expect(transcode.definition.command == ["/w/media-pipeline/.venv/bin/python", "-m", "workflows.process_transcode.launcher"])
        #expect(transcode.definition.env["TEMPORAL_TASK_QUEUE"] == "process-transcode-task-queue")
        let post = try #require(r.services.first { $0.definition.name == "Temporal: Post-Transcode Orchestrator Worker" })
        #expect(Array(post.definition.command.suffix(3)) == ["main_standard", "--worker", "post-transcode-orchestrator"])
    }

    @Test func analyticsFlowUsesExplicitEnvFileAndPython() throws {
        let r = try translate("analytics-worker")
        #expect(r.services.count == 1)
        #expect(r.skipped.map(\.name) == ["Pytest: All Tests"])
        let d = try #require(r.services.first).definition
        #expect(d.envFile == "/w/analytics-worker/.env")
        #expect(d.command == ["/w/analytics-worker/.venv/bin/python", "-m", "main"])
    }

    @Test func storefrontPreservesReloadDirAndCwd() throws {
        let r = try translate("storefront")
        #expect(r.services.map(\.definition.name) == ["Debug BFF", "Debug Order Worker"])
        let bff = r.services[0].definition
        #expect(bff.cwd == "/w/storefront/src")
        #expect(bff.command == ["/w/storefront/.venv/bin/python", "-m", "uvicorn", "adapters.incoming.bff.app:app", "--host", "0.0.0.0", "--port", "8080"])
        #expect(bff.reloadEnabled)
        #expect(bff.reloadArgs == ["--reload", "--reload-dir", "/w/storefront/src"])
        #expect(bff.portHint == 8080)
        let worker = r.services[1].definition
        #expect(worker.command == ["/w/storefront/.venv/bin/python", "/w/storefront/src/main.py", "--adapter", "order-worker"])
        #expect(worker.env["TEMPORAL_DEBUG"] == "true")
        #expect(worker.env["CONFIGURATION_FILE_PATH"] == "/w/storefront/configuration/app-config.yaml")
    }

    @Test func unsupportedVariablesAndTypesAreSkipped() throws {
        let json = """
        { "configurations": [
          { "name": "Input", "type": "debugpy", "request": "launch", "module": "x", "args": ["${input:port}"] },
          { "name": "Attach", "type": "debugpy", "request": "attach" },
          { "name": "Node", "type": "node", "request": "launch", "program": "a.js" },
          { "name": "Nothing", "type": "debugpy", "request": "launch" },
          { "name": "PortEnv", "type": "python", "request": "launch", "module": "worker", "env": { "PORT": "9001" } }
        ] }
        """
        let configs = try LaunchJsonParser.parse(Data(json.utf8))
        let r = LaunchConfigTranslator.translate(configs, repo: URL(fileURLWithPath: "/w/x"))
        #expect(r.services.map(\.definition.name) == ["PortEnv"])
        #expect(r.services.first?.definition.portHint == 9001)
        #expect(r.skipped.map(\.name) == ["Input", "Attach", "Node", "Nothing"])
        #expect(r.skipped.first?.reason.contains("${input:port}") == true)
    }

    @Test func reloadFlagVariantsAreSeparated() {
        let split = LaunchConfigTranslator.splitReloadArgs(
            ["app:app", "--reload", "--reload-dir", "src", "--reload-include=*.yaml", "--port", "1"]
        )
        #expect(split.args == ["app:app", "--port", "1"])
        #expect(split.extras == ["--reload-dir", "src", "--reload-include=*.yaml"])
        #expect(split.hadReload)
    }
}
```

- [ ] **Step 3: Testin fail ettiğini doğrula**

Run: `make test FILTER=LaunchJsonParserTests`
Expected: Derleme hatası, `cannot find 'LaunchJsonParser' in scope`.

- [ ] **Step 4: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Discovery/LaunchConfig.swift
import Foundation

/// The subset of a VS Code launch configuration that DevLauncher understands.
public struct LaunchConfig: Equatable, Sendable {
    public var name: String
    public var type: String?
    public var request: String?
    public var module: String?
    public var program: String?
    public var python: String?
    public var args: [String]
    public var cwd: String?
    public var env: [String: String]
    public var envFile: String?
    public var purpose: [String]
    /// Names of every `${...}` variable referenced anywhere in the configuration.
    public var variables: Set<String>
}

public enum LaunchJsonParser {
    public static func parse(_ data: Data) throws -> [LaunchConfig] {
        let root = try JSONCReader.object(from: data)
        let configurations = root["configurations"] as? [[String: Any]] ?? []
        return configurations.compactMap(config(from:))
    }

    static func config(from dict: [String: Any]) -> LaunchConfig? {
        guard let name = dict["name"] as? String else { return nil }
        return LaunchConfig(
            name: name,
            type: dict["type"] as? String,
            request: dict["request"] as? String,
            module: dict["module"] as? String,
            program: dict["program"] as? String,
            python: dict["python"] as? String,
            args: stringList(dict["args"]),
            cwd: dict["cwd"] as? String,
            env: stringMap(dict["env"]),
            envFile: dict["envFile"] as? String,
            purpose: stringList(dict["purpose"]),
            variables: variables(in: dict)
        )
    }

    static func stringList(_ value: Any?) -> [String] {
        if let list = value as? [Any] { return list.compactMap { $0 as? String } }
        if let text = value as? String { return ShellWords.split(text) }
        return []
    }

    static func stringMap(_ value: Any?) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (key, raw) in dict {
            if let text = raw as? String {
                out[key] = text
            } else if let number = raw as? NSNumber {
                out[key] = number.stringValue
            }
        }
        return out
    }

    static func variables(in value: Any) -> Set<String> {
        switch value {
        case let text as String:
            return variableNames(in: text)
        case let list as [Any]:
            return list.reduce(into: Set<String>()) { $0.formUnion(variables(in: $1)) }
        case let dict as [String: Any]:
            return dict.values.reduce(into: Set<String>()) { $0.formUnion(variables(in: $1)) }
        default:
            return []
        }
    }

    static func variableNames(in text: String) -> Set<String> {
        var names = Set<String>()
        var rest = Substring(text)
        while let start = rest.range(of: "${") {
            guard let end = rest[start.upperBound...].firstIndex(of: "}") else { break }
            names.insert(String(rest[start.upperBound..<end]))
            rest = rest[rest.index(after: end)...]
        }
        return names
    }
}
```

```swift
// File: Sources/DevLauncherCore/Discovery/LaunchConfigTranslator.swift
import Foundation

/// Turns VS Code debugpy launch configurations into runnable service definitions.
public enum LaunchConfigTranslator {
    static let supportedTypes: Set<String> = ["debugpy", "python"]
    static let reloadValueFlags: Set<String> = ["--reload-dir", "--reload-include", "--reload-exclude", "--reload-delay"]

    struct SkipReason: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    struct Candidate {
        var definition: ServiceDefinition
        var hadReload: Bool
    }

    struct MergeKey: Hashable {
        var command: [String]
        var cwd: String
        var envFile: String?
        var env: [String: String]
    }

    public static func translate(_ configs: [LaunchConfig], repo: URL) -> TranslationResult {
        var candidates: [Candidate] = []
        var skipped: [SkippedConfig] = []
        for config in configs {
            switch candidate(from: config, repo: repo) {
            case .success(let candidate):
                candidates.append(candidate)
            case .failure(let reason):
                skipped.append(SkippedConfig(name: config.name, reason: reason.message))
            }
        }
        var taken = Set<String>()
        let services = merge(candidates).map { candidate -> DiscoveredService in
            let slug = Slug.unique(Slug.make(candidate.definition.name), taken: taken)
            taken.insert(slug)
            return DiscoveredService(
                id: "\(repo.lastPathComponent)/\(slug)",
                source: .launchJson(candidate.definition.name),
                definition: candidate.definition
            )
        }
        return TranslationResult(services: services, skipped: skipped)
    }

    static func candidate(from config: LaunchConfig, repo: URL) -> Result<Candidate, SkipReason> {
        guard config.request == "launch" else {
            return .failure(SkipReason("request 'launch' değil"))
        }
        guard let type = config.type, supportedTypes.contains(type) else {
            return .failure(SkipReason("desteklenmeyen tür: \(config.type ?? "-")"))
        }
        if config.module == "pytest" || config.purpose.contains("debug-test") {
            return .failure(SkipReason("test konfigürasyonu"))
        }
        if config.variables.contains(where: { $0.hasPrefix("file") }) {
            return .failure(SkipReason("aktif dosyaya bağlı (${file})"))
        }
        if let other = config.variables.sorted().first(where: { $0 != "workspaceFolder" }) {
            return .failure(SkipReason("desteklenmeyen değişken: ${\(other)}"))
        }

        let root = repo.path
        func substitute(_ text: String) -> String {
            text.replacingOccurrences(of: "${workspaceFolder}", with: root)
        }

        let python = config.python.map(substitute) ?? repo.appendingPathComponent(".venv/bin/python").path
        let base: [String]
        if let module = config.module {
            base = [python, "-m", module]
        } else if let program = config.program {
            base = [python, substitute(program)]
        } else {
            return .failure(SkipReason("module veya program tanımlı değil"))
        }

        var args = config.args.map(substitute)
        let isUvicorn = config.module == "uvicorn"
        var reloadArgs: [String] = []
        var hadReload = false
        if isUvicorn {
            let split = splitReloadArgs(args)
            args = split.args
            hadReload = split.hadReload
            reloadArgs = ["--reload"] + split.extras
        }

        let env = config.env.mapValues(substitute)
        let definition = ServiceDefinition(
            name: config.name,
            command: base + args,
            cwd: config.cwd.map(substitute) ?? root,
            envFile: config.envFile.map(substitute) ?? repo.appendingPathComponent(".env").path,
            env: env,
            supportsReload: isUvicorn,
            reloadEnabled: hadReload,
            reloadArgs: reloadArgs,
            portHint: portHint(args: args, env: env)
        )
        return .success(Candidate(definition: definition, hadReload: hadReload))
    }

    static func splitReloadArgs(_ args: [String]) -> (args: [String], extras: [String], hadReload: Bool) {
        var kept: [String] = []
        var extras: [String] = []
        var hadReload = false
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--reload" {
                hadReload = true
            } else if reloadValueFlags.contains(arg) {
                extras.append(arg)
                if i + 1 < args.count {
                    extras.append(args[i + 1])
                    i += 1
                }
            } else if reloadValueFlags.contains(where: { arg.hasPrefix($0 + "=") }) {
                extras.append(arg)
            } else {
                kept.append(arg)
            }
            i += 1
        }
        return (kept, extras, hadReload)
    }

    static func portHint(args: [String], env: [String: String]) -> Int? {
        for (i, arg) in args.enumerated() {
            if arg == "--port", i + 1 < args.count, let port = Int(args[i + 1]) { return port }
            if arg.hasPrefix("--port="), let port = Int(arg.dropFirst("--port=".count)) { return port }
        }
        return env["PORT"].flatMap { Int($0) }
    }

    /// Configs identical except for reload flags collapse into one service with a reload toggle.
    static func merge(_ candidates: [Candidate]) -> [Candidate] {
        var order: [MergeKey] = []
        var groups: [MergeKey: [Candidate]] = [:]
        for candidate in candidates {
            let d = candidate.definition
            let key = MergeKey(command: d.command, cwd: d.cwd, envFile: d.envFile, env: d.env)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(candidate)
        }
        return order.map { key in
            let group = groups[key] ?? []
            var chosen = group.first(where: { !$0.hadReload }) ?? group[0]
            if let withReload = group.first(where: { $0.hadReload }) {
                chosen.definition.reloadEnabled = true
                chosen.definition.reloadArgs = withReload.definition.reloadArgs
                chosen.hadReload = true
            }
            return chosen
        }
    }
}
```

- [ ] **Step 5: Testlerin geçtiğini doğrula**

Run: `make test FILTER=LaunchJsonParserTests` ve `make test FILTER=LaunchConfigTranslatorTests`
Expected: İkisi de `passed` (4 + 8 test).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: translate VS Code launch configs into services"
```

---

### Task 4: package.json translator + RepoScanner

**Files:**
- Create: `Sources/DevLauncherCore/Discovery/PackageJsonTranslator.swift`, `Sources/DevLauncherCore/Discovery/RepoScanner.swift`
- Create: `Tests/DevLauncherCoreTests/Fixtures/{admin-web,wiki-web,flow-composer}/package.json`
- Test: `Tests/DevLauncherCoreTests/PackageJsonTranslatorTests.swift`, `Tests/DevLauncherCoreTests/RepoScannerTests.swift`

**Interfaces:**
- Consumes: `JSONCReader`, `ShellWords.split`, `Slug`, `LaunchJsonParser`, `LaunchConfigTranslator`, model types.
- Produces:
  - `PackageJsonTranslator.translate(_ data: Data, repo: URL, fileExists: (String) -> Bool = …) throws -> TranslationResult`
  - `PackageJsonTranslator.packageManager(repo:fileExists:) -> PackageManager`
  - `RepoDiscovery(repoPath:services:skipped:warnings:)`
  - `RepoScanner.candidateRepos(in: URL) -> [URL]`
  - `RepoScanner.discover(repo: URL) -> RepoDiscovery`

- [ ] **Step 1: Fixture'ları kopyala**

```bash
cd ~/Projects/devlauncher
F=Tests/DevLauncherCoreTests/Fixtures
for r in admin-web wiki-web flow-composer; do
  mkdir -p "$F/$r" && cp ~/Projects/acme/$r/package.json "$F/$r/package.json"
done
```

- [ ] **Step 2: Failing testleri yaz**

```swift
// File: Tests/DevLauncherCoreTests/PackageJsonTranslatorTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct PackageJsonTranslatorTests {
    func translate(_ repo: String, lockFiles: Set<String>) throws -> TranslationResult {
        try PackageJsonTranslator.translate(Fixtures.data("\(repo)/package.json"), repo: URL(fileURLWithPath: "/w/\(repo)")) { path in
            lockFiles.contains(URL(fileURLWithPath: path).lastPathComponent)
        }
    }

    @Test func viteSpaUsesNpmAndDefaultVitePort() throws {
        let r = try translate("admin-web", lockFiles: ["package-lock.json"])
        let s = try #require(r.services.first)
        #expect(s.id == "admin-web/dev")
        #expect(s.source == .packageJson("dev"))
        #expect(s.definition.command == ["npm", "run", "dev"])
        #expect(s.definition.cwd == "/w/admin-web")
        #expect(s.definition.portHint == 5173)
        #expect(s.definition.envFile == nil)
        #expect(!s.definition.supportsReload)
    }

    @Test func nextAppWithExplicitPortPrefersNpmLock() throws {
        let r = try translate("wiki-web", lockFiles: ["package-lock.json", "yarn.lock"])
        #expect(r.services.first?.definition.command == ["npm", "run", "dev"])
        #expect(r.services.first?.definition.portHint == 3000)
    }

    @Test func plainNextDevDefaultsTo3000() throws {
        let r = try translate("flow-composer", lockFiles: [])
        #expect(r.services.first?.definition.portHint == 3000)
    }

    @Test func lockFilePriority() {
        let repo = URL(fileURLWithPath: "/w/r")
        func pm(_ files: Set<String>) -> PackageManager {
            PackageJsonTranslator.packageManager(repo: repo) { files.contains(URL(fileURLWithPath: $0).lastPathComponent) }
        }
        #expect(pm(["yarn.lock", "pnpm-lock.yaml"]) == .pnpm)
        #expect(pm(["yarn.lock"]) == .yarn)
        #expect(pm([]) == .npm)
    }

    @Test func fallsBackToStartScriptAndReadsPortFlags() throws {
        let start = #"{ "scripts": { "start": "vite --port 4000" } }"#
        let r = try PackageJsonTranslator.translate(Data(start.utf8), repo: URL(fileURLWithPath: "/w/r")) { _ in false }
        #expect(r.services.first?.definition.command == ["npm", "run", "start"])
        #expect(r.services.first?.definition.portHint == 4000)
        let none = #"{ "scripts": { "build": "tsc" } }"#
        #expect(try PackageJsonTranslator.translate(Data(none.utf8), repo: URL(fileURLWithPath: "/w/r")) { _ in false }.services.isEmpty)
    }
}
```

```swift
// File: Tests/DevLauncherCoreTests/RepoScannerTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct RepoScannerTests {
    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func listsVisibleDirectoriesSorted() throws {
        let root = try makeTempDirectory()
        for name in ["b-repo", "a-repo", ".hidden", "node_modules"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try write("x", to: root.appendingPathComponent("file.txt"))
        #expect(RepoScanner.candidateRepos(in: root).map(\.lastPathComponent) == ["a-repo", "b-repo"])
        #expect(RepoScanner.candidateRepos(in: root.appendingPathComponent("missing")).isEmpty)
    }

    @Test func discoversLaunchAndPackageServicesWithUniqueIDs() throws {
        let repo = try makeTempDirectory().appendingPathComponent("web")
        try write(
            #"{ "configurations": [ { "name": "dev", "type": "debugpy", "request": "launch", "module": "uvicorn", "args": ["a:app"], }, ] } // c"#,
            to: repo.appendingPathComponent(".vscode/launch.json")
        )
        try write(#"{ "scripts": { "dev": "vite" } }"#, to: repo.appendingPathComponent("package.json"))
        let d = RepoScanner.discover(repo: repo)
        #expect(d.services.map(\.id) == ["web/dev", "web/dev-2"])
        #expect(d.services.map(\.source.kind) == [.launchJson, .packageJson])
        #expect(d.warnings.isEmpty)
    }

    @Test func brokenLaunchJsonIsReportedButPackageStillScanned() throws {
        let repo = try makeTempDirectory().appendingPathComponent("api")
        try write("{ not json", to: repo.appendingPathComponent(".vscode/launch.json"))
        try write(#"{ "scripts": { "dev": "next dev" } }"#, to: repo.appendingPathComponent("package.json"))
        let d = RepoScanner.discover(repo: repo)
        #expect(d.services.map(\.id) == ["api/dev"])
        #expect(d.warnings.count == 1)
        #expect(d.warnings.first?.contains("launch.json") == true)
    }

    @Test func missingRepoYieldsEmptyDiscovery() {
        let d = RepoScanner.discover(repo: URL(fileURLWithPath: "/nope/gone"))
        #expect(d.services.isEmpty)
        #expect(d.warnings.isEmpty)
    }
}
```

- [ ] **Step 3: Testin fail ettiğini doğrula**

Run: `make test FILTER=PackageJsonTranslatorTests`
Expected: Derleme hatası, `cannot find 'PackageJsonTranslator' in scope`.

- [ ] **Step 4: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Discovery/PackageJsonTranslator.swift
import Foundation

/// Turns a package.json `dev` (or `start`) script into a service definition.
public enum PackageJsonTranslator {
    static let lockFiles: [(file: String, manager: PackageManager)] = [
        ("pnpm-lock.yaml", .pnpm),
        ("package-lock.json", .npm),
        ("yarn.lock", .yarn),
    ]

    public static func translate(
        _ data: Data,
        repo: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> TranslationResult {
        let root = try JSONCReader.object(from: data)
        let scripts = root["scripts"] as? [String: Any] ?? [:]
        guard let scriptName = ["dev", "start"].first(where: { scripts[$0] is String }),
              let script = scripts[scriptName] as? String else {
            return TranslationResult(services: [], skipped: [])
        }
        let manager = packageManager(repo: repo, fileExists: fileExists)
        let definition = ServiceDefinition(
            name: scriptName,
            command: [manager.rawValue, "run", scriptName],
            cwd: repo.path,
            portHint: portHint(script: script)
        )
        let service = DiscoveredService(
            id: "\(repo.lastPathComponent)/\(Slug.make(scriptName))",
            source: .packageJson(scriptName),
            definition: definition
        )
        return TranslationResult(services: [service], skipped: [])
    }

    public static func packageManager(repo: URL, fileExists: (String) -> Bool) -> PackageManager {
        lockFiles.first { fileExists(repo.appendingPathComponent($0.file).path) }?.manager ?? .npm
    }

    static func portHint(script: String) -> Int? {
        let words = ShellWords.split(script)
        for (i, word) in words.enumerated() {
            if word == "--port" || word == "-p", i + 1 < words.count, let port = Int(words[i + 1]) { return port }
            if word.hasPrefix("--port="), let port = Int(word.dropFirst("--port=".count)) { return port }
        }
        if words.contains(where: { $0 == "vite" || $0.hasSuffix("/vite") }) { return 5173 }
        if words.contains("next") { return 3000 }
        return nil
    }
}
```

```swift
// File: Sources/DevLauncherCore/Discovery/RepoScanner.swift
import Foundation

public struct RepoDiscovery: Equatable, Sendable {
    public var repoPath: String
    public var services: [DiscoveredService]
    public var skipped: [SkippedConfig]
    public var warnings: [String]

    public init(repoPath: String, services: [DiscoveredService], skipped: [SkippedConfig], warnings: [String]) {
        self.repoPath = repoPath
        self.services = services
        self.skipped = skipped
        self.warnings = warnings
    }
}

public enum RepoScanner {
    static let excludedNames: Set<String> = ["node_modules"]

    /// First-level, non-hidden subdirectories of `root`, sorted by name.
    public static func candidateRepos(in root: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return items
            .filter { url in
                !excludedNames.contains(url.lastPathComponent)
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func discover(repo: URL) -> RepoDiscovery {
        var services: [DiscoveredService] = []
        var skipped: [SkippedConfig] = []
        var warnings: [String] = []

        if let data = try? Data(contentsOf: repo.appendingPathComponent(".vscode/launch.json")) {
            do {
                let result = LaunchConfigTranslator.translate(try LaunchJsonParser.parse(data), repo: repo)
                services += result.services
                skipped += result.skipped
            } catch {
                warnings.append(".vscode/launch.json okunamadı: \(error)")
            }
        }
        if let data = try? Data(contentsOf: repo.appendingPathComponent("package.json")) {
            do {
                let result = try PackageJsonTranslator.translate(data, repo: repo)
                services += result.services
                skipped += result.skipped
            } catch {
                warnings.append("package.json okunamadı: \(error)")
            }
        }

        var taken = Set<String>()
        for i in services.indices {
            let id = Slug.unique(services[i].id, taken: taken)
            services[i].id = id
            taken.insert(id)
        }
        return RepoDiscovery(repoPath: repo.path, services: services, skipped: skipped, warnings: warnings)
    }
}
```

- [ ] **Step 5: Testlerin geçtiğini doğrula**

Run: `make test FILTER=PackageJsonTranslatorTests` ve `make test FILTER=RepoScannerTests`
Expected: `5 + 4 tests passed`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: package.json discovery and repo scanner"
```

---

### Task 5: .env parser, env katmanları, shell ortamı

**Files:**
- Create: `Sources/DevLauncherCore/Environment/DotEnvParser.swift`, `Sources/DevLauncherCore/Environment/EnvResolver.swift`, `Sources/DevLauncherCore/Environment/ShellEnvironment.swift`
- Test: `Tests/DevLauncherCoreTests/EnvironmentTests.swift`

**Interfaces:**
- Consumes: `ServiceDefinition`.
- Produces:
  - `DotEnvParser.parse(_ text: String) -> [String: String]`
  - `EnvResolution(environment:warnings:)`, `EnvResolver.constants`
  - `EnvResolver.resolve(shell: [String: String], definition: ServiceDefinition, readFile: (String) -> String? = …) -> EnvResolution`
  - `ShellEnvironment(variables:error:)`, `ShellEnvironment.capture(shell: String = "/bin/zsh", timeout: TimeInterval = 5) -> ShellEnvironment`, `ShellEnvironment.fallbackPath`, internal `parse(_ data: Data) -> [String: String]?`, `beginMarker`, `endMarker`

- [ ] **Step 1: Failing testleri yaz**

```swift
// File: Tests/DevLauncherCoreTests/EnvironmentTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct DotEnvParserTests {
    @Test func parsesCommonFormats() {
        let text = "# comment\r\nA=1\r\nexport B = two \nC=\"quoted # not comment\"\nD='single'\nE=value # inline\nF=\"line\\nbreak\"\n=bad\nnoequals\nG=\n"
        let env = DotEnvParser.parse(text)
        #expect(env == [
            "A": "1", "B": "two", "C": "quoted # not comment", "D": "single",
            "E": "value", "F": "line\nbreak", "G": "",
        ])
    }
}

@Suite struct EnvResolverTests {
    let definition = ServiceDefinition(
        name: "api", command: ["py"], cwd: "/r", envFile: "/r/.env",
        env: ["FROM_CONFIG": "c", "SHARED": "config"]
    )

    @Test func layersInOrder() {
        let shell = ["PATH": "/bin", "SHARED": "shell", "FROM_SHELL": "s", "PYTHONUNBUFFERED": "0"]
        let r = EnvResolver.resolve(shell: shell, definition: definition) { path in
            path == "/r/.env" ? "SHARED=file\nFROM_FILE=f\nFROM_CONFIG=file" : nil
        }
        #expect(r.warnings.isEmpty)
        #expect(r.environment["PATH"] == "/bin")
        #expect(r.environment["FROM_SHELL"] == "s")
        #expect(r.environment["FROM_FILE"] == "f")
        #expect(r.environment["FROM_CONFIG"] == "c")
        #expect(r.environment["SHARED"] == "config")
        #expect(r.environment["PYTHONUNBUFFERED"] == "1")
        #expect(r.environment["FORCE_COLOR"] == "1")
    }

    @Test func missingEnvFileWarnsButContinues() {
        let r = EnvResolver.resolve(shell: [:], definition: definition) { _ in nil }
        #expect(r.warnings == ["Env dosyası bulunamadı: /r/.env"])
        #expect(r.environment["FROM_CONFIG"] == "c")
    }

    @Test func noEnvFileMeansNoRead() {
        var d = definition
        d.envFile = nil
        let r = EnvResolver.resolve(shell: [:], definition: d) { _ in
            Issue.record("env file should not be read")
            return nil
        }
        #expect(r.warnings.isEmpty)
    }
}

@Suite struct ShellEnvironmentTests {
    @Test func parsesMarkedNulSeparatedOutput() {
        var data = Data("motd noise\n".utf8)
        data.append(Data(ShellEnvironment.beginMarker.utf8))
        data.append(Data("PATH=/a:/b\0MULTI=x\ny\0=skip\0EMPTY=\0".utf8))
        data.append(Data(ShellEnvironment.endMarker.utf8))
        #expect(ShellEnvironment.parse(data) == ["PATH": "/a:/b", "MULTI": "x\ny", "EMPTY": ""])
    }

    @Test func parseFailsWithoutMarkers() {
        #expect(ShellEnvironment.parse(Data("PATH=/x".utf8)) == nil)
    }

    @Test func capturesRealLoginShell() {
        let env = ShellEnvironment.capture()
        #expect(env.error == nil)
        #expect(env.variables["PATH"]?.contains("/usr/bin") == true)
        #expect(env.variables["HOME"] == NSHomeDirectory())
    }

    @Test func fallsBackWhenShellMissing() {
        let env = ShellEnvironment.capture(shell: "/nonexistent/zsh", timeout: 1)
        #expect(env.error != nil)
        #expect(env.variables["PATH"] == ShellEnvironment.fallbackPath)
    }
}
```

- [ ] **Step 2: Testin fail ettiğini doğrula**

Run: `make test FILTER=DotEnvParserTests`
Expected: Derleme hatası, `cannot find 'DotEnvParser' in scope`.

- [ ] **Step 3: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Environment/DotEnvParser.swift
import Foundation

/// Minimal .env reader: KEY=VALUE lines, `#` comments, optional quotes and `export ` prefix.
/// No variable expansion and no multi-line values.
public enum DotEnvParser {
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let first = value.first, first == "\"" || first == "'" {
                let rest = value.dropFirst()
                if let close = rest.firstIndex(of: first) {
                    value = String(rest[..<close])
                    if first == "\"" { value = value.replacingOccurrences(of: "\\n", with: "\n") }
                }
            } else if let hash = value.range(of: " #") {
                value = value[..<hash.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            result[key] = value
        }
        return result
    }
}
```

```swift
// File: Sources/DevLauncherCore/Environment/EnvResolver.swift
import Foundation

public struct EnvResolution: Equatable, Sendable {
    public var environment: [String: String]
    public var warnings: [String]
}

/// Layers, lowest to highest: shell → env file → definition env → constants.
public enum EnvResolver {
    public static let constants = ["PYTHONUNBUFFERED": "1", "FORCE_COLOR": "1"]

    public static func resolve(
        shell: [String: String],
        definition: ServiceDefinition,
        readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) -> EnvResolution {
        var env = shell
        var warnings: [String] = []
        if let path = definition.envFile {
            if let text = readFile(path) {
                env.merge(DotEnvParser.parse(text)) { _, new in new }
            } else {
                warnings.append("Env dosyası bulunamadı: \(path)")
            }
        }
        env.merge(definition.env) { _, new in new }
        env.merge(constants) { _, new in new }
        return EnvResolution(environment: env, warnings: warnings)
    }
}
```

```swift
// File: Sources/DevLauncherCore/Environment/ShellEnvironment.swift
import Foundation

/// The user's login-shell environment, captured once so GUI-launched services see the same PATH as a terminal.
public struct ShellEnvironment: Equatable, Sendable {
    public var variables: [String: String]
    public var error: String?

    public init(variables: [String: String], error: String?) {
        self.variables = variables
        self.error = error
    }

    public static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    static let beginMarker = "__DEVLAUNCHER_ENV_BEGIN__"
    static let endMarker = "__DEVLAUNCHER_ENV_END__"

    public static func fallback(error: String, base: [String: String] = ProcessInfo.processInfo.environment) -> ShellEnvironment {
        var variables = base
        variables["PATH"] = fallbackPath
        return ShellEnvironment(variables: variables, error: error)
    }

    /// Runs an interactive login shell once and reads its environment between markers,
    /// so anything .zshrc prints is ignored.
    public static func capture(shell: String = "/bin/zsh", timeout: TimeInterval = 5) -> ShellEnvironment {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "printf '\(beginMarker)'; /usr/bin/env -0; printf '\(endMarker)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let buffer = LockedData()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            buffer.append(handle.availableData)
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return fallback(error: "Shell başlatılamadı: \(error.localizedDescription)")
        }
        let end = Data(endMarker.utf8)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, buffer.snapshot().range(of: end) == nil {
            Thread.sleep(forTimeInterval: 0.05)
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        guard let variables = parse(buffer.snapshot()) else {
            return fallback(error: "Shell ortamı \(Int(timeout)) sn içinde okunamadı")
        }
        return ShellEnvironment(variables: variables, error: nil)
    }

    /// Extracts NUL-separated `KEY=VALUE` pairs between the markers.
    static func parse(_ data: Data) -> [String: String]? {
        guard let begin = data.range(of: Data(beginMarker.utf8)),
              let end = data.range(of: Data(endMarker.utf8), in: begin.upperBound..<data.endIndex) else {
            return nil
        }
        var variables: [String: String] = [:]
        for entry in data[begin.upperBound..<end.lowerBound].split(separator: 0) {
            let text = String(decoding: entry, as: UTF8.self)
            guard let eq = text.firstIndex(of: "="), eq != text.startIndex else { continue }
            variables[String(text[..<eq])] = String(text[text.index(after: eq)...])
        }
        return variables.isEmpty ? nil : variables
    }
}

final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `make test FILTER=DotEnvParserTests`, `make test FILTER=EnvResolverTests`, `make test FILTER=ShellEnvironmentTests`
Expected: Hepsi `passed`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: env file parsing, env layering and login-shell capture"
```

---
### Task 6: AppConfig, ConfigStore, ConfigMerger

**Files:**
- Create: `Sources/DevLauncherCore/Config/AppConfig.swift`, `Sources/DevLauncherCore/Config/ConfigStore.swift`, `Sources/DevLauncherCore/Config/ConfigMerger.swift`
- Test: `Tests/DevLauncherCoreTests/ConfigStoreTests.swift`, `Tests/DevLauncherCoreTests/ConfigMergerTests.swift`

**Interfaces:**
- Consumes: `ServiceConfig`, `ServiceSource`, `DiscoveredService`, `RepoDiscovery`, `Slug.unique`.
- Produces:
  - `AppSettings(launchAtLogin:crashNotifications:)`
  - `RepoConfig(path:services:declinedSources:)` + `name`
  - `AppConfig(version:roots:ignoredRepos:pinnedOrder:settings:repos:)` + `defaultConfig(home:)`, `service(id:)`, `repo(containing:)`, `repoIndex(path:)`, `allServiceIDs`
  - `ConfigStore(directory:now:)`, `ConfigStore.defaultDirectory`, `load(defaultConfig:) -> ConfigLoadResult(config:warning:)`, `save(_:) throws`
  - `MergeOutcome(repo:suggestions:unmatched:)`, `ConfigMerger.merge(_:into:) -> MergeOutcome`, `ConfigMerger.accept(_:offered:into:takenIDs:) -> RepoConfig`

- [ ] **Step 1: Failing testleri yaz**

```swift
// File: Tests/DevLauncherCoreTests/ConfigStoreTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct ConfigStoreTests {
    func sampleConfig() -> AppConfig {
        var service = ServiceConfig(
            id: "api/dev",
            source: .launchJson("dev"),
            discovered: ServiceDefinition(
                name: "dev", command: ["/api/.venv/bin/python", "-m", "uvicorn", "a:app"], cwd: "/api",
                envFile: "/api/.env", supportsReload: true, reloadArgs: ["--reload"], portHint: 8000
            )
        )
        service.overrides.reloadEnabled = true
        return AppConfig(
            roots: ["/root"],
            ignoredRepos: ["/root/docs"],
            pinnedOrder: ["api/dev"],
            repos: [RepoConfig(path: "/api", services: [service], declinedSources: [.launchJson("tests")])]
        )
    }

    @Test func savesAndLoadsRoundTrip() throws {
        let dir = try makeTempDirectory().appendingPathComponent("nested")
        let store = ConfigStore(directory: dir)
        try store.save(sampleConfig())
        let loaded = store.load()
        #expect(loaded.warning == nil)
        #expect(loaded.config == sampleConfig())
    }

    @Test func missingFileGivesDefault() throws {
        let store = ConfigStore(directory: try makeTempDirectory())
        let loaded = store.load(defaultConfig: AppConfig(roots: ["/default"]))
        #expect(loaded.config.roots == ["/default"])
        #expect(loaded.warning == nil)
    }

    @Test func brokenFileIsBackedUp() throws {
        let dir = try makeTempDirectory()
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent("config.json"))
        let store = ConfigStore(directory: dir, now: { Date(timeIntervalSince1970: 0) })
        let loaded = store.load(defaultConfig: AppConfig(roots: ["/default"]))
        #expect(loaded.config.roots == ["/default"])
        #expect(loaded.warning?.contains("config.json.broken-") == true)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("config.json.broken-") })
        #expect(!files.contains("config.json"))
    }

    @Test func toleratesMissingFields() throws {
        let dir = try makeTempDirectory()
        try Data(#"{ "roots": ["/a"], "repos": [ { "path": "/a/x" } ] }"#.utf8).write(to: dir.appendingPathComponent("config.json"))
        let loaded = ConfigStore(directory: dir).load()
        #expect(loaded.warning == nil)
        #expect(loaded.config.roots == ["/a"])
        #expect(loaded.config.repos.first?.services == [])
        #expect(loaded.config.repos.first?.declinedSources == [])
        #expect(loaded.config.settings.crashNotifications)
        #expect(loaded.config.version == AppConfig.currentVersion)
    }

    @Test func lookupHelpers() {
        let c = sampleConfig()
        #expect(c.service(id: "api/dev")?.overrides.reloadEnabled == true)
        #expect(c.service(id: "nope") == nil)
        #expect(c.repo(containing: "api/dev")?.path == "/api")
        #expect(c.repo(containing: "api/dev")?.name == "api")
        #expect(c.repoIndex(path: "/api") == 0)
        #expect(c.allServiceIDs == ["api/dev"])
        #expect(AppConfig.defaultConfig(home: URL(fileURLWithPath: "/Users/u")).roots == ["/Users/u/Projects/acme"])
    }
}
```

```swift
// File: Tests/DevLauncherCoreTests/ConfigMergerTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct ConfigMergerTests {
    func discovered(_ name: String, port: Int? = nil) -> DiscoveredService {
        DiscoveredService(
            id: "repo/\(Slug.make(name))",
            source: .launchJson(name),
            definition: ServiceDefinition(name: name, command: ["run", name], cwd: "/repo", portHint: port)
        )
    }

    func discovery(_ services: [DiscoveredService]) -> RepoDiscovery {
        RepoDiscovery(repoPath: "/repo", services: services, skipped: [], warnings: [])
    }

    @Test func updatesDiscoveredButKeepsOverrides() {
        var existing = ServiceConfig(id: "repo/api", source: .launchJson("api"), discovered: discovered("api", port: 1).definition)
        existing.overrides.portHint = 9999
        let outcome = ConfigMerger.merge(discovery([discovered("api", port: 2)]), into: RepoConfig(path: "/repo", services: [existing]))
        let merged = outcome.repo.services[0]
        #expect(merged.discovered.portHint == 2)
        #expect(merged.overrides.portHint == 9999)
        #expect(merged.effective.portHint == 9999)
        #expect(!merged.sourceMissing)
        #expect(outcome.suggestions.isEmpty)
        #expect(outcome.unmatched.isEmpty)
    }

    @Test func marksMissingAndSuggestsNew() {
        let old = ServiceConfig(id: "repo/old", source: .launchJson("old"), discovered: discovered("old").definition)
        let manual = ServiceConfig(id: "repo/mvn", source: .manual, discovered: ServiceDefinition(name: "mvn", command: ["mvn"], cwd: "/repo"))
        let repo = RepoConfig(path: "/repo", services: [old, manual], declinedSources: [.launchJson("declined")])
        let outcome = ConfigMerger.merge(discovery([discovered("new"), discovered("declined")]), into: repo)
        #expect(outcome.repo.services.count == 2)
        #expect(outcome.repo.services[0].sourceMissing)
        #expect(!outcome.repo.services[1].sourceMissing)
        #expect(outcome.suggestions.map(\.definition.name) == ["new"])
        #expect(outcome.unmatched.map(\.definition.name) == ["new", "declined"])
    }

    @Test func deletedRepoFolderMarksEverythingMissingWithoutDeleting() {
        var service = ServiceConfig(id: "repo/api", source: .launchJson("api"), discovered: discovered("api").definition)
        service.overrides.name = "Benim API"
        let outcome = ConfigMerger.merge(discovery([]), into: RepoConfig(path: "/repo", services: [service]))
        #expect(outcome.repo.services.count == 1)
        #expect(outcome.repo.services[0].sourceMissing)
        #expect(outcome.repo.services[0].effective.name == "Benim API")
    }

    @Test func acceptAssignsUniqueIDsAndRecordsDeclined() {
        let offered = [discovered("api"), discovered("worker"), discovered("tests")]
        let repo = ConfigMerger.accept([offered[0], offered[1]], offered: offered, into: RepoConfig(path: "/repo"), takenIDs: ["repo/api"])
        #expect(repo.services.map(\.id) == ["repo/api-2", "repo/worker"])
        #expect(repo.declinedSources == [.launchJson("tests")])

        let again = ConfigMerger.accept([], offered: offered, into: repo, takenIDs: Set(repo.services.map(\.id)))
        #expect(again.declinedSources == [.launchJson("tests")])

        let reAccepted = ConfigMerger.accept([offered[2]], offered: [offered[2]], into: again, takenIDs: Set(again.services.map(\.id)))
        #expect(reAccepted.services.count == 3)
        #expect(reAccepted.declinedSources.isEmpty)
    }
}
```

- [ ] **Step 2: Testin fail ettiğini doğrula**

Run: `make test FILTER=ConfigStoreTests`
Expected: Derleme hatası, `cannot find 'AppConfig' in scope`.

- [ ] **Step 3: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Config/AppConfig.swift
import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool
    public var crashNotifications: Bool

    public init(launchAtLogin: Bool = false, crashNotifications: Bool = true) {
        self.launchAtLogin = launchAtLogin
        self.crashNotifications = crashNotifications
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        crashNotifications = try c.decodeIfPresent(Bool.self, forKey: .crashNotifications) ?? true
    }
}

public struct RepoConfig: Codable, Equatable, Sendable {
    public var path: String
    public var services: [ServiceConfig]
    /// Discovered sources the user chose not to add; they are not suggested again.
    public var declinedSources: [ServiceSource]

    public init(path: String, services: [ServiceConfig] = [], declinedSources: [ServiceSource] = []) {
        self.path = path
        self.services = services
        self.declinedSources = declinedSources
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        services = try c.decodeIfPresent([ServiceConfig].self, forKey: .services) ?? []
        declinedSources = try c.decodeIfPresent([ServiceSource].self, forKey: .declinedSources) ?? []
    }

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var roots: [String]
    public var ignoredRepos: [String]
    public var pinnedOrder: [String]
    public var settings: AppSettings
    public var repos: [RepoConfig]

    public init(
        version: Int = AppConfig.currentVersion,
        roots: [String] = [],
        ignoredRepos: [String] = [],
        pinnedOrder: [String] = [],
        settings: AppSettings = AppSettings(),
        repos: [RepoConfig] = []
    ) {
        self.version = version
        self.roots = roots
        self.ignoredRepos = ignoredRepos
        self.pinnedOrder = pinnedOrder
        self.settings = settings
        self.repos = repos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        roots = try c.decodeIfPresent([String].self, forKey: .roots) ?? []
        ignoredRepos = try c.decodeIfPresent([String].self, forKey: .ignoredRepos) ?? []
        pinnedOrder = try c.decodeIfPresent([String].self, forKey: .pinnedOrder) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        repos = try c.decodeIfPresent([RepoConfig].self, forKey: .repos) ?? []
    }

    public static func defaultConfig(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AppConfig {
        AppConfig(roots: [home.appendingPathComponent("Projects/acme").path])
    }

    public func service(id: String) -> ServiceConfig? {
        for repo in repos {
            if let service = repo.services.first(where: { $0.id == id }) { return service }
        }
        return nil
    }

    public func repo(containing serviceID: String) -> RepoConfig? {
        repos.first { $0.services.contains { $0.id == serviceID } }
    }

    public func repoIndex(path: String) -> Int? {
        repos.firstIndex { $0.path == path }
    }

    public var allServiceIDs: Set<String> {
        Set(repos.flatMap { $0.services.map(\.id) })
    }
}
```

```swift
// File: Sources/DevLauncherCore/Config/ConfigStore.swift
import Foundation

public struct ConfigLoadResult: Equatable, Sendable {
    public var config: AppConfig
    /// Set when an unreadable config.json was moved aside.
    public var warning: String?
}

public final class ConfigStore {
    public let fileURL: URL
    private let now: () -> Date

    public init(directory: URL, now: @escaping () -> Date = { Date() }) {
        fileURL = directory.appendingPathComponent("config.json")
        self.now = now
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevLauncher")
    }

    public func load(defaultConfig: AppConfig = .defaultConfig()) -> ConfigLoadResult {
        guard let data = try? Data(contentsOf: fileURL) else {
            return ConfigLoadResult(config: defaultConfig, warning: nil)
        }
        do {
            return ConfigLoadResult(config: try JSONDecoder().decode(AppConfig.self, from: data), warning: nil)
        } catch {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("config.json.broken-\(formatter.string(from: now()))")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return ConfigLoadResult(
                config: defaultConfig,
                warning: "config.json okunamadı; yedeği \(backup.lastPathComponent) olarak saklandı."
            )
        }
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }
}
```

```swift
// File: Sources/DevLauncherCore/Config/ConfigMerger.swift
import Foundation

public struct MergeOutcome: Equatable, Sendable {
    public var repo: RepoConfig
    /// Discovered services that are not in the repo and were not declined.
    public var suggestions: [DiscoveredService]
    /// Every discovered service that is not in the repo, declined ones included.
    public var unmatched: [DiscoveredService]
}

public enum ConfigMerger {
    /// Refreshes discovered definitions (user overrides win), flags services whose source vanished,
    /// and reports discovered services that are not configured yet.
    public static func merge(_ discovery: RepoDiscovery, into repo: RepoConfig) -> MergeOutcome {
        var repo = repo
        var matched = Set<ServiceSource>()
        for i in repo.services.indices where repo.services[i].source.kind != .manual {
            if let found = discovery.services.first(where: { $0.source == repo.services[i].source }) {
                repo.services[i].discovered = found.definition
                repo.services[i].sourceMissing = false
                matched.insert(found.source)
            } else {
                repo.services[i].sourceMissing = true
            }
        }
        let declined = Set(repo.declinedSources)
        let unmatched = discovery.services.filter { !matched.contains($0.source) }
        let suggestions = unmatched.filter { !declined.contains($0.source) }
        return MergeOutcome(repo: repo, suggestions: suggestions, unmatched: unmatched)
    }

    /// Adds `selected` to the repo and records the rest of `offered` as declined.
    public static func accept(
        _ selected: [DiscoveredService],
        offered: [DiscoveredService],
        into repo: RepoConfig,
        takenIDs: Set<String>
    ) -> RepoConfig {
        var repo = repo
        var taken = takenIDs.union(repo.services.map(\.id))
        for service in selected where !repo.services.contains(where: { $0.source == service.source }) {
            let id = Slug.unique(service.id, taken: taken)
            taken.insert(id)
            repo.services.append(ServiceConfig(id: id, source: service.source, discovered: service.definition))
        }
        let selectedSources = Set(selected.map(\.source))
        repo.declinedSources.removeAll { selectedSources.contains($0) }
        let present = Set(repo.services.map(\.source))
        for service in offered
        where !present.contains(service.source) && !repo.declinedSources.contains(service.source) {
            repo.declinedSources.append(service.source)
        }
        return repo
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `make test FILTER=ConfigStoreTests` ve `make test FILTER=ConfigMergerTests`
Expected: `5 + 4 tests passed`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: persistent config with rescan merging"
```

---

### Task 7: ProcessRunner (posix_spawn + process group)

**Files:**
- Create: `Sources/DevLauncherCore/Process/ProcessTypes.swift`, `Sources/DevLauncherCore/Process/LineBuffer.swift`, `Sources/DevLauncherCore/Process/ProcessInspector.swift`, `Sources/DevLauncherCore/Process/ProcessRunner.swift`
- Test: `Tests/DevLauncherCoreTests/LineBufferTests.swift`, `Tests/DevLauncherCoreTests/ProcessRunnerTests.swift`

**Interfaces:**
- Produces:
  - `OutputKind { stdout, stderr, system }`
  - `ExitStatus { exited(Int32), signaled(Int32) }` + `init(waitStatus:)`, `code`, `description`
  - `SpawnRequest(executable:arguments:environment:cwd:)`
  - `ProcessRunnerError { executableNotFound(String), directoryNotFound(String), spawnFailed(Int32) }`
  - `LineBuffer.append(_:) -> [String]`, `flush() -> String?`
  - `ProcessInspector.isAlive(_:)`, `isGroupAlive(_:)`, `startTime(of:) -> UInt64?`
  - `SpawnedProcess` (`pid`, `pgid`, `startTime`)
  - `ProcessRunner.resolveExecutable(_:searchPath:) -> String?`
  - `ProcessRunner.spawn(_:onLines:onExit:) throws -> SpawnedProcess`
  - `ProcessRunner.terminateGroup(_:grace:) async -> Bool`, which returns true if SIGKILL was needed

- [ ] **Step 1: Failing testleri yaz**

```swift
// File: Tests/DevLauncherCoreTests/LineBufferTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct LineBufferTests {
    @Test func splitsLinesAcrossChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("a\nb".utf8)) == ["a"])
        #expect(buffer.append(Data("c\r\nd\n".utf8)) == ["bc", "d"])
        #expect(buffer.flush() == nil)
        #expect(buffer.append(Data("tail".utf8)).isEmpty)
        #expect(buffer.flush() == "tail")
    }

    @Test func flushesVeryLongLinesWithoutNewline() {
        var buffer = LineBuffer()
        let lines = buffer.append(Data(repeating: 0x78, count: 70_000))
        #expect(lines.count == 1)
        #expect(lines.first?.count == 70_000)
        #expect(buffer.flush() == nil)
    }
}
```

```swift
// File: Tests/DevLauncherCoreTests/ProcessRunnerTests.swift
import Darwin
import Foundation
import Testing
@testable import DevLauncherCore

final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [(OutputKind, String)] = []
    private var status: ExitStatus?

    func add(_ kind: OutputKind, _ lines: [String]) {
        lock.lock()
        collected += lines.map { (kind, $0) }
        lock.unlock()
    }

    func finish(_ exit: ExitStatus) {
        lock.lock()
        status = exit
        lock.unlock()
    }

    var lines: [(OutputKind, String)] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    var exit: ExitStatus? {
        lock.lock()
        defer { lock.unlock() }
        return status
    }
}

@Suite(.serialized) struct ProcessRunnerTests {
    func sh(_ script: String, _ extra: [String] = []) -> SpawnRequest {
        SpawnRequest(executable: "/bin/sh", arguments: ["-c", script] + extra, environment: ["PATH": "/usr/bin:/bin"], cwd: "/tmp")
    }

    func spawn(_ request: SpawnRequest, into collector: OutputCollector) throws -> SpawnedProcess {
        try ProcessRunner.spawn(request, onLines: { collector.add($0, $1) }, onExit: { collector.finish($0) })
    }

    @Test func capturesOutputAndExitCode() async throws {
        let c = OutputCollector()
        _ = try spawn(sh("echo hello; echo oops 1>&2; printf partial; exit 3"), into: c)
        #expect(await waitUntil { c.exit != nil && c.lines.count == 3 })
        #expect(c.exit == .exited(3))
        #expect(c.lines.filter { $0.0 == .stdout }.map(\.1) == ["hello", "partial"])
        #expect(c.lines.contains { $0.0 == .stderr && $0.1 == "oops" })
    }

    @Test func passesEnvironmentAndWorkingDirectory() async throws {
        let c = OutputCollector()
        var request = sh("echo $DL_TEST; pwd")
        request.environment["DL_TEST"] = "merhaba"
        request.cwd = "/usr"
        _ = try spawn(request, into: c)
        #expect(await waitUntil { c.exit != nil && c.lines.count == 2 })
        #expect(c.lines.map(\.1) == ["merhaba", "/usr"])
    }

    @Test func handlesPathsWithSpacesAndTurkishCharacters() async throws {
        let dir = try makeTempDirectory().appendingPathComponent("çalışma klasörü")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let c = OutputCollector()
        var request = sh(#"pwd; echo "$0""#, ["ağ değer"])
        request.cwd = dir.path
        _ = try spawn(request, into: c)
        #expect(await waitUntil { c.exit != nil && c.lines.count == 2 })
        #expect(c.lines.first?.1.hasSuffix("çalışma klasörü") == true)
        #expect(c.lines.last?.1 == "ağ değer")
    }

    @Test func terminateGroupKillsChildren() async throws {
        let c = OutputCollector()
        let process = try spawn(sh("sleep 100 & sleep 100 & echo ready; wait"), into: c)
        #expect(await waitUntil { c.lines.contains { $0.1 == "ready" } })
        #expect(ProcessInspector.isGroupAlive(process.pgid))
        let killed = await ProcessRunner.terminateGroup(process.pgid, grace: 3)
        #expect(!killed)
        #expect(await waitUntil { !ProcessInspector.isGroupAlive(process.pgid) })
        #expect(await waitUntil { c.exit != nil })
    }

    @Test func escalatesToSigkill() async throws {
        let c = OutputCollector()
        let process = try spawn(sh("trap '' TERM; sleep 100 & echo ready; wait"), into: c)
        #expect(await waitUntil { c.lines.contains { $0.1 == "ready" } })
        let killed = await ProcessRunner.terminateGroup(process.pgid, grace: 0.5)
        #expect(killed)
        #expect(await waitUntil { !ProcessInspector.isGroupAlive(process.pgid) })
        #expect(await waitUntil { c.exit == .signaled(SIGKILL) })
    }

    @Test func refusesToSignalInvalidGroups() async {
        #expect(await ProcessRunner.terminateGroup(0, grace: 0.1) == false)
        #expect(await ProcessRunner.terminateGroup(1, grace: 0.1) == false)
    }

    @Test func rejectsMissingExecutableAndDirectory() {
        #expect(throws: ProcessRunnerError.executableNotFound("/nope/bin")) {
            try ProcessRunner.spawn(SpawnRequest(executable: "/nope/bin", arguments: [], environment: [:], cwd: "/tmp"), onLines: { _, _ in }, onExit: { _ in })
        }
        #expect(throws: ProcessRunnerError.directoryNotFound("/nope/dir")) {
            try ProcessRunner.spawn(SpawnRequest(executable: "/bin/sh", arguments: [], environment: [:], cwd: "/nope/dir"), onLines: { _, _ in }, onExit: { _ in })
        }
    }

    @Test func resolvesExecutablesOnPath() {
        #expect(ProcessRunner.resolveExecutable("sh", searchPath: "/nope:/bin") == "/bin/sh")
        #expect(ProcessRunner.resolveExecutable("/bin/sh", searchPath: nil) == "/bin/sh")
        #expect(ProcessRunner.resolveExecutable("definitely-missing-xyz", searchPath: "/bin") == nil)
    }

    @Test func inspectsProcesses() {
        #expect(ProcessInspector.startTime(of: getpid()) != nil)
        #expect(ProcessInspector.startTime(of: 999_999) == nil)
        #expect(ProcessInspector.isAlive(getpid()))
        #expect(!ProcessInspector.isAlive(999_999))
    }

    @Test func decodesWaitStatus() {
        #expect(ExitStatus(waitStatus: 3 << 8) == .exited(3))
        #expect(ExitStatus(waitStatus: 9) == .signaled(9))
        #expect(ExitStatus.signaled(9).code == 137)
        #expect(ExitStatus.exited(2).code == 2)
    }
}
```

- [ ] **Step 2: Testin fail ettiğini doğrula**

Run: `make test FILTER=LineBufferTests`
Expected: Derleme hatası, `cannot find 'LineBuffer' in scope`.

- [ ] **Step 3: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Process/ProcessTypes.swift
import Foundation

public enum OutputKind: String, Codable, Sendable {
    case stdout, stderr, system
}

public enum ExitStatus: Equatable, Sendable, CustomStringConvertible {
    case exited(Int32)
    case signaled(Int32)

    /// Decodes a `waitpid` status word.
    public init(waitStatus: Int32) {
        let signal = waitStatus & 0x7f
        self = signal == 0 ? .exited((waitStatus >> 8) & 0xff) : .signaled(signal)
    }

    /// Shell-style code: the exit code, or 128 + signal number.
    public var code: Int32 {
        switch self {
        case .exited(let code): return code
        case .signaled(let signal): return 128 + signal
        }
    }

    public var description: String {
        switch self {
        case .exited(let code): return "çıkış kodu \(code)"
        case .signaled(let signal): return "sinyal \(signal)"
        }
    }
}

public struct SpawnRequest: Equatable, Sendable {
    /// Absolute path of the executable.
    public var executable: String
    /// Arguments after argv[0].
    public var arguments: [String]
    public var environment: [String: String]
    public var cwd: String

    public init(executable: String, arguments: [String], environment: [String: String], cwd: String) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.cwd = cwd
    }
}

public enum ProcessRunnerError: Error, Equatable, CustomStringConvertible {
    case executableNotFound(String)
    case directoryNotFound(String)
    case spawnFailed(Int32)

    public var description: String {
        switch self {
        case .executableNotFound(let name): return "çalıştırılabilir dosya bulunamadı: \(name)"
        case .directoryNotFound(let path): return "çalışma klasörü yok: \(path)"
        case .spawnFailed(let code): return "süreç başlatılamadı: \(String(cString: strerror(code)))"
        }
    }
}
```

```swift
// File: Sources/DevLauncherCore/Process/LineBuffer.swift
import Foundation

/// Splits a byte stream into lines; partial lines wait for more data.
public struct LineBuffer: Sendable {
    /// Lines longer than this are emitted without waiting for a newline.
    static let maxPending = 64 * 1024

    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
            lines.append(Self.decode(pending[start..<newline]))
            start = pending.index(after: newline)
        }
        if start != pending.startIndex { pending = Data(pending[start...]) }
        if pending.count > Self.maxPending {
            lines.append(Self.decode(pending))
            pending = Data()
        }
        return lines
    }

    public mutating func flush() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending = Data() }
        return Self.decode(pending)
    }

    static func decode(_ bytes: Data) -> String {
        var bytes = bytes
        if bytes.last == 0x0D { bytes = bytes.dropLast() }
        return String(decoding: bytes, as: UTF8.self)
    }
}
```

```swift
// File: Sources/DevLauncherCore/Process/ProcessInspector.swift
import Darwin
import Foundation

public enum ProcessInspector {
    public static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public static func isGroupAlive(_ pgid: pid_t) -> Bool {
        guard pgid > 1 else { return false }
        return kill(-pgid, 0) == 0 || errno == EPERM
    }

    /// Process start time in microseconds since 1970, or nil if there is no such process.
    public static func startTime(of pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
    }
}
```

```swift
// File: Sources/DevLauncherCore/Process/ProcessRunner.swift
import Darwin
import Foundation

/// A child started by `ProcessRunner`. It keeps itself alive until it has exited and its output is drained.
public final class SpawnedProcess: @unchecked Sendable {
    public let pid: pid_t
    public let startTime: UInt64
    public var pgid: pid_t { pid }

    private let queue = DispatchQueue(label: "devlauncher.process")
    private var exitSource: DispatchSourceProcess?
    private var handles: [FileHandle] = []
    private var exited = false

    init(pid: pid_t, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }

    final class LineBufferBox: @unchecked Sendable {
        var buffer = LineBuffer()
    }

    func attachReader(fd: Int32, kind: OutputKind, onLines: @escaping ProcessRunner.LinesHandler) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let box = LineBufferBox()
        handle.readabilityHandler = { [self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                if let rest = box.buffer.flush() { onLines(kind, [rest]) }
                self.queue.async { self.handles.removeAll { $0 === h } }
                return
            }
            let lines = box.buffer.append(data)
            if !lines.isEmpty { onLines(kind, lines) }
        }
        queue.sync { handles.append(handle) }
    }

    func watchExit(onExit: @escaping ProcessRunner.ExitHandler) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler { [self] in self.reap(onExit) }
        exitSource = source
        source.resume()
        // The child may have exited before the source was registered.
        queue.async { [self] in self.reap(onExit) }
    }

    /// Runs on `queue`.
    private func reap(_ onExit: ProcessRunner.ExitHandler) {
        guard !exited else { return }
        var status: Int32 = 0
        guard waitpid(pid, &status, WNOHANG) == pid else { return }
        exited = true
        exitSource?.cancel()
        exitSource = nil
        onExit(ExitStatus(waitStatus: status))
    }
}

public enum ProcessRunner {
    public typealias LinesHandler = @Sendable (OutputKind, [String]) -> Void
    public typealias ExitHandler = @Sendable (ExitStatus) -> Void

    /// Resolves a bare command name against `searchPath`; names containing "/" must exist as given.
    public static func resolveExecutable(_ name: String, searchPath: String?) -> String? {
        let fm = FileManager.default
        if name.contains("/") { return fm.isExecutableFile(atPath: name) ? name : nil }
        for dir in (searchPath ?? "").split(separator: ":") where !dir.isEmpty {
            let candidate = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Starts the request in a new process group whose id equals the child pid.
    public static func spawn(
        _ request: SpawnRequest,
        onLines: @escaping LinesHandler,
        onExit: @escaping ExitHandler
    ) throws -> SpawnedProcess {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProcessRunnerError.directoryNotFound(request.cwd)
        }
        guard FileManager.default.isExecutableFile(atPath: request.executable) else {
            throw ProcessRunnerError.executableNotFound(request.executable)
        }

        var outPipe: [Int32] = [0, 0]
        var errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else { throw ProcessRunnerError.spawnFailed(errno) }
        guard pipe(&errPipe) == 0 else {
            let code = errno
            close(outPipe[0]); close(outPipe[1])
            throw ProcessRunnerError.spawnFailed(code)
        }
        for fd in outPipe + errPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        posix_spawn_file_actions_addchdir_np(&actions, request.cwd)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaultSignals: sigset_t = 0
        for signal in [SIGPIPE, SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGCHLD, SIGUSR1, SIGUSR2] {
            defaultSignals |= sigset_t(1) << sigset_t(signal - 1)
        }
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        var noSignals: sigset_t = 0
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))

        let argv: [UnsafeMutablePointer<CChar>?] = ([request.executable] + request.arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = request.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, request.executable, &actions, &attributes, argv, envp)
        close(outPipe[1])
        close(errPipe[1])
        guard rc == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            throw ProcessRunnerError.spawnFailed(rc)
        }

        let process = SpawnedProcess(pid: pid, startTime: ProcessInspector.startTime(of: pid) ?? 0)
        process.attachReader(fd: outPipe[0], kind: .stdout, onLines: onLines)
        process.attachReader(fd: errPipe[0], kind: .stderr, onLines: onLines)
        process.watchExit(onExit: onExit)
        return process
    }

    /// SIGTERM to the whole group, then SIGKILL after `grace` seconds. Returns true if SIGKILL was needed.
    @discardableResult
    public static func terminateGroup(_ pgid: pid_t, grace: TimeInterval = 5) async -> Bool {
        guard pgid > 1 else { return false }
        kill(-pgid, SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if !ProcessInspector.isGroupAlive(pgid) { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard ProcessInspector.isGroupAlive(pgid) else { return false }
        kill(-pgid, SIGKILL)
        return true
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `make test FILTER=LineBufferTests` ve `make test FILTER=ProcessRunnerTests`
Expected: `2 + 10 tests passed`. `escalatesToSigkill` yaklaşık 0,5 sn sürer.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: process runner with process groups and graceful termination"
```

---

### Task 8: PortProbe

**Files:**
- Create: `Sources/DevLauncherCore/Process/PortProbe.swift`
- Test: `Tests/DevLauncherCoreTests/PortProbeTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner.spawn`, `ProcessRunner.terminateGroup`, `ShellEnvironment.fallbackPath` (yalnızca test).
- Produces:
  - `ListeningSocket(pid:pgid:command:port:)`
  - `PortProbe.snapshot() -> [ListeningSocket]`
  - `PortProbe.ports(forGroup:in:) -> [Int]` (sıralı, tekil)
  - `PortProbe.owners(ofPort:in:) -> [ListeningSocket]`
  - internal `parse(_ output: String) -> [ListeningSocket]`

- [ ] **Step 1: Failing testi yaz**

```swift
// File: Tests/DevLauncherCoreTests/PortProbeTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite(.serialized) struct PortProbeTests {
    @Test func parsesLsofFieldOutput() {
        let output = "p100\ng100\ncpython3.11\nf5\nn127.0.0.1:8010\nf6\nn[::1]:8010\np200\ng150\ncnode\nf20\nn*:5173\n"
        let sockets = PortProbe.parse(output)
        #expect(sockets == [
            ListeningSocket(pid: 100, pgid: 100, command: "python3.11", port: 8010),
            ListeningSocket(pid: 200, pgid: 150, command: "node", port: 5173),
        ])
        #expect(PortProbe.ports(forGroup: 150, in: sockets) == [5173])
        #expect(PortProbe.owners(ofPort: 8010, in: sockets).map(\.pid) == [100])
        #expect(PortProbe.ports(forGroup: 999, in: sockets).isEmpty)
    }

    @Test func findsPortOfRealServerByProcessGroup() async throws {
        let c = OutputCollector()
        let request = SpawnRequest(
            executable: "/bin/sh",
            arguments: ["-c", "exec python3 -u -m http.server 0 --bind 127.0.0.1"],
            environment: ["PATH": ShellEnvironment.fallbackPath],
            cwd: "/tmp"
        )
        let process = try ProcessRunner.spawn(request, onLines: { c.add($0, $1) }, onExit: { c.finish($0) })
        defer { Task { await ProcessRunner.terminateGroup(process.pgid, grace: 1) } }

        var printed: Int?
        #expect(await waitUntil(timeout: 10) {
            printed = c.lines.lazy.compactMap { line -> Int? in
                guard let r = line.1.range(of: #"port (\d+)"#, options: .regularExpression) else { return nil }
                return Int(line.1[r].dropFirst("port ".count))
            }.first
            return printed != nil
        })
        var ports: [Int] = []
        #expect(await waitUntil(timeout: 10) {
            ports = PortProbe.ports(forGroup: process.pgid, in: PortProbe.snapshot())
            return !ports.isEmpty
        })
        #expect(ports == [try #require(printed)])
    }
}
```

- [ ] **Step 2: Testin fail ettiğini doğrula**

Run: `make test FILTER=PortProbeTests`
Expected: Derleme hatası, `cannot find 'PortProbe' in scope`.

- [ ] **Step 3: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Process/PortProbe.swift
import Foundation

public struct ListeningSocket: Equatable, Sendable {
    public var pid: pid_t
    public var pgid: pid_t
    public var command: String
    public var port: Int

    public init(pid: pid_t, pgid: pid_t, command: String, port: Int) {
        self.pid = pid
        self.pgid = pgid
        self.command = command
        self.port = port
    }
}

/// Finds listening TCP ports with `lsof`, so a service is "running" only once it actually listens.
public enum PortProbe {
    /// All TCP sockets in LISTEN state owned by processes visible to this user.
    public static func snapshot() -> [ListeningSocket] {
        guard let output = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpgcn"]) else { return [] }
        return parse(output)
    }

    public static func ports(forGroup pgid: pid_t, in snapshot: [ListeningSocket]) -> [Int] {
        Array(Set(snapshot.filter { $0.pgid == pgid }.map(\.port))).sorted()
    }

    public static func owners(ofPort port: Int, in snapshot: [ListeningSocket]) -> [ListeningSocket] {
        snapshot.filter { $0.port == port }
    }

    static func parse(_ output: String) -> [ListeningSocket] {
        var result: [ListeningSocket] = []
        var pid: pid_t = 0
        var pgid: pid_t = 0
        var command = ""
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p":
                pid = pid_t(value) ?? 0
                pgid = 0
                command = ""
            case "g":
                pgid = pid_t(value) ?? 0
            case "c":
                command = String(value)
            case "n":
                guard let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                let socket = ListeningSocket(pid: pid, pgid: pgid, command: command, port: port)
                if !result.contains(socket) { result.append(socket) }
            default:
                break
            }
        }
        return result
    }

    static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `make test FILTER=PortProbeTests`
Expected: `2 tests passed`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: detect listening ports per process group via lsof"
```

---
### Task 9: ANSI parser, LogBuffer, LogFileWriter

**Files:**
- Create: `Sources/DevLauncherCore/Logs/ANSIParser.swift`, `Sources/DevLauncherCore/Logs/LogBuffer.swift`, `Sources/DevLauncherCore/Logs/LogFileWriter.swift`
- Test: `Tests/DevLauncherCoreTests/LogTests.swift`

**Interfaces:**
- Consumes: `OutputKind`, `Slug.make`.
- Produces:
  - `ANSIColor { standard(Int), bright(Int), palette(Int), rgb(Int, Int, Int) }`, `ANSIStyle(foreground:bold:dim:)`, `ANSISpan(text:style:)`
  - `ANSIParser.parse(_:) -> [ANSISpan]`, `ANSIParser.strip(_:) -> String`
  - `LogLine(id:kind:text:date:)`
  - `@MainActor @Observable LogBuffer(capacity: 5_000)` with `lines`, `append(_:_:date:)`, `clear()`
  - `LogFileWriter(url:maxBytes:)` with `write(_:)`, `flush()`, `url(forService:directory:)`, `defaultDirectory`

- [ ] **Step 1: Failing testleri yaz**

```swift
// File: Tests/DevLauncherCoreTests/LogTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct ANSIParserTests {
    @Test func plainTextIsOneUnstyledSpan() {
        #expect(ANSIParser.parse("hello") == [ANSISpan(text: "hello", style: ANSIStyle())])
        #expect(ANSIParser.parse("").isEmpty)
    }

    @Test func colorsAndReset() {
        #expect(ANSIParser.parse("\u{1B}[32mINFO\u{1B}[0m: ok") == [
            ANSISpan(text: "INFO", style: ANSIStyle(foreground: .standard(2))),
            ANSISpan(text: ": ok", style: ANSIStyle()),
        ])
        #expect(ANSIParser.parse("\u{1B}[1;91mERR") == [
            ANSISpan(text: "ERR", style: ANSIStyle(foreground: .bright(1), bold: true)),
        ])
    }

    @Test func extendedColorsAndIgnoredBackground() {
        #expect(ANSIParser.parse("\u{1B}[38;5;208mX\u{1B}[38;2;1;2;3mY\u{1B}[48;5;1;39mZ") == [
            ANSISpan(text: "X", style: ANSIStyle(foreground: .palette(208))),
            ANSISpan(text: "Y", style: ANSIStyle(foreground: .rgb(1, 2, 3))),
            ANSISpan(text: "Z", style: ANSIStyle()),
        ])
    }

    @Test func stripsOtherEscapeSequences() {
        #expect(ANSIParser.strip("\u{1B}[2Kline\u{1B}[1A") == "line")
        #expect(ANSIParser.strip("\u{1B}]8;;http://x\u{07}link\u{1B}]8;;\u{1B}\\ done") == "link done")
        #expect(ANSIParser.strip("a\rb\u{07}c\td") == "abc\td")
    }
}

@MainActor @Suite struct LogBufferTests {
    @Test func trimsToCapacityInBatches() {
        let buffer = LogBuffer(capacity: 10)
        buffer.append(.stdout, (0..<11).map(String.init))
        #expect(buffer.lines.count == 11)
        buffer.append(.stderr, ["11"])
        #expect(buffer.lines.count == 10)
        #expect(buffer.lines.first?.id == 2)
        #expect(buffer.lines.last?.text == "11")
        #expect(buffer.lines.last?.kind == .stderr)
        buffer.clear()
        #expect(buffer.lines.isEmpty)
        buffer.append(.system, ["x"])
        #expect(buffer.lines.first?.id == 12)
    }
}

@Suite struct LogFileWriterTests {
    @Test func writesAndRotates() throws {
        let dir = try makeTempDirectory()
        let url = dir.appendingPathComponent("svc.log")
        let writer = LogFileWriter(url: url, maxBytes: 20)
        writer.write(["0123456789"])
        writer.flush()
        #expect(try String(contentsOf: url, encoding: .utf8) == "0123456789\n")
        writer.write(["abcdefghij"])
        writer.flush()
        #expect(try String(contentsOf: url, encoding: .utf8) == "abcdefghij\n")
        #expect(try String(contentsOf: URL(fileURLWithPath: url.path + ".1"), encoding: .utf8) == "0123456789\n")
    }

    @Test func serviceLogFileNames() {
        let dir = URL(fileURLWithPath: "/logs")
        #expect(LogFileWriter.url(forService: "docs-api/api-uvicorn-debug", directory: dir).path == "/logs/docs-api-api-uvicorn-debug.log")
    }
}
```

- [ ] **Step 2: Testin fail ettiğini doğrula**

Run: `make test FILTER=ANSIParserTests`
Expected: Derleme hatası, `cannot find 'ANSIParser' in scope`.

- [ ] **Step 3: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Logs/ANSIParser.swift
import Foundation

public enum ANSIColor: Equatable, Sendable {
    case standard(Int)
    case bright(Int)
    case palette(Int)
    case rgb(Int, Int, Int)
}

public struct ANSIStyle: Equatable, Sendable {
    public var foreground: ANSIColor?
    public var bold: Bool
    public var dim: Bool

    public init(foreground: ANSIColor? = nil, bold: Bool = false, dim: Bool = false) {
        self.foreground = foreground
        self.bold = bold
        self.dim = dim
    }
}

public struct ANSISpan: Equatable, Sendable {
    public var text: String
    public var style: ANSIStyle

    public init(text: String, style: ANSIStyle) {
        self.text = text
        self.style = style
    }
}

/// Interprets SGR color/bold codes in one log line and drops every other escape sequence.
public enum ANSIParser {
    public static func parse(_ line: String) -> [ANSISpan] {
        let scalars = Array(line.unicodeScalars)
        var spans: [ANSISpan] = []
        var style = ANSIStyle()
        var text = String.UnicodeScalarView()

        func flush() {
            if !text.isEmpty {
                spans.append(ANSISpan(text: String(text), style: style))
                text = String.UnicodeScalarView()
            }
        }

        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if scalar == "\u{1B}", i + 1 < scalars.count {
                let next = scalars[i + 1]
                if next == "[" {
                    var j = i + 2
                    var params = ""
                    while j < scalars.count, !(0x40...0x7E).contains(scalars[j].value) {
                        params.unicodeScalars.append(scalars[j])
                        j += 1
                    }
                    if j < scalars.count, scalars[j] == "m" {
                        flush()
                        apply(params, to: &style)
                    }
                    i = j + 1
                    continue
                }
                if next == "]" {
                    var j = i + 2
                    while j < scalars.count {
                        if scalars[j] == "\u{07}" { j += 1; break }
                        if scalars[j] == "\u{1B}", j + 1 < scalars.count, scalars[j + 1] == "\\" { j += 2; break }
                        j += 1
                    }
                    i = j
                    continue
                }
                i += 2
                continue
            }
            if scalar.value < 0x20 && scalar != "\t" {
                i += 1
                continue
            }
            text.append(scalar)
            i += 1
        }
        flush()
        return spans
    }

    public static func strip(_ line: String) -> String {
        parse(line).map(\.text).joined()
    }

    static func apply(_ params: String, to style: inout ANSIStyle) {
        let codes = params.isEmpty
            ? [0]
            : params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var k = 0
        while k < codes.count {
            let code = codes[k]
            switch code {
            case 0: style = ANSIStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 22:
                style.bold = false
                style.dim = false
            case 30...37: style.foreground = .standard(code - 30)
            case 39: style.foreground = nil
            case 90...97: style.foreground = .bright(code - 90)
            case 38, 48:
                if k + 2 < codes.count, codes[k + 1] == 5 {
                    if code == 38 { style.foreground = .palette(codes[k + 2]) }
                    k += 2
                } else if k + 4 < codes.count, codes[k + 1] == 2 {
                    if code == 38 { style.foreground = .rgb(codes[k + 2], codes[k + 3], codes[k + 4]) }
                    k += 4
                }
            default:
                break
            }
            k += 1
        }
    }
}
```

```swift
// File: Sources/DevLauncherCore/Logs/LogBuffer.swift
import Foundation
import Observation

public struct LogLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let kind: OutputKind
    public let text: String
    public let date: Date
}

/// In-memory tail of a service's output. Trims in batches so appends stay cheap.
@MainActor @Observable
public final class LogBuffer {
    public let capacity: Int
    public private(set) var lines: [LogLine] = []
    @ObservationIgnored private var nextID = 0

    public init(capacity: Int = 5_000) {
        self.capacity = capacity
    }

    public func append(_ kind: OutputKind, _ texts: [String], date: Date = Date()) {
        guard !texts.isEmpty else { return }
        var batch: [LogLine] = []
        batch.reserveCapacity(texts.count)
        for text in texts {
            batch.append(LogLine(id: nextID, kind: kind, text: text, date: date))
            nextID += 1
        }
        lines.append(contentsOf: batch)
        let slack = max(capacity / 10, 1)
        if lines.count > capacity + slack {
            lines.removeFirst(lines.count - capacity)
        }
    }

    public func clear() {
        lines.removeAll()
    }
}
```

```swift
// File: Sources/DevLauncherCore/Logs/LogFileWriter.swift
import Foundation

/// Appends raw log lines to a file on a background queue, rotating to `<file>.1` past `maxBytes`.
public final class LogFileWriter: @unchecked Sendable {
    public let url: URL
    public let maxBytes: Int
    private let queue = DispatchQueue(label: "devlauncher.logfile")
    private var handle: FileHandle?
    private var size = 0

    public init(url: URL, maxBytes: Int = 10 * 1024 * 1024) {
        self.url = url
        self.maxBytes = maxBytes
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DevLauncher")
    }

    public static func url(forService id: String, directory: URL = defaultDirectory) -> URL {
        directory.appendingPathComponent("\(Slug.make(id)).log")
    }

    public func write(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        let data = Data(lines.map { $0 + "\n" }.joined().utf8)
        queue.async { [self] in self.append(data) }
    }

    /// Blocks until queued writes are on disk.
    public func flush() {
        queue.sync {}
    }

    private func append(_ data: Data) {
        if handle == nil { open() }
        if size > 0, size + data.count > maxBytes { rotate() }
        try? handle?.write(contentsOf: data)
        size += data.count
    }

    private func open() {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let rotated = URL(fileURLWithPath: url.path + ".1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
        open()
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `make test FILTER=ANSIParserTests`, `make test FILTER=LogBufferTests`, `make test FILTER=LogFileWriterTests`
Expected: Hepsi `passed`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: ANSI log parsing, in-memory log buffer and rotating log files"
```

---

### Task 10: LaunchPlanner + RuntimeStateStore

**Files:**
- Create: `Sources/DevLauncherCore/Runtime/LaunchPlanner.swift`, `Sources/DevLauncherCore/Runtime/RuntimeStateStore.swift`
- Test: `Tests/DevLauncherCoreTests/LaunchPlannerTests.swift`, `Tests/DevLauncherCoreTests/RuntimeStateStoreTests.swift`

**Interfaces:**
- Consumes: `ServiceDefinition.launchCommand`, `EnvResolver`, `ProcessRunner.resolveExecutable`, `ProcessRunnerError`, `SpawnRequest`, `PackageManager`, `ProcessInspector.startTime`.
- Produces:
  - `SetupRequirement { pythonEnvironment(project:), packageInstall(PackageManager, directory:), missingExecutable(String) }` with `message`, `fixTitle`, `fix: (command: [String], directory: String)?`
  - `LaunchPlan(request:warnings:)`
  - `LaunchPlanner.setupRequirement(for:searchPath:fileExists:) -> SetupRequirement?`
  - `LaunchPlanner.plan(_:shell:readFile:) throws -> LaunchPlan`
  - `LaunchPlanner.setupRequest(_:shell:) throws -> SpawnRequest?`
  - `RuntimeRecord(serviceID:pid:pgid:startTime:)`, `RuntimeStateStore(directory:)` with `load()`/`save(_:)`, `RuntimeStateStore.liveOrphans(_:startTime:)`

- [ ] **Step 1: Failing testleri yaz**

```swift
// File: Tests/DevLauncherCoreTests/LaunchPlannerTests.swift
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct LaunchPlannerTests {
    let python = ServiceDefinition(
        name: "api", command: ["/repo/.venv/bin/python", "-m", "uvicorn", "a:app"], cwd: "/repo/src",
        supportsReload: true, reloadEnabled: true, reloadArgs: ["--reload"]
    )

    @Test func detectsMissingVirtualEnvironment() {
        let requirement = LaunchPlanner.setupRequirement(for: python, searchPath: "/bin") { _ in false }
        #expect(requirement == .pythonEnvironment(project: "/repo"))
        #expect(requirement?.fix?.command == ["uv", "sync"])
        #expect(requirement?.fix?.directory == "/repo")
        #expect(LaunchPlanner.setupRequirement(for: python, searchPath: "/bin") { _ in true } == nil)
    }

    @Test func detectsMissingNodeModulesAndPackageManager() throws {
        let bin = try makeFakeExecutable("npm")
        let web = ServiceDefinition(name: "dev", command: ["npm", "run", "dev"], cwd: "/web")
        let requirement = LaunchPlanner.setupRequirement(for: web, searchPath: bin.path) { _ in false }
        #expect(requirement == .packageInstall(.npm, directory: "/web"))
        #expect(requirement?.fix?.command == ["npm", "install"])
        #expect(LaunchPlanner.setupRequirement(for: web, searchPath: bin.path) { $0 == "/web/node_modules" } == nil)
        #expect(LaunchPlanner.setupRequirement(for: web, searchPath: "/nonexistent") { _ in true } == .missingExecutable("npm"))
    }

    @Test func otherMissingAbsoluteExecutable() {
        let tool = ServiceDefinition(name: "x", command: ["/opt/tool/bin/run"], cwd: "/")
        let requirement = LaunchPlanner.setupRequirement(for: tool, searchPath: nil) { _ in false }
        #expect(requirement == .missingExecutable("/opt/tool/bin/run"))
        #expect(requirement?.fix == nil)
    }

    @Test func planResolvesCommandEnvAndReload() throws {
        let definition = ServiceDefinition(
            name: "echo", command: ["sh", "-c", "echo hi"], cwd: "/tmp", envFile: "/tmp/none.env",
            env: ["X": "1"], supportsReload: true, reloadEnabled: true, reloadArgs: ["--reload"]
        )
        let plan = try LaunchPlanner.plan(definition, shell: ["PATH": "/bin"]) { _ in nil }
        #expect(plan.request.executable == "/bin/sh")
        #expect(plan.request.arguments == ["-c", "echo hi", "--reload"])
        #expect(plan.request.cwd == "/tmp")
        #expect(plan.request.environment["X"] == "1")
        #expect(plan.request.environment["PYTHONUNBUFFERED"] == "1")
        #expect(plan.warnings == ["Env dosyası bulunamadı: /tmp/none.env"])
    }

    @Test func planFailsForUnknownExecutable() {
        let definition = ServiceDefinition(name: "x", command: ["no-such-tool-xyz"], cwd: "/tmp")
        #expect(throws: ProcessRunnerError.executableNotFound("no-such-tool-xyz")) {
            try LaunchPlanner.plan(definition, shell: ["PATH": "/bin"])
        }
    }

    @Test func setupRequestRunsFixInItsDirectory() throws {
        let bin = try makeFakeExecutable("uv")
        let request = try LaunchPlanner.setupRequest(.pythonEnvironment(project: "/repo"), shell: ["PATH": bin.path])
        #expect(request?.executable == bin.appendingPathComponent("uv").path)
        #expect(request?.arguments == ["sync"])
        #expect(request?.cwd == "/repo")
        #expect(request?.environment["FORCE_COLOR"] == "1")
        #expect(try LaunchPlanner.setupRequest(.missingExecutable("x"), shell: [:]) == nil)
    }
}
```

```swift
// File: Tests/DevLauncherCoreTests/RuntimeStateStoreTests.swift
import Darwin
import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct RuntimeStateStoreTests {
    @Test func roundTrip() throws {
        let store = RuntimeStateStore(directory: try makeTempDirectory())
        #expect(store.load().isEmpty)
        let records = [RuntimeRecord(serviceID: "a/b", pid: 10, pgid: 10, startTime: 5)]
        store.save(records)
        #expect(store.load() == records)
    }

    @Test func liveOrphansRequireMatchingStartTime() {
        let records = [
            RuntimeRecord(serviceID: "a", pid: 1, pgid: 1, startTime: 100),
            RuntimeRecord(serviceID: "b", pid: 2, pgid: 2, startTime: 200),
            RuntimeRecord(serviceID: "c", pid: 3, pgid: 3, startTime: 300),
        ]
        let table: [pid_t: UInt64] = [1: 100, 2: 999]
        #expect(RuntimeStateStore.liveOrphans(records) { table[$0] }.map(\.serviceID) == ["a"])
    }

    @Test func currentProcessCountsAsLive() throws {
        let me = getpid()
        let start = try #require(ProcessInspector.startTime(of: me))
        let record = RuntimeRecord(serviceID: "me", pid: me, pgid: me, startTime: start)
        #expect(RuntimeStateStore.liveOrphans([record]) == [record])
    }
}
```

- [ ] **Step 2: Testin fail ettiğini doğrula**

Run: `make test FILTER=LaunchPlannerTests`
Expected: Derleme hatası, `cannot find 'LaunchPlanner' in scope`.

- [ ] **Step 3: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Runtime/LaunchPlanner.swift
import Foundation

/// Something that must be fixed before a service can start.
public enum SetupRequirement: Equatable, Sendable {
    case pythonEnvironment(project: String)
    case packageInstall(PackageManager, directory: String)
    case missingExecutable(String)

    public var message: String {
        switch self {
        case .pythonEnvironment(let project):
            return "Python sanal ortamı (.venv) bulunamadı: \(project)"
        case .packageInstall(let manager, _):
            return "node_modules yok; önce \(manager.rawValue) install gerekli."
        case .missingExecutable(let name):
            return "Çalıştırılabilir dosya bulunamadı: \(name)"
        }
    }

    public var fixTitle: String {
        guard let fix else { return "" }
        return "\(fix.command.joined(separator: " ")) çalıştır"
    }

    public var fix: (command: [String], directory: String)? {
        switch self {
        case .pythonEnvironment(let project): return (["uv", "sync"], project)
        case .packageInstall(let manager, let directory): return ([manager.rawValue, "install"], directory)
        case .missingExecutable: return nil
        }
    }
}

public struct LaunchPlan: Equatable, Sendable {
    public var request: SpawnRequest
    public var warnings: [String]

    public init(request: SpawnRequest, warnings: [String]) {
        self.request = request
        self.warnings = warnings
    }
}

public enum LaunchPlanner {
    static let venvSuffixes = ["/.venv/bin/python", "/.venv/bin/python3"]

    public static func setupRequirement(
        for definition: ServiceDefinition,
        searchPath: String?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> SetupRequirement? {
        guard let executable = definition.command.first else { return .missingExecutable("") }
        if executable.contains("/") {
            guard !fileExists(executable) else { return nil }
            if let suffix = venvSuffixes.first(where: { executable.hasSuffix($0) }) {
                return .pythonEnvironment(project: String(executable.dropLast(suffix.count)))
            }
            return .missingExecutable(executable)
        }
        guard ProcessRunner.resolveExecutable(executable, searchPath: searchPath) != nil else {
            return .missingExecutable(executable)
        }
        if let manager = PackageManager(rawValue: executable),
           !fileExists(URL(fileURLWithPath: definition.cwd).appendingPathComponent("node_modules").path) {
            return .packageInstall(manager, directory: definition.cwd)
        }
        return nil
    }

    public static func plan(
        _ definition: ServiceDefinition,
        shell: [String: String],
        readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) throws -> LaunchPlan {
        let command = definition.launchCommand
        guard let executable = command.first else { throw ProcessRunnerError.executableNotFound("") }
        let env = EnvResolver.resolve(shell: shell, definition: definition, readFile: readFile)
        guard let resolved = ProcessRunner.resolveExecutable(executable, searchPath: env.environment["PATH"]) else {
            throw ProcessRunnerError.executableNotFound(executable)
        }
        let request = SpawnRequest(
            executable: resolved,
            arguments: Array(command.dropFirst()),
            environment: env.environment,
            cwd: definition.cwd
        )
        return LaunchPlan(request: request, warnings: env.warnings)
    }

    public static func setupRequest(_ requirement: SetupRequirement, shell: [String: String]) throws -> SpawnRequest? {
        guard let fix = requirement.fix, let name = fix.command.first else { return nil }
        guard let executable = ProcessRunner.resolveExecutable(name, searchPath: shell["PATH"]) else {
            throw ProcessRunnerError.executableNotFound(name)
        }
        var environment = shell
        environment.merge(EnvResolver.constants) { _, new in new }
        return SpawnRequest(
            executable: executable,
            arguments: Array(fix.command.dropFirst()),
            environment: environment,
            cwd: fix.directory
        )
    }
}
```

```swift
// File: Sources/DevLauncherCore/Runtime/RuntimeStateStore.swift
import Foundation

/// A running service as remembered in state.json, so orphans can be found after a crash.
public struct RuntimeRecord: Codable, Equatable, Sendable {
    public var serviceID: String
    public var pid: Int32
    public var pgid: Int32
    /// Microseconds since 1970; guards against pid reuse.
    public var startTime: UInt64

    public init(serviceID: String, pid: Int32, pgid: Int32, startTime: UInt64) {
        self.serviceID = serviceID
        self.pid = pid
        self.pgid = pgid
        self.startTime = startTime
    }
}

public final class RuntimeStateStore {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("state.json")
    }

    public func load() -> [RuntimeRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([RuntimeRecord].self, from: data)) ?? []
    }

    public func save(_ records: [RuntimeRecord]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
    }

    /// Records whose process still exists and is the same process (start time matches).
    public static func liveOrphans(
        _ records: [RuntimeRecord],
        startTime: (pid_t) -> UInt64? = { ProcessInspector.startTime(of: $0) }
    ) -> [RuntimeRecord] {
        records.filter { startTime($0.pid) == $0.startTime }
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `make test FILTER=LaunchPlannerTests` ve `make test FILTER=RuntimeStateStoreTests`
Expected: `6 + 3 tests passed`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: launch planning, setup checks and runtime state"
```

---

### Task 11: ServiceSupervisor

**Files:**
- Create: `Sources/DevLauncherCore/Runtime/ServiceSupervisor.swift`
- Test: `Tests/DevLauncherCoreTests/ServiceSupervisorTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner.spawn/terminateGroup`, `SpawnedProcess`, `LaunchPlan`, `LogBuffer`, `LogFileWriter`, `ListeningSocket`, `PortProbe.ports(forGroup:in:)`, `RuntimeRecord`, `ProcessInspector.isAlive`, `ShellWords.join`.
- Produces:
  - `ServiceStatus { stopped, starting, running(ports: [Int]), stopping, crashed(ExitStatus) }` + `isActive`, `isCrashed`
  - `@MainActor @Observable ServiceSupervisor(id:logs:fileLog:now:)` with properties `status`, `pgid`, `isAdopted`, `isRunningSetup`, `startedAt`, `runtimeRecord`, `onStatusChange`
  - Methods: `start(_ plan: LaunchPlan, expectsPort: Bool) throws`, `stop(grace:) async`, `adopt(_:)`, `refresh(with:isAlive:)`, `runSetup(_:) throws`, `appendSystem(_:)`
  - `ServiceSupervisor.noPortGracePeriod = 3`

- [ ] **Step 1: Failing testi yaz**

```swift
// File: Tests/DevLauncherCoreTests/ServiceSupervisorTests.swift
import Darwin
import Foundation
import Testing
@testable import DevLauncherCore

@MainActor @Suite(.serialized) struct ServiceSupervisorTests {
    func plan(_ script: String) -> LaunchPlan {
        LaunchPlan(
            request: SpawnRequest(executable: "/bin/sh", arguments: ["-c", script], environment: ["PATH": "/usr/bin:/bin"], cwd: "/tmp"),
            warnings: ["örnek uyarı"]
        )
    }

    @Test func crashIsDetectedWithExitCode() async throws {
        let s = ServiceSupervisor(id: "t/crash")
        try s.start(plan("echo boom; exit 4"), expectsPort: false)
        #expect(s.status == .starting)
        #expect(await waitUntil { s.status == .crashed(.exited(4)) })
        #expect(s.logs.lines.contains { $0.text == "boom" && $0.kind == .stdout })
        #expect(s.logs.lines.contains { $0.kind == .system && $0.text.contains("örnek uyarı") })
        #expect(s.runtimeRecord == nil)
        #expect(s.pgid == nil)
        #expect(s.status.isCrashed)
    }

    @Test func stopTransitionsToStopped() async throws {
        let s = ServiceSupervisor(id: "t/stop")
        var seen: [ServiceStatus] = []
        s.onStatusChange = { seen.append($0.status) }
        try s.start(plan("sleep 100"), expectsPort: false)
        let record = try #require(s.runtimeRecord)
        #expect(record.pgid == s.pgid)
        await s.stop(grace: 2)
        #expect(await waitUntil { s.status == .stopped })
        #expect(seen == [.starting, .stopping, .stopped])
        #expect(!ProcessInspector.isGroupAlive(record.pgid))
    }

    @Test func secondStartWhileRunningIsIgnored() async throws {
        let s = ServiceSupervisor(id: "t/double")
        try s.start(plan("sleep 100"), expectsPort: false)
        let first = s.pgid
        try s.start(plan("sleep 100"), expectsPort: false)
        #expect(s.pgid == first)
        await s.stop(grace: 2)
        #expect(await waitUntil { s.status == .stopped })
    }

    @Test func workerWithoutPortBecomesRunningAfterGracePeriod() async throws {
        var clock = Date()
        let s = ServiceSupervisor(id: "t/worker", now: { clock })
        try s.start(plan("sleep 100"), expectsPort: false)
        s.refresh(with: [])
        #expect(s.status == .starting)
        clock = clock.addingTimeInterval(3.1)
        s.refresh(with: [])
        #expect(s.status == .running(ports: []))
        await s.stop(grace: 2)
    }

    @Test func serverStaysStartingUntilPortAppears() async throws {
        var clock = Date()
        let s = ServiceSupervisor(id: "t/server", now: { clock })
        try s.start(plan("sleep 100"), expectsPort: true)
        let pgid = try #require(s.pgid)
        clock = clock.addingTimeInterval(10)
        s.refresh(with: [])
        #expect(s.status == .starting)
        s.refresh(with: [ListeningSocket(pid: pgid, pgid: pgid, command: "python", port: 8010)])
        #expect(s.status == .running(ports: [8010]))
        s.refresh(with: [ListeningSocket(pid: pgid + 1, pgid: pgid, command: "python", port: 8011)])
        #expect(s.status == .running(ports: [8011]))
        await s.stop(grace: 2)
    }

    @Test func adoptedProcessCanBeStopped() async throws {
        let process = try ProcessRunner.spawn(plan("sleep 100").request, onLines: { _, _ in }, onExit: { _ in })
        let s = ServiceSupervisor(id: "t/adopt")
        s.adopt(RuntimeRecord(serviceID: "t/adopt", pid: process.pid, pgid: process.pgid, startTime: process.startTime))
        #expect(s.status == .running(ports: []))
        #expect(s.isAdopted)
        await s.stop(grace: 2)
        #expect(s.status == .stopped)
        #expect(!s.isAdopted)
        #expect(await waitUntil { !ProcessInspector.isGroupAlive(process.pgid) })
    }

    @Test func adoptedProcessExitIsNoticedOnRefresh() {
        let s = ServiceSupervisor(id: "t/adopt2")
        s.adopt(RuntimeRecord(serviceID: "t/adopt2", pid: 99_998, pgid: 99_998, startTime: 1))
        s.refresh(with: [], isAlive: { _ in false })
        #expect(s.status == .stopped)
        #expect(s.runtimeRecord == nil)
    }

    @Test func spawnFailureIsReportedAsCrash() {
        let s = ServiceSupervisor(id: "t/fail")
        var bad = plan("true")
        bad.request.cwd = "/nope/dir"
        #expect(throws: ProcessRunnerError.directoryNotFound("/nope/dir")) { try s.start(bad, expectsPort: false) }
        #expect(s.status == .crashed(.exited(127)))
        #expect(s.logs.lines.contains { $0.kind == .system && $0.text.contains("/nope/dir") })
    }

    @Test func runSetupLogsResult() async throws {
        let s = ServiceSupervisor(id: "t/setup")
        try s.runSetup(plan("echo installing").request)
        #expect(s.isRunningSetup)
        #expect(await waitUntil { !s.isRunningSetup })
        #expect(s.logs.lines.contains { $0.text == "installing" })
        #expect(s.logs.lines.contains { $0.text.contains("kurulum tamamlandı") })
        #expect(s.status == .stopped)
    }
}
```

- [ ] **Step 2: Testin fail ettiğini doğrula**

Run: `make test FILTER=ServiceSupervisorTests`
Expected: Derleme hatası, `cannot find 'ServiceSupervisor' in scope`.

- [ ] **Step 3: Implementasyonu yaz**

```swift
// File: Sources/DevLauncherCore/Runtime/ServiceSupervisor.swift
import Foundation
import Observation

public enum ServiceStatus: Equatable, Sendable {
    case stopped
    case starting
    case running(ports: [Int])
    case stopping
    case crashed(ExitStatus)

    public var isActive: Bool {
        switch self {
        case .starting, .running, .stopping: return true
        case .stopped, .crashed: return false
        }
    }

    public var isCrashed: Bool {
        if case .crashed = self { return true }
        return false
    }
}

/// Owns one service's process: start, stop, port-based readiness, crash detection and logs.
@MainActor @Observable
public final class ServiceSupervisor {
    public static let noPortGracePeriod: TimeInterval = 3

    public let id: String
    public let logs: LogBuffer
    public private(set) var status: ServiceStatus = .stopped
    public private(set) var pgid: pid_t?
    public private(set) var isAdopted = false
    public private(set) var isRunningSetup = false
    public private(set) var startedAt: Date?

    @ObservationIgnored public var onStatusChange: ((ServiceSupervisor) -> Void)?
    @ObservationIgnored private let fileLog: LogFileWriter?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var process: SpawnedProcess?
    @ObservationIgnored private var setupProcess: SpawnedProcess?
    @ObservationIgnored private var record: RuntimeRecord?
    @ObservationIgnored private var expectsPort = false
    @ObservationIgnored private var generation = 0

    public init(id: String, logs: LogBuffer? = nil, fileLog: LogFileWriter? = nil, now: @escaping () -> Date = { Date() }) {
        self.id = id
        self.logs = logs ?? LogBuffer()
        self.fileLog = fileLog
        self.now = now
    }

    public var runtimeRecord: RuntimeRecord? { record }

    public func start(_ plan: LaunchPlan, expectsPort: Bool) throws {
        guard !status.isActive else { return }
        generation += 1
        let current = generation
        self.expectsPort = expectsPort
        appendSystem(
            ["──── başlatılıyor · \(Self.timestamp(now())) ────",
             "$ " + ShellWords.join([plan.request.executable] + plan.request.arguments),
             "cwd: \(plan.request.cwd)"]
                + plan.warnings.map { "⚠️ \($0)" }
        )
        do {
            let spawned = try ProcessRunner.spawn(
                plan.request,
                onLines: { [weak self] kind, lines in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(kind, lines) } }
                },
                onExit: { [weak self] exit in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.processExited(exit, generation: current) } }
                }
            )
            process = spawned
            pgid = spawned.pgid
            isAdopted = false
            startedAt = now()
            record = RuntimeRecord(serviceID: id, pid: spawned.pid, pgid: spawned.pgid, startTime: spawned.startTime)
            setStatus(.starting)
        } catch {
            appendSystem(["❌ başlatılamadı: \(error)"])
            setStatus(.crashed(.exited(127)))
            throw error
        }
    }

    public func stop(grace: TimeInterval = 5) async {
        guard let group = pgid, status.isActive, status != .stopping else { return }
        setStatus(.stopping)
        appendSystem(["──── durduruluyor (SIGTERM) ────"])
        let killed = await ProcessRunner.terminateGroup(group, grace: grace)
        if killed { appendSystem(["⚠️ \(Int(grace)) sn içinde kapanmadı, SIGKILL gönderildi"]) }
        if isAdopted, status == .stopping {
            clearProcessState()
            appendSystem(["──── durduruldu ────"])
            setStatus(.stopped)
        }
    }

    /// Tracks a process left over from a previous app session. Its output cannot be recovered.
    public func adopt(_ record: RuntimeRecord) {
        guard !status.isActive else { return }
        generation += 1
        self.record = record
        pgid = record.pgid
        isAdopted = true
        expectsPort = false
        startedAt = now()
        appendSystem(["──── önceki oturumdan sahiplenildi (pid \(record.pid)); loglar bu oturumda görüntülenemez ────"])
        setStatus(.running(ports: []))
    }

    /// Updates readiness and ports from a port snapshot; also notices when an adopted process exits.
    public func refresh(with snapshot: [ListeningSocket], isAlive: (pid_t) -> Bool = { ProcessInspector.isAlive($0) }) {
        guard let group = pgid else { return }
        if isAdopted, let record, !isAlive(record.pid) {
            clearProcessState()
            appendSystem(["──── sahiplenilen süreç sonlandı ────"])
            setStatus(.stopped)
            return
        }
        let ports = PortProbe.ports(forGroup: group, in: snapshot)
        switch status {
        case .starting:
            if !ports.isEmpty {
                setStatus(.running(ports: ports))
            } else if !expectsPort, let startedAt, now().timeIntervalSince(startedAt) >= Self.noPortGracePeriod {
                setStatus(.running(ports: []))
            }
        case .running(let current) where current != ports:
            setStatus(.running(ports: ports))
        default:
            break
        }
    }

    /// Runs a one-off setup command (e.g. `uv sync`) whose output goes to this service's log.
    public func runSetup(_ request: SpawnRequest) throws {
        guard !isRunningSetup else { return }
        appendSystem(["──── kurulum: " + ShellWords.join([request.executable] + request.arguments) + " ────"])
        setupProcess = try ProcessRunner.spawn(
            request,
            onLines: { [weak self] kind, lines in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(kind, lines) } }
            },
            onExit: { [weak self] exit in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.setupFinished(exit) } }
            }
        )
        isRunningSetup = true
    }

    public func appendSystem(_ lines: [String]) {
        logs.append(.system, lines)
        fileLog?.write(lines)
    }

    private func receive(_ kind: OutputKind, _ lines: [String]) {
        logs.append(kind, lines)
        fileLog?.write(lines)
    }

    private func processExited(_ exit: ExitStatus, generation exited: Int) {
        guard exited == generation else { return }
        let group = pgid
        let wasStopping = status == .stopping
        clearProcessState()
        if wasStopping {
            appendSystem(["──── durduruldu ────"])
            setStatus(.stopped)
        } else {
            appendSystem(["💥 beklenmedik şekilde sonlandı (\(exit))"])
            setStatus(.crashed(exit))
            if let group {
                Task.detached { await ProcessRunner.terminateGroup(group, grace: 2) }
            }
        }
    }

    private func setupFinished(_ exit: ExitStatus) {
        isRunningSetup = false
        setupProcess = nil
        appendSystem([exit == .exited(0) ? "✅ kurulum tamamlandı" : "❌ kurulum başarısız (\(exit))"])
        onStatusChange?(self)
    }

    private func clearProcessState() {
        process = nil
        record = nil
        pgid = nil
        isAdopted = false
    }

    private func setStatus(_ newStatus: ServiceStatus) {
        guard newStatus != status else { return }
        status = newStatus
        onStatusChange?(self)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `make test FILTER=ServiceSupervisorTests`
Expected: `9 tests passed`.

- [ ] **Step 5: Tüm Core testlerini çalıştır**

Run: `make test`
Expected: Tüm suite'ler `passed`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: service supervisor state machine"
```

---
### Task 12: AppModel, Alerts, SystemIntegration

UI katmanı otomatik test edilmez. Bu task'ın kabul kriteri `make build`'in uyarı vermeden derlemesidir; Task 15'te manuel kontrol listesi var.

**Files:**
- Create: `Sources/DevLauncher/AppModel.swift`, `Sources/DevLauncher/Alerts.swift`, `Sources/DevLauncher/SystemIntegration.swift`

**Interfaces:**
- Consumes: Core'daki tüm public API.
- Produces:
  - `@MainActor @Observable AppModel`
  - State: `config`, `shell`, `supervisors`, `discoveries`, `suggestions`, `unmatched`, `newRepoCandidates`, `isScanning`, `selection`, `integration`
  - Lifecycle: `bootstrap()`, `reloadShell()`, `rescan()`
  - Lookups: `service(_:)`, `displayName(_:)`, `repoName(of:)`, `status(_:)`, `activeCount`, `hasCrash`, `pinnedIDs`, `isPinned(_:)`, `setupRequirement(_:)`
  - Service actions: `start(_:force:)`, `stop(_:)`, `restart(_:)`, `stopAll()`, `runSetup(_:)`
  - Config edits: `togglePin(_:)`, `movePinned(from:to:)`, `updateOverrides(_:_:)`, `removeService(_:)`
  - Repo edits: `discover(_:)`, `addRepo(_:services:)`, `ignoreRepos(_:)`, `removeRepo(_:)`, `acceptSuggestions(_:selected:)`, `addManualService(_:definition:)`
  - Settings: `addRoot(_:)`, `removeRoot(_:)`, `setCrashNotifications(_:)`, `setLaunchAtLogin(_:)`
  - `Alerts.info(_:_:)`, `Alerts.confirm(_:_:confirm:cancel:) -> Bool`
  - `SystemIntegration`: `requestNotificationPermission()`, `notifyCrash(service:detail:)`, `launchAtLoginEnabled`, `setLaunchAtLogin(_:) throws`, `openBrowser(port:)`, `reveal(_:)`

- [ ] **Step 1: Alerts ve SystemIntegration'ı yaz**

```swift
// File: Sources/DevLauncher/Alerts.swift
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
```

```swift
// File: Sources/DevLauncher/SystemIntegration.swift
import AppKit
import ServiceManagement
import UserNotifications

/// macOS services that only work inside the signed .app bundle; no-ops (or errors) under `swift run`.
@MainActor
final class SystemIntegration {
    enum IntegrationError: LocalizedError {
        case notBundled

        var errorDescription: String? {
            "Bu özellik yalnızca DevLauncher.app olarak çalışırken kullanılabilir (make install)."
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
```

- [ ] **Step 2: AppModel'i yaz**

```swift
// File: Sources/DevLauncher/AppModel.swift
import AppKit
import DevLauncherCore
import Observation
import SwiftUI

/// App-wide state: configuration, one supervisor per service, discovery results and port polling.
@MainActor @Observable
final class AppModel {
    private(set) var config: AppConfig
    private(set) var shell: ShellEnvironment?
    private(set) var supervisors: [String: ServiceSupervisor] = [:]
    private(set) var discoveries: [String: RepoDiscovery] = [:]
    private(set) var suggestions: [String: [DiscoveredService]] = [:]
    private(set) var unmatched: [String: [DiscoveredService]] = [:]
    private(set) var newRepoCandidates: [URL] = []
    private(set) var isScanning = false
    var selection: String?

    @ObservationIgnored let integration = SystemIntegration()
    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let runtimeStore: RuntimeStateStore
    @ObservationIgnored private var configWarning: String?
    @ObservationIgnored private var pendingOrphans: [RuntimeRecord] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastSlowPoll = Date.distantPast
    @ObservationIgnored private var didBootstrap = false

    init(directory: URL = ConfigStore.defaultDirectory) {
        configStore = ConfigStore(directory: directory)
        runtimeStore = RuntimeStateStore(directory: directory)
        let loaded = configStore.load()
        config = loaded.config
        configWarning = loaded.warning
        ensureSupervisors()
    }

    // MARK: Lifecycle

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        if let configWarning { Alerts.info("Ayarlar sıfırlandı", configWarning) }
        await reloadShell()
        await rescan()
        let orphans = RuntimeStateStore.liveOrphans(runtimeStore.load())
            .filter { supervisors[$0.serviceID] != nil }
        if !orphans.isEmpty {
            pendingOrphans = orphans
            let names = orphans.map { displayName($0.serviceID) }.joined(separator: ", ")
            let adopt = Alerts.confirm(
                "\(orphans.count) servis önceki oturumdan çalışıyor",
                "\(names)\n\nSahiplenirsen durumlarını izleyip durdurabilirsin, ancak loglarını göremezsin.",
                confirm: "Sahiplen",
                cancel: "Durdur"
            )
            resolveOrphans(adopt: adopt)
        }
        startPolling()
    }

    func reloadShell() async {
        shell = await Task.detached { ShellEnvironment.capture() }.value
    }

    private func resolveOrphans(adopt: Bool) {
        let records = pendingOrphans
        pendingOrphans = []
        for record in records {
            if adopt {
                supervisors[record.serviceID]?.adopt(record)
            } else {
                let pgid = record.pgid
                Task.detached { await ProcessRunner.terminateGroup(pgid) }
            }
        }
        persistRuntimeState()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.pollPorts()
            }
        }
    }

    /// Every 2 s while something is starting, otherwise every 10 s.
    private func pollPorts() async {
        let active = supervisors.values.filter { $0.pgid != nil }
        guard !active.isEmpty else { return }
        let starting = active.contains { $0.status == .starting }
        guard starting || Date().timeIntervalSince(lastSlowPoll) >= 10 else { return }
        lastSlowPoll = Date()
        let snapshot = await Task.detached { PortProbe.snapshot() }.value
        for supervisor in active { supervisor.refresh(with: snapshot) }
    }

    private func ensureSupervisors() {
        for service in config.repos.flatMap(\.services) where supervisors[service.id] == nil {
            let supervisor = ServiceSupervisor(
                id: service.id,
                fileLog: LogFileWriter(url: LogFileWriter.url(forService: service.id))
            )
            supervisor.onStatusChange = { [weak self] in self?.statusChanged($0) }
            supervisors[service.id] = supervisor
        }
    }

    private func statusChanged(_ supervisor: ServiceSupervisor) {
        persistRuntimeState()
        if case .crashed(let exit) = supervisor.status, config.settings.crashNotifications {
            integration.notifyCrash(service: displayName(supervisor.id), detail: exit.description)
        }
    }

    private func persistRuntimeState() {
        runtimeStore.save(supervisors.values.compactMap(\.runtimeRecord) + pendingOrphans)
    }

    // MARK: Lookups

    func service(_ id: String) -> ServiceConfig? { config.service(id: id) }
    func displayName(_ id: String) -> String { service(id)?.effective.name ?? id }
    func repoName(of id: String) -> String { config.repo(containing: id)?.name ?? "" }
    func status(_ id: String) -> ServiceStatus { supervisors[id]?.status ?? .stopped }
    var activeCount: Int { supervisors.values.filter { $0.status.isActive }.count }
    var hasCrash: Bool { supervisors.values.contains { $0.status.isCrashed } }
    var pinnedIDs: [String] { config.pinnedOrder.filter { service($0) != nil } }
    func isPinned(_ id: String) -> Bool { config.pinnedOrder.contains(id) }

    func setupRequirement(_ id: String) -> SetupRequirement? {
        guard let service = service(id), let shell else { return nil }
        return LaunchPlanner.setupRequirement(for: service.effective, searchPath: shell.variables["PATH"])
    }

    // MARK: Service actions

    func start(_ id: String, force: Bool = false) {
        guard let service = service(id), let supervisor = supervisors[id], !supervisor.status.isActive else { return }
        guard let shell else {
            Alerts.info("Henüz hazır değil", "Shell ortamı yükleniyor, birkaç saniye sonra tekrar dene.")
            return
        }
        let definition = service.effective
        guard !force, let port = definition.portHint else {
            launch(definition, on: supervisor, shell: shell)
            return
        }
        Task {
            let snapshot = await Task.detached { PortProbe.snapshot() }.value
            if let owner = PortProbe.owners(ofPort: port, in: snapshot).first {
                let proceed = Alerts.confirm(
                    "\(port) portu kullanımda",
                    "\(describe(owner)) bu portu dinliyor. Yine de başlatılsın mı?",
                    confirm: "Yine de başlat",
                    cancel: "İptal"
                )
                guard proceed else { return }
            }
            launch(definition, on: supervisor, shell: shell)
        }
    }

    private func launch(_ definition: ServiceDefinition, on supervisor: ServiceSupervisor, shell: ShellEnvironment) {
        let plan: LaunchPlan
        do {
            plan = try LaunchPlanner.plan(definition, shell: shell.variables)
        } catch {
            supervisor.appendSystem(["❌ başlatılamadı: \(error)"])
            Alerts.info("\(definition.name) başlatılamadı", "\(error)")
            return
        }
        do {
            try supervisor.start(plan, expectsPort: definition.portHint != nil)
        } catch {
            Alerts.info("\(definition.name) başlatılamadı", "\(error)")
        }
    }

    private func describe(_ owner: ListeningSocket) -> String {
        if let supervisor = supervisors.values.first(where: { $0.pgid == owner.pgid }) {
            return displayName(supervisor.id)
        }
        return "\(owner.command) (pid \(owner.pid))"
    }

    func stop(_ id: String) {
        guard let supervisor = supervisors[id] else { return }
        Task { await supervisor.stop() }
    }

    func restart(_ id: String) {
        guard let supervisor = supervisors[id] else { return }
        Task {
            await supervisor.stop()
            for _ in 0..<60 where supervisor.status.isActive {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            start(id, force: true)
        }
    }

    func stopAll() async {
        let active = supervisors.values.filter { $0.status.isActive }
        await withTaskGroup(of: Void.self) { group in
            for supervisor in active {
                group.addTask { await supervisor.stop() }
            }
        }
        for _ in 0..<120 where activeCount > 0 {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func runSetup(_ id: String) {
        guard let requirement = setupRequirement(id), let shell, let supervisor = supervisors[id] else { return }
        do {
            guard let request = try LaunchPlanner.setupRequest(requirement, shell: shell.variables) else { return }
            try supervisor.runSetup(request)
        } catch {
            Alerts.info("Kurulum başlatılamadı", "\(error)")
        }
    }

    // MARK: Config edits

    func togglePin(_ id: String) {
        mutate { config in
            if let index = config.pinnedOrder.firstIndex(of: id) {
                config.pinnedOrder.remove(at: index)
            } else {
                config.pinnedOrder.append(id)
            }
        }
    }

    func movePinned(from source: IndexSet, to destination: Int) {
        var ids = pinnedIDs
        ids.move(fromOffsets: source, toOffset: destination)
        mutate { $0.pinnedOrder = ids }
    }

    func updateOverrides(_ id: String, _ overrides: ServiceOverrides) {
        mutate { config in
            for r in config.repos.indices {
                if let s = config.repos[r].services.firstIndex(where: { $0.id == id }) {
                    config.repos[r].services[s].overrides = overrides
                }
            }
        }
    }

    func removeService(_ id: String) {
        guard supervisors[id]?.status.isActive != true else {
            Alerts.info("Servis çalışıyor", "Kaldırmadan önce servisi durdur.")
            return
        }
        mutate { config in
            for r in config.repos.indices {
                guard let removed = config.repos[r].services.first(where: { $0.id == id }) else { continue }
                config.repos[r].services.removeAll { $0.id == id }
                if removed.source.kind != .manual, !config.repos[r].declinedSources.contains(removed.source) {
                    config.repos[r].declinedSources.append(removed.source)
                }
            }
            config.pinnedOrder.removeAll { $0 == id }
        }
        supervisors[id] = nil
        if selection == id { selection = nil }
        refreshSuggestions()
    }

    // MARK: Repos

    func rescan() async {
        isScanning = true
        defer { isScanning = false }
        let roots = config.roots.map { URL(fileURLWithPath: $0) }
        let known = config.repos.map(\.path)
        let ignored = Set(config.ignoredRepos)
        let (candidates, found) = await Task.detached { () -> ([URL], [String: RepoDiscovery]) in
            let knownSet = Set(known)
            let candidates = roots
                .flatMap { RepoScanner.candidateRepos(in: $0) }
                .filter { !knownSet.contains($0.path) && !ignored.contains($0.path) }
            var found: [String: RepoDiscovery] = [:]
            for path in known + candidates.map(\.path) {
                found[path] = RepoScanner.discover(repo: URL(fileURLWithPath: path))
            }
            return (candidates, found)
        }.value
        newRepoCandidates = candidates
        discoveries = found
        mutate { config in
            for index in config.repos.indices {
                if let discovery = found[config.repos[index].path] {
                    config.repos[index] = ConfigMerger.merge(discovery, into: config.repos[index]).repo
                }
            }
        }
        refreshSuggestions()
    }

    func discover(_ url: URL) -> RepoDiscovery {
        let discovery = RepoScanner.discover(repo: url)
        discoveries[url.path] = discovery
        return discovery
    }

    func addRepo(_ path: String, services selected: [DiscoveredService]) {
        guard config.repoIndex(path: path) == nil else { return }
        let offered = discoveries[path]?.services ?? []
        mutate { config in
            let repo = ConfigMerger.accept(selected, offered: offered, into: RepoConfig(path: path), takenIDs: config.allServiceIDs)
            config.repos.append(repo)
            config.repos.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            config.ignoredRepos.removeAll { $0 == path }
        }
        newRepoCandidates.removeAll { $0.path == path }
        refreshSuggestions()
    }

    func ignoreRepos(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        mutate { config in
            for path in paths where !config.ignoredRepos.contains(path) { config.ignoredRepos.append(path) }
        }
        newRepoCandidates.removeAll { paths.contains($0.path) }
    }

    func removeRepo(_ path: String) {
        guard let repo = config.repos.first(where: { $0.path == path }) else { return }
        if repo.services.contains(where: { supervisors[$0.id]?.status.isActive == true }) {
            Alerts.info("Repo'da çalışan servis var", "Kaldırmadan önce servisleri durdur.")
            return
        }
        let ids = Set(repo.services.map(\.id))
        mutate { config in
            config.repos.removeAll { $0.path == path }
            config.pinnedOrder.removeAll { ids.contains($0) }
        }
        for id in ids { supervisors[id] = nil }
        if let selection, ids.contains(selection) { self.selection = nil }
        refreshSuggestions()
    }

    func acceptSuggestions(_ path: String, selected: [DiscoveredService]) {
        guard let index = config.repoIndex(path: path) else { return }
        let offered = unmatched[path] ?? []
        mutate { config in
            config.repos[index] = ConfigMerger.accept(selected, offered: offered, into: config.repos[index], takenIDs: config.allServiceIDs)
        }
        refreshSuggestions()
    }

    func addManualService(_ path: String, definition: ServiceDefinition) {
        guard let index = config.repoIndex(path: path) else { return }
        mutate { config in
            let base = "\(config.repos[index].name)/\(Slug.make(definition.name))"
            let id = Slug.unique(base, taken: config.allServiceIDs)
            config.repos[index].services.append(ServiceConfig(id: id, source: .manual, discovered: definition))
        }
    }

    private func refreshSuggestions() {
        var newSuggestions: [String: [DiscoveredService]] = [:]
        var newUnmatched: [String: [DiscoveredService]] = [:]
        for repo in config.repos {
            guard let discovery = discoveries[repo.path] else { continue }
            let outcome = ConfigMerger.merge(discovery, into: repo)
            newSuggestions[repo.path] = outcome.suggestions
            newUnmatched[repo.path] = outcome.unmatched
        }
        suggestions = newSuggestions
        unmatched = newUnmatched
    }

    // MARK: Settings

    func addRoot(_ path: String) async {
        mutate { if !$0.roots.contains(path) { $0.roots.append(path) } }
        await rescan()
    }

    func removeRoot(_ path: String) async {
        mutate { $0.roots.removeAll { $0 == path } }
        await rescan()
    }

    func setCrashNotifications(_ enabled: Bool) {
        mutate { $0.settings.crashNotifications = enabled }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try integration.setLaunchAtLogin(enabled)
            mutate { $0.settings.launchAtLogin = enabled }
        } catch {
            Alerts.info("Login ayarı değiştirilemedi", error.localizedDescription)
        }
    }

    private func mutate(_ change: (inout AppConfig) -> Void) {
        change(&config)
        do {
            try configStore.save(config)
        } catch {
            Alerts.info("Ayarlar kaydedilemedi", error.localizedDescription)
        }
        ensureSupervisors()
    }
}
```

- [ ] **Step 3: Derle**

Run: `make build`
Expected: `Build complete!`, hata ve uyarı yok.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: app model orchestrating discovery, supervisors and config"
```

---

### Task 13: Ana pencere view'ları

**Files:**
- Create:
  - `Sources/DevLauncher/Views/StatusStyle.swift`
  - `Sources/DevLauncher/Views/ServiceRow.swift`
  - `Sources/DevLauncher/Views/MainWindow.swift`
  - `Sources/DevLauncher/Views/ServiceDetailView.swift`
  - `Sources/DevLauncher/Views/LogView.swift`
  - `Sources/DevLauncher/Views/ServiceSettingsForm.swift`
  - `Sources/DevLauncher/Views/RepoSheets.swift`

**Interfaces:**
- Consumes: `AppModel` (Task 12), `ANSIParser`, `ShellWords`, `DotEnvParser`, `LogFileWriter.url(forService:)`.
- Produces:
  - `MainWindow`
  - `StatusDot(status:)`, `StartStopButton(id:)`
  - `ServiceStatus.color`, `.label`, `.ports`
  - `ANSIRender.attributed(_:)`
  - `SheetRoute`
  - Sheets: `NewReposSheet`, `AddRepoSheet(path:)`, `SuggestionsSheet(path:)`, `ManualServiceSheet(path:)`

- [ ] **Step 1: Ortak parçaları yaz**

```swift
// File: Sources/DevLauncher/Views/StatusStyle.swift
import DevLauncherCore
import SwiftUI

extension ServiceStatus {
    var color: Color {
        switch self {
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        case .running: return .green
        case .crashed: return .red
        }
    }

    var label: String {
        switch self {
        case .stopped: return "Durdu"
        case .starting: return "Başlatılıyor…"
        case .running(let ports):
            return ports.isEmpty ? "Çalışıyor" : "Çalışıyor · " + ports.map { ":\($0)" }.joined(separator: " ")
        case .stopping: return "Durduruluyor…"
        case .crashed(let exit): return "Çöktü (\(exit))"
        }
    }

    var ports: [Int] {
        switch self {
        case .running(let ports): return ports
        default: return []
        }
    }
}

struct StatusDot: View {
    let status: ServiceStatus

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .help(status.label)
    }
}

enum ANSIRender {
    static let base: [Color] = [Color(white: 0.45), .red, .green, .orange, .blue, .purple, .teal, .secondary]

    static func attributed(_ line: String) -> AttributedString {
        var result = AttributedString()
        for span in ANSIParser.parse(line) {
            var piece = AttributedString(span.text)
            if let foreground = span.style.foreground { piece.foregroundColor = color(foreground) }
            if span.style.dim { piece.foregroundColor = .secondary }
            if span.style.bold { piece.inlinePresentationIntent = .stronglyEmphasized }
            result += piece
        }
        return result
    }

    static func color(_ color: ANSIColor) -> Color {
        switch color {
        case .standard(let index), .bright(let index):
            return base[max(0, min(7, index))]
        case .palette(let n):
            if n < 16 { return base[n % 8] }
            if n < 232 {
                let v = n - 16
                return Color(red: Double(v / 36) / 5, green: Double((v / 6) % 6) / 5, blue: Double(v % 6) / 5)
            }
            return Color(white: Double(min(n, 255) - 232) / 23)
        case .rgb(let r, let g, let b):
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }
}
```

```swift
// File: Sources/DevLauncher/Views/ServiceRow.swift
import DevLauncherCore
import SwiftUI

struct ServiceRow: View {
    @Environment(AppModel.self) private var model
    let id: String
    var showRepo = false

    var body: some View {
        let status = model.status(id)
        HStack(spacing: 8) {
            StatusDot(status: status)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(id)).lineLimit(1)
                if showRepo {
                    Text(model.repoName(of: id)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let port = status.ports.first {
                Text(":\(port)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if model.service(id)?.sourceMissing == true {
                Image(systemName: "questionmark.circle").foregroundStyle(.orange).help("Kaynakta artık yok")
            }
            StartStopButton(id: id)
        }
        .contextMenu { ServiceContextMenu(id: id) }
    }
}

struct StartStopButton: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        switch model.status(id) {
        case .starting, .running:
            Button { model.stop(id) } label: { Image(systemName: "stop.fill") }
                .buttonStyle(.borderless)
                .help("Durdur")
        case .stopping:
            ProgressView().controlSize(.small)
        case .stopped, .crashed:
            Button { model.start(id) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .help("Başlat")
        }
    }
}

struct ServiceContextMenu: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        if model.status(id).isActive {
            Button("Durdur") { model.stop(id) }
            Button("Yeniden başlat") { model.restart(id) }
        } else {
            Button("Başlat") { model.start(id) }
        }
        Button(model.isPinned(id) ? "Sabitlemeyi kaldır" : "Sabitle") { model.togglePin(id) }
    }
}
```

- [ ] **Step 2: Ana pencere ve sidebar'ı yaz**

```swift
// File: Sources/DevLauncher/Views/MainWindow.swift
import AppKit
import DevLauncherCore
import SwiftUI

enum SheetRoute: Identifiable {
    case newRepos
    case addRepo(String)
    case suggestions(String)
    case manualService(String)

    var id: String {
        switch self {
        case .newRepos: return "new"
        case .addRepo(let path): return "add:\(path)"
        case .suggestions(let path): return "suggest:\(path)"
        case .manualService(let path): return "manual:\(path)"
        }
    }
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: SheetRoute?

    var body: some View {
        NavigationSplitView {
            Sidebar(sheet: $sheet)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            if let id = model.selection, model.service(id) != nil {
                ServiceDetailView(id: id).id(id)
            } else {
                ContentUnavailableView(
                    "Bir servis seç",
                    systemImage: "bolt.horizontal.circle",
                    description: Text("Soldan bir servis seçerek loglarını ve ayarlarını görebilirsin.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { addRepoFromPanel() } label: { Label("Repo ekle", systemImage: "folder.badge.plus") }
                Button { Task { await model.rescan() } } label: { Label("Yeniden tara", systemImage: "arrow.clockwise") }
                    .disabled(model.isScanning)
                Button { Task { await model.stopAll() } } label: { Label("Tümünü durdur", systemImage: "stop.circle") }
                    .disabled(model.activeCount == 0)
            }
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .newRepos: NewReposSheet()
            case .addRepo(let path): AddRepoSheet(path: path)
            case .suggestions(let path): SuggestionsSheet(path: path)
            case .manualService(let path): ManualServiceSheet(path: path)
            }
        }
    }

    private func addRepoFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ekle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard model.config.repoIndex(path: url.path) == nil else {
            Alerts.info("Repo zaten listede", url.lastPathComponent)
            return
        }
        _ = model.discover(url)
        sheet = .addRepo(url.path)
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var sheet: SheetRoute?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            if !model.newRepoCandidates.isEmpty {
                Button { sheet = .newRepos } label: {
                    Label("\(model.newRepoCandidates.count) yeni repo bulundu", systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
            }
            Section("Sabitlenenler") {
                if model.pinnedIDs.isEmpty {
                    Text("Bir servise sağ tıklayıp “Sabitle” de.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.pinnedIDs, id: \.self) { id in
                    ServiceRow(id: id, showRepo: true).tag(id)
                }
                .onMove { model.movePinned(from: $0, to: $1) }
            }
            ForEach(model.config.repos, id: \.path) { repo in
                Section {
                    ForEach(repo.services.filter { !model.isPinned($0.id) }) { service in
                        ServiceRow(id: service.id).tag(service.id)
                    }
                } header: {
                    RepoHeader(repo: repo, sheet: $sheet)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct RepoHeader: View {
    @Environment(AppModel.self) private var model
    let repo: RepoConfig
    @Binding var sheet: SheetRoute?

    var body: some View {
        HStack {
            Text(repo.name)
            let count = model.suggestions[repo.path]?.count ?? 0
            if count > 0 {
                Button { sheet = .suggestions(repo.path) } label: { Text("\(count) yeni").font(.caption2) }
                    .buttonStyle(.borderless)
                    .help("Keşfedilen yeni servisler")
            }
            Spacer()
            Menu {
                Button("Keşfedilen servisler…") { sheet = .suggestions(repo.path) }
                Button("Manuel servis ekle…") { sheet = .manualService(repo.path) }
                Divider()
                Button("Finder'da göster") { model.integration.reveal(repo.path) }
                Button("Repoyu kaldır", role: .destructive) { model.removeRepo(repo.path) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
```

- [ ] **Step 3: Detay, log ve ayar view'larını yaz**

```swift
// File: Sources/DevLauncher/Views/ServiceDetailView.swift
import DevLauncherCore
import SwiftUI

struct ServiceDetailView: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var tab: Tab = .log

    enum Tab: String, CaseIterable, Identifiable {
        case log = "Log"
        case settings = "Ayarlar"
        var id: String { rawValue }
    }

    var body: some View {
        if let service = model.service(id), let supervisor = model.supervisors[id] {
            VStack(spacing: 0) {
                header(service, supervisor)
                banners(service, supervisor)
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .padding(.vertical, 8)
                Divider()
                switch tab {
                case .log: LogView(supervisor: supervisor)
                case .settings: ServiceSettingsForm(service: service)
                }
            }
        }
    }

    @ViewBuilder
    private func header(_ service: ServiceConfig, _ supervisor: ServiceSupervisor) -> some View {
        let definition = service.effective
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusDot(status: supervisor.status)
                    Text(definition.name).font(.title2.bold())
                    if supervisor.isAdopted {
                        Text("sahiplenildi")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(model.repoName(of: id) + " · " + supervisor.status.label).foregroundStyle(.secondary)
                Text(ShellWords.join(definition.launchCommand))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            ForEach(supervisor.status.ports, id: \.self) { port in
                Button(":\(port)") { model.integration.openBrowser(port: port) }.help("Tarayıcıda aç")
            }
            Button { model.togglePin(id) } label: {
                Image(systemName: model.isPinned(id) ? "pin.fill" : "pin")
            }
            .help(model.isPinned(id) ? "Sabitlemeyi kaldır" : "Sabitle")
            if supervisor.status.isActive {
                Button("Yeniden başlat") { model.restart(id) }.disabled(supervisor.status == .stopping)
                Button("Durdur") { model.stop(id) }.disabled(supervisor.status == .stopping)
            } else {
                Button("Başlat") { model.start(id) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("r")
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func banners(_ service: ServiceConfig, _ supervisor: ServiceSupervisor) -> some View {
        if let requirement = model.setupRequirement(id) {
            Banner(systemImage: "exclamationmark.triangle.fill", tint: .orange, text: requirement.message) {
                if requirement.fix != nil {
                    Button(supervisor.isRunningSetup ? "Çalışıyor…" : requirement.fixTitle) { model.runSetup(id) }
                        .disabled(supervisor.isRunningSetup)
                }
            }
        }
        if service.sourceMissing {
            Banner(
                systemImage: "questionmark.circle.fill",
                tint: .orange,
                text: "Bu servis artık kaynağında (launch.json / package.json) bulunmuyor. Ayarlar sekmesinden kaldırabilirsin."
            ) { EmptyView() }
        }
    }
}

struct Banner<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            actions()
        }
        .padding(10)
        .background(tint.opacity(0.12))
    }
}
```

```swift
// File: Sources/DevLauncher/Views/LogView.swift
import DevLauncherCore
import SwiftUI

struct LogView: View {
    @Environment(AppModel.self) private var model
    let supervisor: ServiceSupervisor
    @State private var query = ""
    @State private var autoScroll = true

    var body: some View {
        let lines = filtered
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Logda ara", text: $query)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 240)
                Toggle("Otomatik kaydır", isOn: $autoScroll).toggleStyle(.checkbox)
                Spacer()
                Text("\(lines.count) satır").font(.caption).foregroundStyle(.secondary)
                Button("Log dosyası") { model.integration.reveal(LogFileWriter.url(forService: supervisor.id).path) }
                Button("Temizle") { supervisor.logs.clear() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            LogLineView(line: line).id(line.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: supervisor.logs.lines.last?.id) { _, last in
                    guard autoScroll, query.isEmpty, let last else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
                .onAppear {
                    if let last = lines.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var filtered: [LogLine] {
        let all = supervisor.logs.lines
        guard !query.isEmpty else { return all }
        return all.filter { ANSIParser.strip($0.text).localizedCaseInsensitiveContains(query) }
    }
}

struct LogLineView: View {
    let line: LogLine

    var body: some View {
        Group {
            if line.kind == .system {
                Text(line.text).foregroundStyle(.secondary).italic()
            } else {
                Text(ANSIRender.attributed(line.text))
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
```

```swift
// File: Sources/DevLauncher/Views/ServiceSettingsForm.swift
import DevLauncherCore
import SwiftUI

/// Edits a service's overrides. Only fields that differ from the discovered definition are stored.
struct ServiceSettingsForm: View {
    @Environment(AppModel.self) private var model
    let service: ServiceConfig

    @State private var name = ""
    @State private var command = ""
    @State private var cwd = ""
    @State private var envFile = ""
    @State private var envText = ""
    @State private var reload = false
    @State private var port = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("Ad", text: $name)
                TextField("Komut", text: $command, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
                TextField("Çalışma klasörü", text: $cwd)
                TextField("Port", text: $port, prompt: Text("örn. 8000"))
                if service.discovered.supportsReload {
                    Toggle("Kod değişince yeniden yükle (--reload)", isOn: $reload)
                }
            } header: {
                Text("Genel")
            } footer: {
                Text("Değişiklikler bir sonraki başlatmada geçerli olur.").foregroundStyle(.secondary)
            }
            Section("Ortam değişkenleri") {
                TextField("Env dosyası", text: $envFile, prompt: Text("boş = env dosyası yok"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ek değişkenler (her satıra KEY=VALUE); keşfedilenlerin üzerine yazar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $envText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                }
                if !service.discovered.env.isEmpty {
                    DisclosureGroup("Keşfedilen değişkenler (\(service.discovered.env.count))") {
                        ForEach(service.discovered.env.keys.sorted(), id: \.self) { key in
                            Text("\(key)=\(service.discovered.env[key] ?? "")")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Section {
                HStack {
                    Button("Keşfedilen değerlere dön") { resetToDiscovered() }
                        .disabled(service.overrides.isEmpty)
                    Spacer()
                    if saved { Text("Kaydedildi").foregroundStyle(.secondary) }
                    Button("Kaydet") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                }
            }
            Section {
                Button("Servisi kaldır", role: .destructive) { model.removeService(service.id) }
            }
        }
        .formStyle(.grouped)
        .onAppear { load(service.effective, extraEnv: service.overrides.env ?? [:]) }
    }

    private func load(_ definition: ServiceDefinition, extraEnv: [String: String]) {
        name = definition.name
        command = ShellWords.join(definition.command)
        cwd = definition.cwd
        envFile = definition.envFile ?? ""
        reload = definition.reloadEnabled
        port = definition.portHint.map(String.init) ?? ""
        envText = extraEnv.keys.sorted().map { "\($0)=\(extraEnv[$0] ?? "")" }.joined(separator: "\n")
        saved = false
    }

    private func save() {
        let discovered = service.discovered
        var overrides = ServiceOverrides()
        if name != discovered.name { overrides.name = name }
        let words = ShellWords.split(command)
        if words != discovered.command { overrides.command = words }
        if cwd != discovered.cwd { overrides.cwd = cwd }
        if envFile != (discovered.envFile ?? "") { overrides.envFile = envFile }
        let extra = DotEnvParser.parse(envText)
        if !extra.isEmpty { overrides.env = extra }
        if reload != discovered.reloadEnabled { overrides.reloadEnabled = reload }
        if let value = Int(port), value != discovered.portHint { overrides.portHint = value }
        model.updateOverrides(service.id, overrides)
        saved = true
    }

    private func resetToDiscovered() {
        model.updateOverrides(service.id, ServiceOverrides())
        load(service.discovered, extraEnv: [:])
    }
}
```

- [ ] **Step 4: Repo sheet'lerini yaz**

```swift
// File: Sources/DevLauncher/Views/RepoSheets.swift
import DevLauncherCore
import SwiftUI

struct ServicePickerList: View {
    let services: [DiscoveredService]
    @Binding var selected: Set<String>

    var body: some View {
        ForEach(services, id: \.id) { service in
            Toggle(isOn: Binding(
                get: { selected.contains(service.id) },
                set: { isOn in
                    if isOn { selected.insert(service.id) } else { selected.remove(service.id) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(service.definition.name)
                        if let port = service.definition.portHint {
                            Text(":\(port)").foregroundStyle(.secondary)
                        }
                    }
                    Text(ShellWords.join(service.definition.launchCommand))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
    }
}

struct SkippedNote: View {
    let discovery: RepoDiscovery?

    var body: some View {
        if let discovery, !(discovery.skipped.isEmpty && discovery.warnings.isEmpty) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(discovery.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if !discovery.skipped.isEmpty {
                    Text("Atlanan konfigürasyonlar: " + discovery.skipped.map { "\($0.name) (\($0.reason))" }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}

struct SheetButtons: View {
    let confirmTitle: String
    var confirmDisabled = false
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button("İptal") { dismiss() }
            Button(confirmTitle) {
                onConfirm()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(confirmDisabled)
        }
    }
}

struct NewReposSheet: View {
    @Environment(AppModel.self) private var model
    @State private var selectedRepos: Set<String> = []
    @State private var selectedServices: Set<String> = []
    @State private var ignoreRest = false

    var body: some View {
        let candidates = model.newRepoCandidates.map(\.path)
        VStack(alignment: .leading, spacing: 12) {
            Text("Yeni repolar").font(.title2.bold())
            Text("Eklemek istediğin repoları ve servislerini seç.").foregroundStyle(.secondary)
            List {
                ForEach(candidates, id: \.self) { path in
                    let services = model.discoveries[path]?.services ?? []
                    Toggle(isOn: Binding(
                        get: { selectedRepos.contains(path) },
                        set: { isOn in
                            if isOn { selectedRepos.insert(path) } else { selectedRepos.remove(path) }
                        }
                    )) {
                        HStack {
                            Text(URL(fileURLWithPath: path).lastPathComponent).bold()
                            Text(services.isEmpty ? "servis bulunamadı" : "\(services.count) servis").foregroundStyle(.secondary)
                        }
                    }
                    if selectedRepos.contains(path), !services.isEmpty {
                        ServicePickerList(services: services, selected: $selectedServices)
                            .padding(.leading, 22)
                    }
                }
            }
            .frame(minHeight: 380)
            Toggle("Seçmediğim repoları bir daha önerme", isOn: $ignoreRest)
            SheetButtons(confirmTitle: "Ekle") { apply(candidates) }
        }
        .padding(20)
        .frame(width: 620)
        .onAppear {
            for path in candidates {
                let services = model.discoveries[path]?.services ?? []
                if !services.isEmpty { selectedRepos.insert(path) }
                selectedServices.formUnion(services.map(\.id))
            }
        }
    }

    private func apply(_ candidates: [String]) {
        for path in candidates where selectedRepos.contains(path) {
            let services = model.discoveries[path]?.services ?? []
            model.addRepo(path, services: services.filter { selectedServices.contains($0.id) })
        }
        if ignoreRest {
            model.ignoreRepos(candidates.filter { !selectedRepos.contains($0) })
        }
    }
}

struct AddRepoSheet: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var selected: Set<String> = []

    var body: some View {
        let discovery = model.discoveries[path]
        let services = discovery?.services ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text(URL(fileURLWithPath: path).lastPathComponent).font(.title2.bold())
            if services.isEmpty {
                Text("Bu klasörde servis bulunamadı. Repoyu ekleyip sonra manuel servis tanımlayabilirsin.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Eklenecek servisleri seç:").foregroundStyle(.secondary)
                List { ServicePickerList(services: services, selected: $selected) }
                    .frame(minHeight: 220)
            }
            SkippedNote(discovery: discovery)
            SheetButtons(confirmTitle: "Repoyu ekle") {
                model.addRepo(path, services: services.filter { selected.contains($0.id) })
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { selected = Set(services.map(\.id)) }
    }
}

struct SuggestionsSheet: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var selected: Set<String> = []

    var body: some View {
        let services = model.unmatched[path] ?? []
        let fresh = Set((model.suggestions[path] ?? []).map(\.id))
        VStack(alignment: .leading, spacing: 12) {
            Text("Keşfedilen servisler · \(URL(fileURLWithPath: path).lastPathComponent)").font(.title2.bold())
            if services.isEmpty {
                Text("Listede olmayan keşfedilmiş servis yok.").foregroundStyle(.secondary)
            } else {
                Text("Seçmediklerin bir daha öneri olarak gösterilmez; bu ekrandan her zaman ekleyebilirsin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List { ServicePickerList(services: services, selected: $selected) }
                    .frame(minHeight: 220)
            }
            SkippedNote(discovery: model.discoveries[path])
            SheetButtons(confirmTitle: "Kaydet") {
                model.acceptSuggestions(path, selected: services.filter { selected.contains($0.id) })
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { selected = fresh }
    }
}

struct ManualServiceSheet: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var name = ""
    @State private var command = ""
    @State private var cwd = ""
    @State private var port = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manuel servis").font(.title2.bold())
            Form {
                TextField("Ad", text: $name, prompt: Text("örn. legacy-ear"))
                TextField("Komut", text: $command, prompt: Text("örn. mvn spring-boot:run"))
                    .font(.system(.body, design: .monospaced))
                TextField("Çalışma klasörü", text: $cwd)
                TextField("Port (opsiyonel)", text: $port)
            }
            SheetButtons(
                confirmTitle: "Ekle",
                confirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty || ShellWords.split(command).isEmpty
            ) {
                model.addManualService(
                    path,
                    definition: ServiceDefinition(name: name, command: ShellWords.split(command), cwd: cwd, portHint: Int(port))
                )
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { cwd = path }
    }
}
```

- [ ] **Step 5: Derle**

Run: `make build`
Expected: `Build complete!`, hata yok.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: main window with sidebar, service detail, logs, settings and repo sheets"
```

---

### Task 14: Menu bar, Ayarlar penceresi, uygulama giriş noktası

**Files:**
- Create: `Sources/DevLauncher/Views/MenuBarView.swift`, `Sources/DevLauncher/Views/SettingsView.swift`, `Sources/DevLauncher/DevLauncherApp.swift`
- Delete: `Sources/DevLauncher/main.swift`

**Interfaces:**
- Consumes: `AppModel`, `MainWindow`, `StatusDot`, `StartStopButton`, `Alerts`.
- Produces: `@main DevLauncherApp`, `AppDelegate` (owns the `AppModel`), `MenuBarView`, `SettingsView`.

- [ ] **Step 1: Menu bar ve ayarlar view'larını yaz**

```swift
// File: Sources/DevLauncher/Views/MenuBarView.swift
import AppKit
import DevLauncherCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DevLauncher").font(.headline)
                Spacer()
                if model.activeCount > 0 {
                    Text("\(model.activeCount) çalışıyor").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if model.pinnedIDs.isEmpty {
                Text("Sabitlenmiş servis yok. Ana pencerede bir servise sağ tıklayıp “Sabitle” diyebilirsin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.pinnedIDs, id: \.self) { id in
                        MenuServiceRow(id: id)
                    }
                }
                .padding(.vertical, 6)
            }
            Divider()
            HStack {
                Button("Pencereyi aç") { openMainWindow() }
                Spacer()
                Button("Tümünü durdur") { Task { await model.stopAll() } }
                    .disabled(model.activeCount == 0)
                Button("Çık") { NSApp.terminate(nil) }
            }
            .padding(10)
        }
        .frame(width: 360)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct MenuServiceRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let id: String

    var body: some View {
        let status = model.status(id)
        HStack(spacing: 8) {
            StatusDot(status: status)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(id)).lineLimit(1)
                Text(model.repoName(of: id) + " · " + status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let port = status.ports.first {
                Button(":\(port)") { model.integration.openBrowser(port: port) }.buttonStyle(.link)
            }
            Button {
                model.selection = id
                openWindow(id: "main")
                NSApp.activate()
            } label: {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .help("Logu göster")
            StartStopButton(id: id)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
```

```swift
// File: Sources/DevLauncher/Views/SettingsView.swift
import AppKit
import DevLauncherCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Taranan klasörler") {
                ForEach(model.config.roots, id: \.self) { root in
                    HStack {
                        Text(root).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { Task { await model.removeRoot(root) } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Klasör ekle…") { addRoot() }
            }
            Section("Genel") {
                Toggle("Login'de başlat", isOn: Binding(
                    get: { model.integration.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Servis çökünce bildirim gönder", isOn: Binding(
                    get: { model.config.settings.crashNotifications },
                    set: { model.setCrashNotifications($0) }
                ))
            }
            Section("Shell ortamı") {
                if let shell = model.shell {
                    if let error = shell.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else {
                        Text("PATH: " + (shell.variables["PATH"] ?? ""))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
                Button("Yeniden yükle") { Task { await model.reloadShell() } }
            }
            Section("Dosyalar") {
                Button("Ayar dosyasını göster") {
                    model.integration.reveal(ConfigStore.defaultDirectory.appendingPathComponent("config.json").path)
                }
                Button("Log klasörünü göster") { model.integration.reveal(LogFileWriter.defaultDirectory.path) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Ekle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.addRoot(url.path) }
    }
}
```

- [ ] **Step 2: Giriş noktasını yaz, placeholder'ı sil**

```bash
git rm -q Sources/DevLauncher/main.swift
```

```swift
// File: Sources/DevLauncher/DevLauncherApp.swift
import AppKit
import DevLauncherCore
import SwiftUI

@main
struct DevLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("DevLauncher", id: "main") {
            MainWindow()
                .environment(delegate.model)
                .frame(minWidth: 820, minHeight: 480)
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            MenuBarView().environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(delegate.model)
        }
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if model.hasCrash {
            Image(systemName: "exclamationmark.triangle.fill")
        } else if model.activeCount > 0 {
            Image(systemName: "bolt.horizontal.circle.fill")
        } else {
            Image(systemName: "bolt.horizontal.circle")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.integration.requestNotificationPermission()
        Task { await model.bootstrap() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let count = model.activeCount
        guard count > 0 else { return .terminateNow }
        let stop = Alerts.confirm(
            "\(count) servis çalışıyor",
            "Çıkmadan önce hepsi durdurulacak.",
            confirm: "Hepsini durdur ve çık",
            cancel: "İptal"
        )
        guard stop else { return .terminateCancel }
        Task {
            await model.stopAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
```

- [ ] **Step 3: Derle ve duman testi yap**

Run: `make build && (swift run DevLauncher & sleep 6; pkill -f '.build/.*/DevLauncher'; true)`
Expected: Derleme başarılı. Uygulama açılır; ana pencere ve menu bar ikonu görünür, crash olmadan 6 sn ayakta kalır. Bundle dışında çalıştığı için bildirim ve login özellikleri sessizce devre dışıdır.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: menu bar extra, settings window and app entry point"
```

---

### Task 15: Paketleme, ikon, README, manuel doğrulama

**Files:**
- Create: `Resources/Info.plist`, `scripts/make-icon.swift`, `Resources/AppIcon.icns` (üretilir), `README.md`

**Interfaces:**
- Consumes: Makefile `app`/`install`/`icon` target'ları (Task 1).
- Produces: `build/DevLauncher.app` ve `~/Applications/DevLauncher.app`.

- [ ] **Step 1: Info.plist ve ikon script'ini yaz**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- File: Resources/Info.plist -->
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DevLauncher</string>
    <key>CFBundleIdentifier</key>
    <string>com.etokalak.devlauncher</string>
    <key>CFBundleName</key>
    <string>DevLauncher</string>
    <key>CFBundleDisplayName</key>
    <string>DevLauncher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

```swift
// File: scripts/make-icon.swift
// Renders the app icon into an .iconset folder: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in sizes {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    NSGradient(
        starting: NSColor(calibratedRed: 0.20, green: 0.32, blue: 0.95, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.70, blue: 0.85, alpha: 1)
    )?.draw(in: shape, angle: -60)
    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.5, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try png.write(to: URL(fileURLWithPath: "\(output)/\(name).png"))
}
```

- [ ] **Step 2: İkonu üret ve plist'i doğrula**

Run: `make icon && plutil -lint Resources/Info.plist && ls -la Resources/AppIcon.icns`
Expected: `Resources/Info.plist: OK`, `AppIcon.icns` mevcut.

- [ ] **Step 3: README yaz**

````markdown
<!-- File: README.md -->
# DevLauncher

`~/Projects/acme` altındaki servisleri (FastAPI/uvicorn, Temporal worker'ları, Vite/Next dev
server'ları) VS Code açmadan başlatıp durduran native macOS menu bar + masaüstü uygulaması.

## Kurulum

    make install        # build/DevLauncher.app → ~/Applications/DevLauncher.app (ad-hoc imzalı)
    open ~/Applications/DevLauncher.app

Geliştirirken:

    make build          # debug derleme
    make test           # Core testleri (Swift Testing, Xcode gerekmez)
    swift run DevLauncher

## Nasıl çalışır

- Servisler `.vscode/launch.json` (debugpy) ve `package.json` (`dev`/`start`) dosyalarından keşfedilir.
- Python servisleri `<repo>/.venv/bin/python` ile, env katmanları VS Code'daki gibi (`.env` + config `env`) çalışır.
- Her servis kendi process group'unda başlar; durdurma tüm gruba SIGTERM, 5 sn sonra SIGKILL gönderir.
- Ayarlar: `~/Library/Application Support/DevLauncher/config.json`
- Loglar: `~/Library/Logs/DevLauncher/`

## Kapsam dışı (v1)

Debugger attach, docker-compose, Makefile target keşfi, compound/grup başlatma, otomatik yeniden başlatma.
````

- [ ] **Step 4: Uygulamayı paketle ve kur**

Run: `make install && codesign -v ~/Applications/DevLauncher.app && echo SIGNED`
Expected: `SIGNED`.

- [ ] **Step 5: Manuel doğrulama listesi** (kullanıcıyla birlikte)

1. `open ~/Applications/DevLauncher.app` → ana pencere + menu bar ikonu.
2. Sidebar'da "N yeni repo bulundu" → sheet → `docs-api` ve `storefront-web` ekle.
3. Knowledge API başlat → "Başlatılıyor…" → "Çalışıyor · :8010"; port linki tarayıcıda açılır.
4. Ayarlar sekmesinde reload'u kapat/aç → Kaydet → Yeniden başlat; komut satırında `--reload` görünür/kaybolur.
5. `storefront-web` başlat → `:5173`; durdur → `lsof -iTCP:5173 -sTCP:LISTEN` boş.
6. İki servisi sabitle, sürükleyerek sırala → menu bar aynı sırayı gösterir.
7. `flow-composer` ve `wiki-web` → ikincisinde "3000 portu kullanımda" uyarısı.
8. Manuel servis `sh -c "sleep 2; exit 3"` → "Çöktü (çıkış kodu 3)", bildirim, menu bar'da uyarı ikonu.
9. Servis çalışırken Çık → onay → servis durur, port boşalır.
10. Servis çalışırken `pkill -9 DevLauncher` → uygulamayı aç → "önceki oturumdan çalışıyor" → Sahiplen → Durdur çalışır.
11. Ayarlar → Login'de başlat → Sistem Ayarları > Genel > Giriş Öğeleri'nde DevLauncher görünür.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "build: app bundle packaging, icon and README"
```
