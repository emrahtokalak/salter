# DevLauncher — Tasarım Dokümanı

- **Tarih:** 2026-10-09
- **Durum:** Onaylandı (tasarım), spec incelemesi bekliyor
- **Konum:** `~/Projects/salter`
- **Not (2026-10-10):** Uygulama **Şalter** olarak yeniden adlandırıldı; teknik ad `salter` (modüller `Salter`/`SalterCore`, bundle id `com.etokalak.salter`, `~/Library/Application Support/Salter`). Bu dokümandaki "DevLauncher" geçmiş adıdır.

## 1. Amaç

`~/Projects/acme` altındaki geliştirme servislerini (FastAPI/uvicorn API'leri, Temporal
worker'ları, Vite/Next dev server'ları) VS Code debugger'ı veya terminal açmadan, tek bir native
macOS uygulamasından başlatıp durdurmak.

### Başarı kriterleri

1. Yeni bir repo eklendiğinde servisleri `.vscode/launch.json` ve `package.json`'dan otomatik
   önerilir; kullanıcı seçer, gerekirse düzenler.
2. Kullanıcı sık kullandığı servisleri sabitler (pin) ve sürükle-bırak ile sıralar; menu bar bu
   sırayı gösterir.
3. Tek tıkla başlat/durdur; durdurma alt process'leri (uvicorn reloader, npm → node) yetim
   bırakmaz, port serbest kalır.
4. Her servisin canlı logu (ANSI renkli) uygulama içinde görülür; çökme anında neden görünür.
5. uvicorn servislerinde `--reload` servis bazında açılıp kapatılabilir.

### Kapsam dışı (v1)

- Debugger / debugpy attach
- docker-compose ve altyapı yönetimi (Redis, Postgres)
- Makefile target keşfi (manuel servis ile eklenebilir)
- launch.json `compounds` ve grup başlatma
- Otomatik yeniden başlatma
- Servis başına CPU/RAM göstergesi

## 2. Mevcut ortam (keşif bulguları)

- Python servisleri `uv` + repo içi `.venv` kullanıyor; VS Code'dan `debugpy` launch config'leri
  ile çalıştırılıyor. Görülen config şekilleri:
  - `module: uvicorn` + `args` (`gateway-api` :8002, `analytics-api` :8000,
    `docs-api` :8010)
  - `module: main` / `main_gpu` / `workflows.*.launcher` (Temporal worker'ları,
    `media-pipeline`'da 10 config, `analytics-worker`)
  - `program: ${workspaceFolder}/src/app/main.py` + `python: ${workspaceFolder}/.venv/bin/python`
    (`flow-api`)
  - `env.PYTHONPATH`, opsiyonel `envFile`, bazen `env.TEMPORAL_TASK_QUEUE`
  - `//` yorumları ve sondaki virgüller (JSONC) mevcut
- Node uygulamaları: `admin-web`, `storefront-web` (Vite, `dev: vite`), `flow-composer`
  (`next dev`), `wiki-web` (`next dev --turbopack --port 3000`). Lock dosyası çoğunlukla
  `package-lock.json`; `wiki-web`'de ayrıca `yarn.lock` var.
- Port çakışma adayları: `wiki-web` ve `flow-composer` → 3000; iki Vite SPA → 5173.
- Toolchain: Swift 6.3 (Command Line Tools), Xcode yok. `uv`, `node` Homebrew'da.
- Spike sonuçları (atıldı):
  - SPM ile `Window` + `MenuBarExtra` SwiftUI uygulaması derleniyor; elle paketlenen `.app`
    ad-hoc imza (`codesign -s -`) ile açılıyor.
  - XCTest CLT'de yok. Swift Testing CLT'de var ama şu bayraklarla çalışıyor:
    `-Xswiftc -F -Xswiftc $CLT/Library/Developer/Frameworks`
    `-Xlinker -rpath -Xlinker $CLT/Library/Developer/Frameworks`
    `-Xlinker -rpath -Xlinker $CLT/Library/Developer/usr/lib`
    (`$CLT=/Library/Developer/CommandLineTools`).

## 3. Mimari

SPM paketi, iki target + test target:

```
devlauncher/
  Package.swift                 (macOS 14+, swift-tools 6.0)
  Makefile                      (build, test, app, install)
  Resources/Info.plist
  Sources/DevLauncherCore/      (UI'dan bağımsız mantık)
  Sources/DevLauncher/          (SwiftUI uygulaması)
  Tests/DevLauncherCoreTests/   (Swift Testing + fixture'lar)
```

### 3.1 DevLauncherCore bileşenleri

| Bileşen | Sorumluluk | Bağımlılık |
|---|---|---|
| `JSONCReader` | `//`, `/* */` yorumları ve sondaki virgülleri temizleyip `Data` döner (string literal içindekileri korur) | — |
| `LaunchJsonParser` | launch.json → `[LaunchConfig]` (ham model) | `JSONCReader` |
| `PackageJsonParser` | package.json → `dev` script + paket yöneticisi | — |
| `ServiceTranslator` | `LaunchConfig` / package script → `ServiceDefinition` (komut, cwd, env kaynakları, reload desteği, port tahmini); filtreleme ve birleştirme | parser'lar |
| `RepoScanner` | Kök klasör(ler)i tarar; repo başına keşif sonucu (`DiscoveredService` listesi) üretir | translator |
| `ShellEnvironment` | Açılışta `/bin/zsh -ilc 'env'` ile kullanıcı ortamını bir kez yakalar, cache'ler; başarısızsa varsayılan PATH | — |
| `EnvResolver` | Katmanlı env birleştirme (bkz. 4.3), `.env` dosyası okuma | `ShellEnvironment` |
| `ProcessRunner` | `posix_spawn` + `POSIX_SPAWN_SETPGROUP` ile başlatma, stdout/stderr pipe okuma, `kill(-pgid, …)` ile durdurma, exit code yakalama | — |
| `PortProbe` | PGID'deki process'lerin dinlediği TCP portlarını `lsof` ile bulur; verilen portun dolu olup olmadığını ve kimin tuttuğunu söyler | — |
| `ConfigStore` | `config.json` okuma/yazma; yeniden taramada birleştirme (bkz. 4.5) | — |
| `RuntimeStateStore` | `state.json`: çalışan servislerin PID/PGID/başlangıç zamanı | — |
| `LogStore` | Servis başına ring buffer (5.000 satır) + dosya log (10 MB × 2 rotasyon) | — |
| `ANSIParser` | ANSI SGR renk kodları → stil aralıkları (`AttributedString` üretimi UI'da) | — |
| `ServiceSupervisor` | Bir servisin durum makinesi: başlat, izle, durdur, crash tespiti; Runner + Probe + LogStore'u yönetir | yukarıdakiler |

### 3.2 DevLauncher (SwiftUI) bileşenleri

- `DevLauncherApp`: `Window("DevLauncher", id: "main")` + `MenuBarExtra` (`.window` stili).
- `AppModel` (`@Observable`, `@MainActor`): repo/servis listesi, durumlar, pin sırası; Core'a
  delegasyon. UI mantığı burada, view'lar ince.
- Ana pencere: `NavigationSplitView`
  - Sidebar: "Sabitlenenler" bölümü (sürükle-bırak sıralama), altında repo bazlı gruplar;
    "Yeni repo bulundu" rozetleri; "Repo ekle", "Servis ekle", "Yeniden tara".
  - Detay: servis başlığı (durum, port linki, başlat/durdur/yeniden başlat), sekmeler:
    **Log** (canlı, ANSI renkli, arama, temizle, otomatik kaydırma) ve **Ayarlar** (komut,
    cwd, env override'ları, reload toggle, port, pin).
- Menu bar: sabitlenen servisler kullanıcı sırasıyla; her satırda durum noktası + başlat/durdur;
  altta "Tümünü durdur", "Pencereyi aç", "Çık". Crash varsa ikonda rozet.
- Ayarlar penceresi: kök klasörler, login'de başlat, crash bildirimleri.
- Dock davranışı: ana pencere açıkken `NSApp.setActivationPolicy(.regular)`, kapanınca
  `.accessory` (uygulama menu bar'da yaşamaya devam eder).

## 4. Detaylı davranış

### 4.1 Repo keşfi

- Varsayılan kök: `~/Projects/acme`. Ayarlardan ek kök veya tekil klasör eklenebilir.
- Kökün birinci seviye alt klasörleri repo adayıdır; gizli klasörler ve `node_modules` atlanır.
- Uygulama açılışında ve "Yeniden tara"da: listede olmayan adaylar "Yeni repo bulundu" olarak
  gösterilir; kullanıcı ekler veya yok sayar (yok sayılanlar `config.json`'da hatırlanır).
- Repo eklenince keşfedilen servisler önerilir; kullanıcı hangilerini ekleyeceğini işaretler.

### 4.2 launch.json çevirisi

1. Dosya `JSONCReader` ile okunur.
2. **Filtre:** şu config'ler atlanır:
   - `request != "launch"`
   - `module == "pytest"`
   - `purpose` içinde `debug-test`
   - herhangi bir alanda `${file}` geçen
   - `type` `debugpy` / `python` dışında olan (v1'de Node launch config'leri desteklenmez;
     Node için package.json kullanılır)
   - `compounds` tamamen yok sayılır
3. **Değişken yerine koyma:** `${workspaceFolder}` → repo mutlak yolu. Başka `${...}`
   değişkeni içeren config "desteklenmiyor" olarak işaretlenir ve önerilmez.
4. **Yorumlayıcı:** `python` alanı varsa o; yoksa `<repo>/.venv/bin/python`. Dosya yoksa servis
   `needsSetup` uyarısı taşır ("`uv sync` çalıştır" aksiyonu: repo cwd'sinde `uv sync`'i bir
   kerelik görev olarak çalıştırır, çıktısı servis logunda görünür).
5. **Komut:**
   - `module` → `[python, "-m", module] + args`
   - `program` → `[python, program] + args`
6. **cwd:** `cwd` alanı, yoksa repo kökü.
7. **Reload:** komut `-m uvicorn` ise `supportsReload = true`. `reloadEnabled` varsayılanı:
   orijinal args'ta `--reload` varsa true. Çalıştırırken `--reload` eklenir/çıkarılır; diğer
   `--reload-*` argümanları yalnızca reload açıkken geçirilir.
8. **Birleştirme:** `--reload` / `--reload-dir X` çıkarıldıktan sonra komut + cwd + env'i aynı
   olan config'ler tek servise birleşir; ad olarak `--reload` içermeyenin adı kullanılır.
9. **Ad:** config `name` (emoji korunur). Servis kimliği: `<repoKlasörAdı>/<slug(name)>`.
10. **Port tahmini:** args'ta `--port N` veya env'de `PORT`.

### 4.3 Env birleştirme (düşükten yükseğe)

1. `ShellEnvironment` (yakalanan kullanıcı ortamı)
2. `envFile` (config'te varsa) — yoksa `<repo>/.env` (VS Code Python eklentisi varsayılanı);
   dosya yoksa uyarı, servis yine başlar. Format: `KEY=VALUE`, `#` yorumları, opsiyonel tırnak,
   opsiyonel `export ` öneki; değişken genişletme yok.
3. Config `env` (değerlerde `${workspaceFolder}` yerine konur)
4. Kullanıcı override'ları (Ayarlar sekmesi)
5. Sabitler: `PYTHONUNBUFFERED=1`, `FORCE_COLOR=1`

### 4.4 package.json çevirisi

- `scripts.dev` varsa servis önerilir (yoksa `scripts.start`).
- Paket yöneticisi: `pnpm-lock.yaml` → pnpm, `package-lock.json` → npm, `yarn.lock` → yarn
  (bu öncelik sırasıyla; birden fazla varsa ilk eşleşen; kullanıcı Ayarlar'dan değiştirebilir).
- Komut: `[pm, "run", "dev"]`; binary yolu `ShellEnvironment` PATH'inden çözülür.
- `node_modules` yoksa `needsSetup` uyarısı ("`<pm> install` çalıştır" aksiyonu).
- Reload desteği yok (HMR zaten var).
- Port tahmini: script'te `--port N` / `-p N`; yoksa script `vite` içeriyorsa 5173, `next`
  içeriyorsa 3000.

### 4.5 Kalıcılık ve yeniden tarama

`~/Library/Application Support/DevLauncher/config.json`:

```json
{
  "version": 1,
  "roots": ["/Users/…/Projects/acme"],
  "ignoredRepos": ["/Users/…/Projects/acme/docs"],
  "pinnedOrder": ["docs-api/api-uvicorn-debug", "storefront-web/dev"],
  "settings": { "launchAtLogin": false, "crashNotifications": true },
  "repos": [{
    "path": "/Users/…/Projects/acme/docs-api",
    "services": [{
      "id": "docs-api/api-uvicorn-debug",
      "source": { "kind": "launchJson", "configName": "API: uvicorn (debug)" },
      "discovered": { "name": "…", "command": ["…"], "cwd": "…", "envFile": "…",
                      "env": {}, "supportsReload": true, "reloadEnabled": false,
                      "portHint": 8010 },
      "overrides": { "reloadEnabled": true },
      "sourceMissing": false
    }]
  }]
}
```

- Efektif değer = `overrides` varsa o, yoksa `discovered`. Kullanıcı bir alanı düzenleyince
  yalnızca `overrides`'a yazılır.
- Yeniden taramada:
  - `discovered` güncellenir (override'lar korunur)
  - kaynakta artık olmayanlar `sourceMissing = true` olur (silinmez, UI'da işaretli)
  - yeni config'ler "öneri" olarak gösterilir
- Manuel servisler `source.kind = "manual"`; yeniden taramadan etkilenmez.
- Yazma atomik (geçici dosya + rename).

### 4.6 Süreç yaşam döngüsü

**Durumlar:** `stopped`, `starting`, `running(ports: [Int])`, `stopping`, `crashed(exitCode)`.

**Başlatma:**
1. Efektif komut/cwd/env hesaplanır.
2. `portHint` doluysa `PortProbe` sahibini bulur → uyarı ("3000'de wiki-web çalışıyor"):
   "İptal / Yine de başlat".
3. `posix_spawn` (`POSIX_SPAWN_SETPGROUP`, pgid = kendi pid'i), stdin `/dev/null`,
   stdout+stderr ayrı pipe'lar → `LogStore` (stderr satırları işaretli).
4. `state.json`'a PID, PGID, başlangıç zamanı yazılır. Durum `starting`.
5. 2 sn aralıkla `PortProbe`: PGID'deki herhangi bir process LISTEN durumunda bir TCP portu
   açtıysa → `running(ports)`. Port açmayan servisler 3 sn ayakta kalınca `running([])`.
   Probe, `running` olduktan sonra da 10 sn aralıkla devam eder (Vite'in port değiştirmesi gibi
   durumlar için).

**Durdurma:** durum `stopping` → `kill(-pgid, SIGTERM)` → 5 sn bekle → hâlâ grupta process varsa
`kill(-pgid, SIGKILL)` → `stopped`. "Yeniden başlat" = durdur + başlat.

**Beklenmedik çıkış:** ana process `stopping` dışında biterse:
- durum `crashed(exitCode)`
- process grubunda kalan varsa onlar da SIGTERM/SIGKILL ile temizlenir
- log korunur, menu bar ikonunda rozet çıkar, ayar açıksa macOS bildirimi gönderilir
- otomatik yeniden başlatma yok

**Uygulama çıkışı:** çalışan servis varsa "Hepsini durdur ve çık / İptal". Ana pencereyi kapatmak
çıkış değildir.

**Çökme sonrası kurtarma:** açılışta `state.json` okunur.
- Kayıtlı PID hâlâ yaşıyor ve başlangıç zamanı eşleşiyorsa (`proc_pidinfo`) servis "yetim"
  sayılır → "N servis önceki oturumdan çalışıyor: Durdur / Sahiplen".
- Sahiplenilenler `running` olarak izlenir (çıkış `kill(pid, 0)` yoklamasıyla tespit edilir,
  exit code bilinmez). Durdurulabilirler ama log akışı yoktur; bu UI'da belirtilir.

### 4.7 Hata durumları

| Durum | Davranış |
|---|---|
| Yorumlayıcı / `.venv` yok | Servis ⚠️ `needsSetup`, "`uv sync` çalıştır" aksiyonu |
| `node_modules` yok | ⚠️ `needsSetup`, "`<pm> install` çalıştır" aksiyonu |
| Komut binary'si PATH'te yok | Başlatma reddedilir, açıklayıcı hata |
| `.env` yok | Uyarı, servis başlar |
| `posix_spawn` hatası | Durum `crashed`, hata mesajı log'a yazılır |
| Shell ortamı yakalanamadı (timeout 5 sn / hata) | Fallback PATH: `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, Ayarlar'da uyarı |
| launch.json bozuk | Repo uyarı gösterir, diğer kaynaklar (package.json) yine taranır |
| `config.json` bozuk | Yedeği `config.json.broken-<zaman>` olarak saklanır, boş config ile açılır, uyarı |

### 4.8 Loglar

- Bellek: servis başına ring buffer, 5.000 satır.
- Dosya: `~/Library/Logs/DevLauncher/<servis-id-slug>.log`, 10 MB'ı geçince `.1`'e döner
  (en fazla 2 dosya). Her başlatmada ayraç satırı yazılır.
- UI: ANSI SGR (renk, kalın) desteklenir; diğer escape dizileri temizlenir. Arama (filtre),
  temizle, otomatik kaydırma (kullanıcı yukarı kaydırınca durur).

## 5. Test stratejisi

`make test` (Swift Testing, CLT bayrakları Makefile'da).

- **Fixture testleri** (`Tests/DevLauncherCoreTests/Fixtures/`): gerçek dosyaların kopyaları:
  - `gateway-api`, `docs-api`, `flow-api`, `media-pipeline`,
    `analytics-worker`, `storefront` launch.json'ları
  - `admin-web`, `wiki-web` package.json'ları

  Her biri için beklenen servis listesi, komut, cwd, env kaynakları, reload ve port tahmini
  doğrulanır.
- **Birim testleri:**
  - JSONC (yorum, sondaki virgül, string içindeki `//`)
  - filtreler
  - `${workspaceFolder}` yerine koyma
  - birleştirme
  - `.env` parse
  - env katman önceliği
  - `ConfigStore` override/yeniden tarama birleştirme
  - `ANSIParser`
- **Entegrasyon testleri:**
  - `ProcessRunner`:
    - `sh -c 'sleep 100 & sleep 100'` durdurulunca tüm grup ölür
    - SIGTERM'i yok sayan process (`trap '' TERM`) SIGKILL ile kapanır
    - exit code yakalanır
    - stdout/stderr satırları gelir
  - `PortProbe`: `python3 -m http.server 0`'ın açtığı port bulunur.
  - `ServiceSupervisor`: crash tespiti ve durum geçişleri.
- **UI:** otomatik test yok; manuel kontrol listesi plan'da yer alır.

## 6. Build ve dağıtım

- `make build`: `swift build`
- `make test`: CLT Swift Testing bayraklarıyla `swift test`
- `make app`: `swift build -c release` → `build/DevLauncher.app` (Info.plist, ikon) →
  `codesign -s - --force --deep`
- `make install`: `~/Applications/DevLauncher.app`'e kopyala
- Login'de başlat: `SMAppService.mainApp.register()` (Ayarlar toggle'ı; ad-hoc imzalı
  uygulamada çalışır)
- Bundle id: `com.etokalak.devlauncher`; minimum macOS 14.
