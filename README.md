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
