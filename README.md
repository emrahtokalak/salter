# Şalter

`~/Projects/acme` altındaki servisleri (FastAPI/uvicorn, Temporal worker'ları, Vite/Next dev
server'ları) VS Code açmadan başlatıp durduran native macOS menu bar + masaüstü uygulaması.
Teknik adı `salter` (paket, bundle id, klasörler); görünen adı **Şalter**.

## Kurulum

    make dist           # imzala + notarize + staple + ~/Applications/Salter.app'e kur
    open ~/Applications/Salter.app

`make dist` için bir kez keychain'e notarization kimliği kaydetmen gerekir:

    make notary-setup   # Apple ID + Team ID + app-specific password sorar
    # app-specific password: https://appleid.apple.com/account/manage

İmza: anahtar zincirinde "Developer ID Application" sertifikası varsa `make app` / `make run`
onunla (`--options runtime` + zaman damgası + `Resources/Salter.entitlements`) imzalar, yoksa
ad-hoc (`-`) imzaya düşer. Elle seçmek için: `make install SIGN_ID=-` veya
`SIGN_ID="Developer ID Application: …"`. İmzayı/notarization'ı doğrulamak için:

    make verify         # codesign --verify + spctl (Gatekeeper) kontrolü

Notarize edilmemiş Developer ID uygulamaları Gatekeeper tarafından reddedilir
(`spctl: rejected, source=Unnotarized Developer ID`). `make dist` bu yüzden submit + staple içerir.

### SDK sürümü (sadece Command Line Tools kuruluysa)

macOS 27 SDK'da `@State` bir macro oldu ve implementasyonu (`SwiftUIMacros`) yalnızca Xcode ile
gelir; Command Line Tools ile derleme `plugin for module 'SwiftUIMacros' not found` hatası verir.
Makefile bu yüzden derlemeyi hâlâ property-wrapper `State` içeren en yeni SDK'ya sabitler:

    SDKROOT ?= $(firstword $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk))

Xcode kuruluysa ya da SDK'yı elle seçmek istersen: `make SDKROOT=/path/to/MacOSX.sdk app`.

Şirket politikası (ör. BeyondTrust) hâlâ engelliyorsa onay gelene kadar geliştirici modunda
çalıştır:

    make run            # release binary'yi arka planda başlatır; log: ~/Library/Logs/Salter/app.log

Bu modda macOS bildirimleri ve "Login'de başlat" kullanılamaz.

Geliştirirken:

    make build          # debug derleme
    make test           # Core testleri (Swift Testing, Xcode gerekmez)
    make run            # release binary'yi arka planda başlat

## Nasıl çalışır

- Servisler `.vscode/launch.json` (debugpy) ve `package.json` (`dev`/`start`) dosyalarından keşfedilir.
- Python servisleri `<repo>/.venv/bin/python` ile, env katmanları VS Code'daki gibi (`.env` + config `env`) çalışır.
- Her servis kendi process group'unda başlar; durdurma tüm gruba SIGTERM, 5 sn sonra SIGKILL gönderir.
- Ayarlar: `~/Library/Application Support/Salter/config.json`
- Loglar: `~/Library/Logs/Salter/`

## Kapsam dışı (v1)

Debugger attach, docker-compose, Makefile target keşfi, compound/grup başlatma, otomatik yeniden başlatma.
