CLT := /Library/Developer/CommandLineTools
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
APP := build/Salter.app
# Signing identity: the first "Developer ID Application" in the keychain, else ad-hoc ("-").
# Override with e.g. `make app SIGN_ID=-`.
SIGN_ID ?= $(or $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $$2; exit}'),-)
SIGN_FLAGS := $(if $(filter -,$(SIGN_ID)),,--options runtime --timestamp)
SIGN := codesign -s '$(SIGN_ID)' --force $(SIGN_FLAGS)

.PHONY: build test run app install icon clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)',)

# Developer mode: runs the release binary directly (no .app bundle). Notifications and
# launch-at-login are unavailable in this mode.
run:
	swift build -c release
	$(SIGN) .build/release/Salter
	mkdir -p $(HOME)/Library/Logs/Salter
	@if pgrep -qf '.build/release/Salter'; then echo 'Şalter zaten çalışıyor'; \
	else nohup .build/release/Salter > $(HOME)/Library/Logs/Salter/app.log 2>&1 & echo 'Şalter başlatıldı'; fi

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Salter $(APP)/Contents/MacOS/Salter
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	$(SIGN) $(APP)

install: app
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/Salter.app
	cp -R $(APP) $(HOME)/Applications/Salter.app

icon:
	rm -rf build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build build
