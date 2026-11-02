# Arayüz yenileme (Linear tarzı) — tasarım

Tarih: 2026-11-02

## Neden

Kullanıcı mevcut arayüzü (ana pencere + menü çubuğu popover'ı) amatör buluyor: varsayılan
SwiftUI kontrolleri, ağır mor arka plan, launch.json'dan gelen "🚀 Debug FastAPI",
"API: uvicorn (debug)", "Run" gibi adlar ve emoji. İstenen: profesyonel, sade, modern —
referans **Linear**.

Şalter'ın debugger desteği yok ve olmayacak; **"Debug" kelimesi arayüzün hiçbir yerinde
görünmemeli.**

Onaylanan görsel taslak: `docs/superpowers/specs/assets/2026-11-02-ui-redesign-mockup.html`
(tarayıcıda açılır). Renkler, aralıklar ve yerleşim için referans budur; birebir piksel
kopyası değil, SwiftUI'de aynı his.

## Hedefler

1. Linear tarzı görsel dil: sakin koyu yüzeyler, ince (1px) ayraçlar, küçük ve net tipografi,
   renk yalnızca durum için, tek birincil eylem.
2. Servis adları: repo adı başlık; gerektiğinde temizlenmiş ayırt edici ek; takma ad.
3. Detay ekranında kaynak tüketimi (CPU, bellek, süreç sayısı, çalışma süresi + son 5 dk grafiği).
4. Okunur loglar: saat ve seviye sütunu, JSON logların tek satıra çevrilmesi.
5. Menü çubuğu popover'ı aynı dilde, sadeleşmiş.

## Kapsam dışı / istenmeyenler

- İşlev değişikliği yok: başlatma/durdurma, keşif, öneri akışı, ayarların anlamı aynı kalır.
- Kaynak tüketimi kenar çubuğunda veya menü çubuğunda **gösterilmez** (yalnızca detay).
- Debugger, "Debug" terimi, emoji.
- Go için `go build` varsayılanı yok (`go run` kalır; kullanıcı komutu Ayarlar'dan değiştirebilir).
- Özel pencere çerçevesi/çizimi yok; standart `NavigationSplitView` + toolbar korunur.
- Kötü sonuç: iki servisin aynı adla görünüp ayırt edilememesi; mor/degrade arka planların kalması;
  her yerde renkli düğmeler.

## Görsel dil

Taslaktaki token'lar (koyu tema):

| Token | Değer | Kullanım |
|---|---|---|
| bg | `#0f1011` | içerik zemini |
| panel | `#141517` | kenar çubuğu |
| line | `#23252a` | 1px ayraçlar, ince çerçeveler |
| selection | `#1f2024` | seçili satır |
| text / text2 / text3 | `#ededed` / `#8a8f98` / `#62666d` | birincil / ikincil / üçüncül metin |
| accent | `#5e6ad2` | tek birincil düğme (Başlat), odak, CPU grafiği |
| ok / warn / err | `#4cb782` / `#f2c94c` / `#eb5757` | çalışıyor / başlıyor-duruyor / çöktü |

- **Açık tema da desteklenir** ve sistem görünümünü takip eder (Claude'un kararı; Linear gibi).
  Açık tema değerleri builder'a bırakılır: aynı hiyerarşi, beyaz/çok açık gri zemin, `#e6e6e6`
  civarı ayraçlar.
- Tipografi: sistem fontu (SF Pro). Gövde 13pt, ikincil 12pt, bölüm başlıkları 11pt medium
  üçüncül renk, detay başlığı 17pt semibold. Komut ve log: SF Mono 11.5–12pt. Sayılar
  `monospacedDigit`.
- Köşe yarıçapı: satırlar 6pt, kartlar 8pt. Düğmeler 28pt yükseklik, ince çerçeve; yalnızca
  birincil eylem (Başlat) dolu accent.
- Durum noktası 7pt; çalışırken hafif halka (glow).
- Mevcut mor degrade/vibrancy arka planı kaldırılır.

## Adlandırma

`ServiceConfig` için görüntü adı hesaplayan saf bir fonksiyon (SalterCore'da, test edilebilir):

1. Kullanıcı takma ad verdiyse (`overrides.name`) → aynen o.
2. Repoda bu servisten başka servis yoksa → repo klasör adı (`classifier-go`).
3. Birden çok servis varsa → `"<repo> · <ek>"`; ek = keşfedilen adın temizlenmiş hali.
   Kenar çubuğunda repo grubu altında yalnızca ek gösterilir ("BFF").
4. Temizleme: emoji ve simge karakterleri, "Debug"/"Run" kelimeleri (büyük-küçük harf
   duyarsız, tek başına kelime olarak; parantez içi "(debug)" dahil), baştaki/sondaki
   ayırıcılar (`:` `-` `·` boşluk) atılır. Sonuç boşsa ek olarak sıra numarası kullanılır
   ("storefront · 2"). Örnekler: "🚀 Debug FastAPI" → "FastAPI", "Debug BFF" → "BFF",
   "API: uvicorn (debug)" → "API: uvicorn", "Run" → "" (tek servisse zaten repo adı).
5. Aynı repoda temizlenmiş ekler çakışırsa sıra numarası eklenir ("FastAPI", "FastAPI 2").
6. Farklı repolardaki iki servisin tam görüntü adı aynı çıkarsa (aynı klasör adlı iki repo,
   ya da başka bir servisle aynı takma ad), her birine üst klasör adı eklenir:
   `"api (acme)"` / `"api (personal)"`. Bu yüzden fonksiyon tüm `AppConfig`'i görür.
7. Manuel servisler (`source.kind == .manual`): kullanıcının yazdığı ad (`discovered.name`)
   takma ad gibi aynen kullanılır, temizlenmez.

Fonksiyon bağlama göre üç değer verir: **tam ad** (Sabitlenenler, menü çubuğu, detay başlığı,
öneri sayfaları), **grup içi ad** (Repolar altında servis satırı: ek ya da takma ad) ve
**grup başlığı** (repo adı).

**Takma ad:** kenar çubuğunda sağ tık → "Yeniden adlandır" (satır içi düzenleme ya da küçük
popover; builder seçer) ve Ayarlar sekmesindeki "Ad" alanı. Boş bırakmak takma adı kaldırır.
Mevcut `overrides.name` alanı kullanılır; yeni config alanı yok. (Not: bugün kullanıcının
verdiği bir ad varsa takma ad sayılır — doğru davranış.)

"Debug" geçen başka metin varsa (ör. menü, yardım) değiştirilir.

## Ana pencere

### Kenar çubuğu
- "Sabitlenenler" bölümü: düz liste, satır = durum noktası + görüntü adı + port (varsa,
  üçüncül renk, `:8080`).
- "Repolar" bölümü: birden çok servisli repo açılır/kapanır grup olur; grup satırında repo
  adı (ikincil renk), altında servis satırları (grup içi adlarıyla). **Tek servisli repo grup
  değil, düz bir servis satırıdır** (repo adıyla). Sabitlenmiş servisler bugünkü gibi yalnızca
  "Sabitlenenler"de görünür, Repolar altında tekrar edilmez (seçim kimlikleri tekil kalır). Mevcut repo bağlam menüsü (keşfedilen servisler,
  manuel servis, Finder'da göster, repoyu kaldır) korunur; bölüm başlığında "+" (repo ekle).
- Satırlarda oynat/durdur düğmesi kalıcı olarak gösterilmez; hover'da görünebilir (builder),
  sağ tık menüsü korunur.
- "N yeni repo bulundu" bildirimi kenar çubuğunun altında küçük, çerçeveli bir kart
  ("İncele →").

### Detay başlığı
- Üstte üçüncül renkli konum satırı: `<taranan kök klasör adı> / <repo>`.
- Satır: görüntü adı (17pt semibold) · durum etiketi (pill: "Çalışıyor · 4 dk", "Durdu",
  "Başlatılıyor…", "Çöktü (kod)") · port düğmesi (`localhost:8080 ↗`, tarayıcıda açar) ·
  sağda eylemler. Çalışırken: "Yeniden başlat", "Durdur" (ince çerçeveli); dururken: dolu
  accent "Başlat". Sabitle düğmesi ikon olarak kalır.
- Altında komut (SF Mono, ikincil renk, seçilebilir).
- Kaynak kartları (aşağıda).
- Sekmeler: "Log", "Ayarlar" — alt çizgili sekme stili (segmented control değil).

### Kaynak kartları (yalnızca detay)
- Dört kart: **CPU** (yüzde + son 5 dk çizgi grafiği), **Bellek** (MB/GB + grafik),
  **Süreçler** (sayı + ana PID), **Çalışma süresi**.
- Değerler servisin **tüm süreç grubunun** toplamıdır (`go run`'ın başlattığı binary, `npm`'in
  başlattığı vite vb. dahil). Süreç grubu kimliği `ServiceSupervisor.pgid`.
- Örnekleme: ~2 sn aralıkla; son 5 dk tutulur (~150 örnek). CPU yüzdesi iki örnek arasındaki
  toplam CPU süresi farkı / geçen duvar saati (tek çekirdek = %100; çok çekirdekte %100'ü
  geçebilir — Activity Monitor ile aynı). Bellek = süreçlerin resident size toplamı.
- Yöntem builder'a bırakılır; tercih: `libproc` (`proc_listpgrppids` / `proc_listpids` ile
  gruptaki pid'ler, `proc_pidinfo(PROC_PIDTASKINFO)` ile CPU zamanı ve RSS) — `ps`'i her
  2 sn'de çalıştırmak yerine. Hesaplama mantığı SalterCore'da, test edilebilir olmalı.
- Servis çalışmıyorsa kartlar "—" gösterir (gizlenmez, yerleşim zıplamasın). Sahiplenilmiş
  (adopted) servislerde de çalışır.
- Örnekleme yalnızca servis aktifken yapılır; detay görünür değilken de sürebilir (grafik
  geçmişi dolu kalsın) — builder pil/performans açısından makul olanı seçer, ama en azından
  seçili servis için geçmiş tutulmalı.

### Log sekmesi
- Araç çubuğu: arama alanı, "Otomatik kaydır" anahtarı, satır sayısı, "Log dosyası",
  "Temizle" — küçük, sade düğmeler.
- Satır biçimi: `HH:mm:ss` (üçüncül) · seviye sütunu (INFO mavi-gri, WARN sarı, ERROR kırmızı,
  DEBUG/TRACE üçüncül; seviye yoksa boş) · mesaj.
- JSON satırları (`{` ile başlayan geçerli JSON nesnesi): mesaj alanı (`message` / `msg`),
  seviye alanı (`level` / `log_level` / `severity`), zaman alanı (`@timestamp` / `timestamp` /
  `time` / `ts`) ayıklanır; kalan alanlar mesajdan sonra üçüncül renkte `key=value` olarak.
  Gürültü alanları (`logger`, `service`, `event_type` gibi mesajla aynı olanlar) builder
  takdirine; en azından mesajla aynı değere sahip alanlar tekrar edilmez.
- Saat: JSON'da zaman alanı varsa o (yerel saate çevrilmiş), yoksa satırın alındığı zaman
  (`LogLine.date`).
- **Düz metin satırları da** saat ve seviye sütunu alır: saat = alındığı zaman; seviye basit
  kalıplarla tanınır — baştaki `INFO:` (uvicorn), `[INFO]`, logfmt `level=info`, satırın ilk
  ~60 karakterinde tek başına geçen `INFO`/`WARN`/`WARNING`/`ERROR`/`DEBUG`/`TRACE`
  (Spring Boot). Tanınmazsa seviye boş, metin aynen (ANSI korunur). Logfmt satırları
  (`time=… level=… msg=…`, Go slog metin çıktısı) JSON gibi ele alınır: `msg` mesaj, `time`
  saat, kalanlar `key=value`. Diğer düz metin satırlarında satırın kendi zaman damgası
  silinmez.
- Sistem satırları ("başlatılıyor", "durduruldu") ortada, üçüncül renkte ince ayraç gibi.
- Arama ham metin üzerinde çalışır; log dosyası ham kalır (dosya biçimi değişmez).
- Mevcut ANSI renk işleme korunur (JSON olmayan satırlar).
- Ayrıştırma SalterCore'da saf fonksiyon, test edilebilir.

### Ayarlar sekmesi
- Aynı işlev, form yerine Linear tarzı gruplanmış alanlar: Genel (Ad = takma ad, Komut,
  Çalışma klasörü, Port, reload anahtarı), Ortam değişkenleri, tehlikeli bölge (Servisi kaldır).
  Kaydet düğmesi tek birincil eylem.

## Menü çubuğu popover'ı
- Başlık: "Şalter" + sağda "N çalışıyor".
- Satır: durum noktası · görüntü adı · port · tek eylem (çalışıyorsa durdur ■, duruyorsa
  başlat ▶, çöktüyse yeniden başlat ↻). Log ikonu kaldırılır; satıra tıklamak ana pencerede
  o servisi açar.
- Alt bar: "Pencereyi aç", "Tümünü durdur", "Çık" — sade metin düğmeleri.
- Genişlik ~320pt; mor zemin yok.

## Diğer ekranlar
Repo önerileri sayfaları, manuel servis sayfası ve uygulama Ayarlar penceresi aynı görsel
dile uyarlanır; içerik/işlev değişmez. Buralarda da servis adları görüntü adı kuralını kullanır
ve "Debug" görünmez.

## Testler
- SalterCore birim testleri: görüntü adı (tek/çok servis, takma ad, temizleme örnekleri,
  çakışma, boş sonuç), JSON log ayrıştırma (alan varyantları, geçersiz JSON, iç içe değerler),
  kaynak örnekleyici hesapları (CPU yüzdesi delta hesabı, RSS toplamı, süreç kaybolması,
  5 dk pencere kırpma) — sistem çağrısı soyutlanarak.
- Görsel doğrulama: uygulamayı çalıştırıp ekran görüntüsüyle taslakla karşılaştırma
  (koyu ve açık tema).

## Builder'a bırakılanlar
SwiftUI bileşen yapısı, açık tema renkleri, hover davranışları, grafik çizimi (Swift Charts veya
`Path`), takma ad düzenleme etkileşimi, örnekleme mimarisi (hangi actor, ne zaman).

## Claude'un verdiği kararlar (kullanıcı genel tabloyu onayladı, bunları tek tek değil)
- Açık temayı da desteklemek, sistemi takip etmek.
- Sağ tık "Yeniden adlandır" + Ayarlar'daki Ad alanı = takma ad (`overrides.name`).
- Ek çakışmasında ve boş ekte sıra numarası.
- JSON log biçimlendirmesi ve alan adı listeleri.
- Kaynak kartlarında süreç grubu toplamı ve 2 sn / 5 dk değerleri.
- Menü çubuğunda log ikonunun kaldırılıp satıra tıklamanın pencereyi açması.
- Düz metin loglarda seviye tanıma kalıpları ve logfmt'nin JSON gibi ayrıştırılması.
- Sabitlenmiş servislerin Repolar altında tekrar edilmemesi; tek servisli reponun düz satır olması.
- Repolar arası ad çakışmasında üst klasör adının eklenmesi; manuel servis adının takma ad sayılması.
