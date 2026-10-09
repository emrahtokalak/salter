# Şalter

`~/Projects/acme` altındaki servisleri (FastAPI/uvicorn, Temporal worker'ları, Vite/Next dev
server'ları) VS Code açmadan başlatıp durduran native macOS menu bar + masaüstü uygulaması.
Teknik adı `salter` (paket, bundle id, klasörler); görünen adı **Şalter**.

## Kurulum

    make install        # build/Salter.app → ~/Applications/Salter.app (ad-hoc imzalı)
    open ~/Applications/Salter.app

Şirket politikası imzasız `.app` paketini engelliyorsa (ör. BeyondTrust "Local Admin" uyarısı),
onay gelene kadar geliştirici modunda çalıştır:

    make run            # release binary'yi arka planda başlatır; log: ~/Library/Logs/Salter/app.log

Bu modda macOS bildirimleri ve "Login'de başlat" kullanılamaz.

Geliştirirken:

    make build          # debug derleme
    make test           # Core testleri (Swift Testing, Xcode gerekmez)
    swift run Salter

## Nasıl çalışır

- Servisler `.vscode/launch.json` (debugpy) ve `package.json` (`dev`/`start`) dosyalarından keşfedilir.
- Python servisleri `<repo>/.venv/bin/python` ile, env katmanları VS Code'daki gibi (`.env` + config `env`) çalışır.
- Her servis kendi process group'unda başlar; durdurma tüm gruba SIGTERM, 5 sn sonra SIGKILL gönderir.
- Ayarlar: `~/Library/Application Support/Salter/config.json`
- Loglar: `~/Library/Logs/Salter/`

## Kapsam dışı (v1)

Debugger attach, docker-compose, Makefile target keşfi, compound/grup başlatma, otomatik yeniden başlatma.
