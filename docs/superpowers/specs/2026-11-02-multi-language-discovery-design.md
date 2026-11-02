# Çok dilli servis keşfi — tasarım

Tarih: 2026-11-02

## Neden

Şalter bir repoda yalnızca iki şeyi tanıyor: `.vscode/launch.json` içindeki Python
(`debugpy`/`python`) konfigürasyonları ve `package.json`'daki `dev`/`start` script'i.
Kullanıcının Go API'si `classifier-go` (`/Users/dev/Projects/acme/classifier-go`)
repo listesinde görünüyor ama çalıştırılacak servis çıkmıyor: launch.json'daki `"type": "go"`
konfigürasyonları "desteklenmeyen tür: go" diye atlanıyor. Kullanıcı bugün bu servisi repo kökünde
`go run ./cmd/classifier` ile elle başlatıyor.

Hedef: Go, Rust, Python, TypeScript/JavaScript, Java ve .NET projeleri Şalter'da ek elle ayar
yapmadan çalıştırılabilir servis olarak görünsün. Şu an elde gerçek repo yalnızca Go (ve mevcut
Python/TS) için var; Rust, Java, .NET repoları ileride gelecek — en çok Rust bekleniyor.

## Başarı ölçütü

- `classifier-go` taranınca tek bir servis çıkar (launch.json'daki "Run" ve "Debug"
  aynı komuta indiği için birleşir), komutu `go run ./cmd/classifier`, cwd repo kökü;
  Şalter'dan başlatılıp durdurulabilir, portu `lsof` ile görünür.
- Rust/Java/.NET için yaygın proje düzenleri (aşağıda) test fixture'larıyla doğrulanır.
- Mevcut Python ve package.json davranışı değişmez; mevcut testler geçer; daha önce eklenmiş
  servislerin `ServiceSource` değerleri değişmez (yeniden taramada "kaynak kayboldu" olmamalı).

## Kapsam dışı / istenmeyenler

- **Hot reload / watch yok** (Go/Rust/Java/.NET için). Kullanıcı elle restart edecek.
  `supportsReload` bu dillerde `false`.
- Debugger bağlama, `mode: test` / test konfigürasyonları, `preLaunchTask` çalıştırma.
- launch.json'sız Python keşfi (pyproject vb.) — Python launch.json üzerinden zaten çalışıyor.
- Monorepo'da alt dizinlerdeki `package.json`'ları tarama (mevcut davranış korunur).
- Toolchain kurma (`go`, `cargo`, `dotnet`, JDK). Bulunamazsa mevcut "Çalıştırılabilir dosya
  bulunamadı" uyarısı yeterli.
- Kötü sonuç sayılacaklar: aynı servisin hem launch.json'dan hem proje dosyasından iki kez
  çıkması; kütüphane/test paketlerinin servis diye önerilmesi; mevcut servis kimliklerinin
  değişmesi.

## Mimari

İki kaynak, sabit öncelikle:

1. **launch.json** — her dil için tip bazlı çeviri (mevcut `LaunchConfigTranslator` genişler).
2. **Proje dosyası (manifest)** — yeni `ManifestDetector`'lar. Bir ekosistem için launch.json
   en az bir servis ürettiyse o ekosistemin manifest tespiti **çalışmaz** (çift kayıt önlemi).
   Ekosistemler: `go`, `rust`, `node`, `python`, `java`, `dotnet`. launch.json tipi → ekosistem:
   `go`→go, `lldb`/`codelldb`→rust, `node`/`pwa-node`→node, `debugpy`/`python`→python,
   `java`→java, `coreclr`→dotnet.
   - package.json ile launch.json `node` çakışması: package.json servisi her zaman üretilir
     (mevcut `.packageJson(script)` kaynakları korunsun diye). Bir launch.json `node` servisi
     package.json servisiyle **aynı komut + aynı cwd**'ye çıkıyorsa (ör. `wiki-web`:
     `runtimeExecutable: npm`, `runtimeArgs: ["run","dev"]` ↔ `dev` script'i) launch.json servisi
     üretilmez; atlananlara "package.json `<script>` ile aynı" diye eklenir. env/envFile farkı
     bu karşılaştırmaya girmez. Farklı komutlar (`node server.js` vs `npm run dev`) ikisi de kalır.

`RepoScanner.discover` sırası: launch.json → package.json → manifest detector'ları (go, rust,
java, dotnet). Kimlik çakışmaları mevcut `Slug.unique` mantığıyla çözülür.

### `ServiceSource`

Yeni `Kind.manifest`; `name` = `"<ekosistem>:<göreli hedef>"`, örn. `go:cmd/classifier`,
`go:.`, `rust:api/server` (paket/bin), `java:pom.xml`, `dotnet:src/Api/Api.csproj`. Bu değer
yeniden taramalarda eşleştirme anahtarı olduğundan deterministik ve kararlı olmalı.
launch.json kaynakları mevcut `.launchJson(configName)` olarak kalır. Eski config dosyaları
`manifest` içermez, yeni sürüm onları sorunsuz okur. Tersi garanti değil: yeni sürümün yazdığı,
`manifest` kaynağı içeren config'i **eski bir build** okursa decode başarısız olur ve
`ConfigStore` dosyayı `.broken-*` yedeğine taşıyıp varsayılanlara döner. Kabul edilen risk:
kurulu uygulama ve `make run` aynı kaynaktan birlikte yeniden derlenir. İleriye dönük önlem:
`Kind` decode'u bilinmeyen değerlerde tüm config'i düşürmemeli; bilinmeyen kind'lı servis
yok sayılmalı ya da `manual` gibi korunmalı (builder seçer), ki bir sonraki yeni kind'da aynı
sorun olmasın.

### `DiscoveredService` id'si

Mevcut kalıp: `"<repo klasör adı>/<slug>"`. Manifest servislerinde slug, servis adından üretilir
(aşağıda her dil için ad tanımlı).

## launch.json çevirileri

Ortak kurallar (mevcut Python çevirisiyle aynı): `request` `launch` olmalı; `${workspaceFolder}`
dışındaki değişkenler (`${file}`, `${fileDirname}` …) atla; `cwd` yoksa repo kökü; `env` ve
`args` korunur; `envFile` yoksa varsayılan `<repo>/.env` (EnvResolver dosya yoksa ne yapıyorsa
o — mevcut davranış). Konfigürasyon birleştirme (`merge`) tüm tiplere uygulanır: komut, cwd,
envFile, env aynıysa tek servis; ad olarak listedeki ilk konfigürasyonun adı kalır.
`preLaunchTask` olan konfigürasyonlar yine çevrilir (görev çalıştırılmaz); repo uyarılarına
"`<ad>`: preLaunchTask `<görev>` çalıştırılmıyor" eklenir.

### `go`
- `mode` `test` ise atla ("test konfigürasyonu"). `debug`, `auto`, `exec`, yok → kabul.
  `noDebug` önemsiz (iki konfigürasyon birleşir).
- `mode: exec`: `program` derlenmiş binary yoludur → komut `[program] + args`.
- Diğer modlar: `program` bir dizin ya da `.go` dosyası. Komut:
  `["go", "run"] + buildFlags + [göreli program] + args`.
  - Göreli program: `cwd`'ye göre göreli yol, `./` önekiyle (`./cmd/classifier`);
    `program` == `cwd` ise `.`. `cwd` dışındaysa mutlak yol kullan.
  - `buildFlags` string ya da liste olabilir → kelimelere böl (`ShellWords.split`).
- `program` yoksa atla ("program tanımlı değil").
- portHint: `args` içinde `--port`/`-port` (Go flag'leri tek tire de olabilir) ya da `env.PORT`.

### `node` / `pwa-node`
- `runtimeExecutable` varsa (örn. `npm`, `pnpm`, `yarn`, `node`, `tsx`, `ts-node`) komut:
  `[runtimeExecutable] + runtimeArgs + (program varsa [program]) + args`.
- Yoksa `["node"] + runtimeArgs + [program] + args`. `program` da yoksa atla.
- `program` `.ts` ise ve `runtimeExecutable` yoksa: `npx tsx <program>` yerine atla
  ("TypeScript programı için runtimeExecutable gerekli") — builder'a bırakılabilir, ama sessizce
  `node x.ts` üretme.
- portHint: mevcut `--port` arg / `env.PORT` kuralı.

### `lldb` / `codelldb` (Rust)
- `cargo` bloğu varsa: `cargo.args` (örn. `["build", "--bin=server", "--package=api"]`)
  içinden `build`/`test`'i çıkar; `test` ise atla. Kalan `--bin`, `--package`/`-p`,
  `--features`, `--release` gibi bayraklar korunur. Komut:
  `["cargo", "run"] + kalan bayraklar + (args boş değilse ["--"] + args)`.
- `cargo` bloğu yoksa ve `program` derlenmiş binary yoluysa: atla ("cargo bloğu yok; Cargo.toml
  kullanılıyor") — manifest tespiti devreye girsin diye bu bir servis üretmez.

### `java`, `coreclr`
- Doğrudan çalıştırılamaz (Java: classpath'i eklenti çözer; coreclr: `program` önceden
  derlenmiş `.dll`, `preLaunchTask` gerekir). Atla, neden: "proje dosyasından çalıştırılıyor".
  Bu konfigürasyonlar o ekosistem için "servis üretti" sayılmaz → manifest tespiti çalışır.

### `debugpy` / `python`
- Mevcut davranış aynen.

## Proje dosyası tespitleri

Tüm tespitler repo kökünden başlar. Taranmayacak dizinler: gizli dizinler, `vendor`,
`node_modules`, `target`, `build`, `bin`, `obj`, `dist`, `testdata`. Derinlik sınırı builder'ın
kararı (makul: 4).

### Go — `go.mod`
- Kökte `go.mod` yoksa çalışmaz. (Alt dizinlerde ayrı `go.mod`'lu çoklu modül: kapsam dışı.)
- Servis adayları:
  1. `cmd/` altındaki her alt dizin (yalnızca bir seviye, `cmd/<ad>/`) içinde `_test.go` olmayan
     ve `package main` bildiren en az bir `.go` dosyası varsa → servis.
  2. Kökte `package main` bildiren `.go` dosyası varsa → servis `go run .`.
  - `package main` tespiti: dosyanın ilk satırlarından `package` bildirimini oku
    (yorumları/`//go:build` satırlarını geç). Basit satır taraması yeterli.
- Komut: `["go", "run", "./cmd/<ad>"]` / `["go", "run", "."]`, cwd repo kökü,
  envFile `<repo>/.env`.
- Ad: `<ad>` (kök için repo klasör adı). Source name: `go:cmd/<ad>` / `go:.`.
- portHint yok (lsof bulur).

### Rust — `Cargo.toml`
TOML ayrıştırma gerekir. Builder'ın kararı: küçük, yalnızca gereken alt kümeyi okuyan bir
ayrıştırıcı (tablolar `[package]`, `[workspace]`, `[[bin]]`; string, string dizisi; satır içi
tablo/çok satırlı dizi desteği `members` için) ya da hafif bir SPM bağımlılığı. Projede şu an
dış bağımlılık yok; tercih kendi küçük okuyucumuz.
- Kökteki `Cargo.toml`:
  - `[workspace]` varsa `members` dizisindeki her yol (glob `crates/*` gibi basit `*` desenleri
    desteklenmeli) için o paketin `Cargo.toml`'unu işle.
  - `[package]` varsa kökü de bir paket olarak işle.
- Bir paketin binary'leri:
  - `[[bin]]` girdileri (`name`, opsiyonel `path`),
  - `src/main.rs` varsa paket adıyla bir bin (`[[bin]]` aynı adı zaten tanımlıyorsa tekrar
    sayma),
  - `src/bin/*.rs` ve `src/bin/<ad>/main.rs` → dosya/dizin adıyla bin
    (`autobins = false` ise bu otomatik kurallar uygulanmaz).
- Komut:
  - Repoda toplam tek binary varsa: `["cargo", "run"]` (workspace üyesiyse `-p <paket>`).
  - Birden fazlaysa her biri: `["cargo", "run", "-p", "<paket>", "--bin", "<bin>"]`
    (tek paketli repoda `-p` atlanabilir).
- cwd repo kökü, envFile `<repo>/.env`. Ad: bin adı. Source name: `rust:<paket>/<bin>`.
- Kütüphane-only paketler (`src/lib.rs`, bin yok) servis üretmez.

### Java — `pom.xml` / `build.gradle(.kts)`
- Maven (`pom.xml` kökte):
  - Çalıştırıcı: kökte `mvnw` varsa `./mvnw`, yoksa `mvn`.
  - `spring-boot-maven-plugin` geçiyorsa (metin araması yeterli) → `[mvn, "spring-boot:run"]`.
  - Değilse `exec-maven-plugin` geçiyorsa → `[mvn, "exec:java"]`.
  - İkisi de yoksa servis üretme; atlananlara "çalıştırma eklentisi bulunamadı (spring-boot /
    exec)" ekle.
  - Çok modüllü Maven: kapsam dışı, kök pom tek servis.
- Gradle (`build.gradle` veya `build.gradle.kts` kökte, `pom.xml` yoksa):
  - Çalıştırıcı: `gradlew` varsa `./gradlew`, yoksa `gradle`.
  - `org.springframework.boot` plugin'i geçiyorsa → `bootRun`; `application` plugin'i geçiyorsa
    → `run`; ikisi de yoksa atla (aynı mesajla).
- cwd repo kökü, envFile `<repo>/.env`. Ad: `spring-boot`, `bootRun`, `run` veya `exec`
  (hangi görev ise). Source name: `java:pom.xml` / `java:build.gradle`.
- portHint: `src/main/resources/application.properties` içindeki `server.port` ya da
  `application.yml`/`.yaml` içindeki `server:` altındaki `port:`; yoksa Spring Boot ise 8080.
- `./mvnw` / `./gradlew` göreli yolu: komut ilk elemanı `/` içerdiği için `LaunchPlanner`
  bunu dosya yolu kabul eder; mutlak yol (`<repo>/mvnw`) kullan ki varlık kontrolü doğru çalışsın.

### .NET — `*.csproj`
- Repo içinde (dışlanan dizinler hariç) `*.csproj` dosyalarını bul.
- Servis olanlar: `Sdk="Microsoft.NET.Sdk.Web"` (veya `.Worker`) ya da
  `<OutputType>Exe</OutputType>` içerenler; `IsTestProject` true olanlar, adı `Tests`/`.Test`
  ile bitenler ya da `Microsoft.NET.Test.Sdk` referansı olanlar hariç.
- Komut: `["dotnet", "run", "--project", "<göreli csproj yolu>"]`, cwd repo kökü,
  envFile `<repo>/.env`.
- Ad: csproj dosya adı (uzantısız). Source name: `dotnet:<göreli csproj yolu>`.
- portHint: csproj dizinindeki `Properties/launchSettings.json` → ilk `profiles` girdisinin
  `applicationUrl`'indeki ilk URL'nin portu (JSONC olabilir; `JSONCReader` kullan).
- `.sln` ayrıştırma gerekmez.

## Setup kontrolleri

`LaunchPlanner.setupRequirement` mevcut haliyle `go`/`cargo`/`dotnet`/`mvn` PATH'te yoksa
`missingExecutable` verir — yeterli. `./mvnw`/`./gradlew` çalıştırılabilir değilse
`missingExecutable` (mevcut dosya kontrolü). Yeni "fix" komutları (ör. `go mod download`)
eklenmez.

## Arayüz

Ek UI yok. Atlanan konfigürasyonlar mevcut "Atlanan konfigürasyonlar" satırında görünür.
Yeni servisler mevcut "öneri" akışıyla (ConfigMerger suggestions) kullanıcıya sunulur.

## Testler

`Tests/SalterCoreTests` altında, mevcut fixture yaklaşımıyla:
- launch.json: `go` (Run+Debug birleşmesi, `mode: test` atlama, `${fileDirname}` atlama,
  `buildFlags`, `exec` modu), `node`, `lldb` cargo bloğu, `java`/`coreclr` atlama.
- Manifest: Go (cmd/* çoklu, kök main, `_test.go`/kütüphane paketleri hariç), Rust (tek bin,
  `[[bin]]`, `src/bin/*`, workspace + glob, lib-only), Maven/Gradle (spring-boot, application,
  wrapper tercihi, eklenti yoksa atlama, port), .NET (web, exe, test projesi hariç,
  launchSettings portu).
- Öncelik: launch.json go servisi varken go.mod tespiti servis üretmez; java launch.json
  atlandığında pom.xml tespiti çalışır.
- `classifier-go`'nun launch.json'ının birebir kopyası ve `cmd/classifier/main.go`
  içeren bir fixture: tek servis, komut `go run ./cmd/classifier`.

## Builder'a bırakılanlar

Dosya/tip düzeni (ör. ekosistem başına bir detector dosyası), TOML okuyucunun nasıl yazılacağı,
derinlik sınırı, hata/uyarı metinlerinin tam ifadesi.

## Benim (Claude) verdiğim kararlar — kullanıcı onaylamadı, yalnızca genel tabloyu onayladı

- java/coreclr launch.json konfigürasyonlarını atlayıp proje dosyasına düşmek.
- launch.json'ın ekosistem bazında manifest'e baskın gelmesi.
- Maven/Gradle'da hangi görevlerin seçildiği; eklenti yoksa servis üretmemek.
- Rust komut biçimi (tek bin → `cargo run`, çoklu → `-p/--bin`).
- Varsayılan envFile `<repo>/.env` tüm yeni servislerde.
- launch.json `node` servisi package.json ile aynı komuta çıkıyorsa package.json'ın kalması.
- `preLaunchTask` olan konfigürasyonların çevrilip uyarı verilmesi.
- Eski build'lerin yeni config'i okuyamamasının kabul edilmesi.
