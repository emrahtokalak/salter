CLT := /Library/Developer/CommandLineTools
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
APP := build/DevLauncher.app

.PHONY: build test app install icon clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter $(FILTER),)

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
