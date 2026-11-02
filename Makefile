CLT := /Library/Developer/CommandLineTools
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
# The macOS 27 SDK reimplements @State as a macro whose implementation
# (SwiftUIMacros) ships only with Xcode, not with the Command Line Tools, so
# CLT-only builds fail against it. Pin the newest SDK that still uses the
# property-wrapper State. Override with `make SDKROOT=...` (or install Xcode).
SDKROOT ?= $(firstword $(wildcard $(CLT)/SDKs/MacOSX26*.sdk))
SWIFT := $(if $(SDKROOT),env SDKROOT=$(SDKROOT),) swift
APP := build/Salter.app
ENTITLEMENTS := Resources/Salter.entitlements
ZIP := build/Salter.zip
# Keychain profile created once by `make notary-setup` (stores Apple ID + app-specific password).
NOTARY_PROFILE ?= salter-notary
# Signing identity: the first "Developer ID Application" in the keychain, else ad-hoc ("-").
# Override with e.g. `make app SIGN_ID=-`.
SIGN_ID ?= $(or $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $$2; exit}'),-)
SIGN_FLAGS := $(if $(filter -,$(SIGN_ID)),,--options runtime --timestamp)
ENT_FLAG := $(if $(wildcard $(ENTITLEMENTS)),--entitlements '$(ENTITLEMENTS)',)
SIGN := codesign -s '$(SIGN_ID)' --force $(SIGN_FLAGS) $(ENT_FLAG)

.PHONY: build test run app install notary-setup notarize verify dist icon clean

build:
	$(SWIFT) build

test:
	$(SWIFT) test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)',)

# Developer mode: runs the release binary directly (no .app bundle). Notifications and
# launch-at-login are unavailable in this mode.
run:
	$(SWIFT) build -c release
	$(SIGN) .build/release/Salter
	mkdir -p $(HOME)/Library/Logs/Salter
	@if pgrep -qf '.build/release/Salter'; then echo 'Şalter zaten çalışıyor'; \
	else nohup .build/release/Salter > $(HOME)/Library/Logs/Salter/app.log 2>&1 & echo 'Şalter başlatıldı'; fi

app:
	$(SWIFT) build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Salter $(APP)/Contents/MacOS/Salter
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	$(SIGN) $(APP)

install: app _install-app

_install-app:
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/Salter.app
	ditto $(APP) $(HOME)/Applications/Salter.app

# One-time setup: store notarization credentials in the login keychain.
# Prompts for Apple ID, Team ID and an app-specific password
# (create one at https://appleid.apple.com/account/manage).
notary-setup:
	xcrun notarytool store-credentials $(NOTARY_PROFILE)

# Notarize + staple. Needs Developer ID signing (not ad-hoc) and a built app.
notarize: app
	@test '$(SIGN_ID)' != '-' || { echo 'error: notarization needs a Developer ID identity, not ad-hoc (SIGN_ID=-)'; exit 1; }
	@ditto -c -k --keepParent $(APP) $(ZIP)
	xcrun notarytool submit $(ZIP) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(APP)
	@$(MAKE) --no-print-directory verify

verify:
	@echo '--- codesign ---'
	@codesign --verify --deep --strict --verbose=2 $(APP)
	@echo '--- gatekeeper ---'
	@spctl -a -vvv $(APP)

# Full, distributable build: sign, notarize, staple, then install to ~/Applications.
dist: notarize _install-app

icon:
	rm -rf build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build build
