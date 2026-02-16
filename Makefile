# Makefile for XStream project

FLUTTER = flutter
PROJECT_NAME = XStream
APP_NAME := Xstream
ICON_SRC := assets/logo.png
ICON_DST := macos/Runner/Assets.xcassets/AppIcon.appiconset

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
BUILD_ID := $(shell git rev-parse --short HEAD)
BUILD_DATE := $(shell date "+%Y-%m-%d")

DMG_TAG := $(shell git describe --tags --exact-match 2>/dev/null || echo "")
IS_MAIN := $(shell test "$(BRANCH)" = "main" && echo "yes" || echo "no")
DMG_NAME := $(shell \
	if [ "$(IS_MAIN)" = "yes" ]; then \
		if [ "$(DMG_TAG)" != "" ]; then \
			echo "xstream-release-$(DMG_TAG).dmg"; \
		else \
			echo "xstream-latest-$(BUILD_ID).dmg"; \
		fi; \
	else \
		echo "xstream-dev-$(BUILD_ID).dmg"; \
	fi)

.PHONY: all macos-intel macos-arm64 windows-x64 linux-x64 linux-arm64 android-arm64 android-libxray ios-arm64 clean

all: macos-intel macos-arm64 windows-x64 linux-x64 linux-arm64 android-arm64 ios-arm64

define resize_image
	@echo "🖼 生成 $(2) ($(1)x$(1))"
	@if sips -z $(1) $(1) $(ICON_SRC) --out $(2) 2>/dev/null; then \
		echo "✔️ 使用 sips 成功"; \
	elif command -v convert >/dev/null; then \
		echo "⚠️ sips 失败，使用 convert 替代"; \
		convert $(ICON_SRC) -resize $(1)x$(1)\! $(2); \
	else \
		echo "❌ 无法处理图片：请安装 ImageMagick (brew install imagemagick)"; \
		exit 1; \
	fi
endef

windows-icon:
	mkdir -p windows/runner/resources
	magick assets/logo.png -resize 256x256 windows/runner/resources/app_icon.ico
	@echo "✅ Windows app_icon.ico generated"

icon:
	flutter pub run flutter_launcher_icons:main
	@echo "✅ 图标替换完成！"

fix-macos-signing:
	@echo "🧹 Cleaning extended attributes for macOS build..."
	xattr -rc .
	flutter clean
	flutter pub get

macos-intel:
	@if [ "$(UNAME_S)" = "Darwin" ] && [ "$(UNAME_M)" = "x86_64" ]; then \
		echo "Building for macOS (Intel)..."; \
		$(FLUTTER) build macos --release \
			--dart-define=BRANCH_NAME=$(BRANCH) \
			--dart-define=BUILD_ID=$(BUILD_ID) \
			--dart-define=BUILD_DATE=$(BUILD_DATE); \
		brew install create-dmg || true; \
		create-dmg \
			--volname "XStream Installer" \
			--window-pos 200 120 \
			--window-size 800 400 \
			--icon-size 100 \
			--app-drop-link 600 185 \
			build/macos/$(DMG_NAME) \
			build/macos/Build/Products/Release/xstream.app; \
	else \
		echo "Skipping macOS Intel build (not on Intel architecture)"; \
	fi

macos-arm64:
	@if [ "$(UNAME_S)" = "Darwin" ] && [ "$(UNAME_M)" = "arm64" ]; then \
		echo "Building for macOS (ARM64)..."; \
		$(FLUTTER) build macos --release \
			--dart-define=BRANCH_NAME=$(BRANCH) \
			--dart-define=BUILD_ID=$(BUILD_ID) \
			--dart-define=BUILD_DATE=$(BUILD_DATE); \
		brew install create-dmg || true; \
		create-dmg \
			--volname "XStream Installer" \
			--window-pos 200 120 \
			--window-size 800 400 \
			--icon-size 100 \
			--app-drop-link 600 185 \
			build/macos/$(DMG_NAME) \
			build/macos/Build/Products/Release/xstream.app; \
	else \
		echo "Skipping macOS ARM64 build (not on ARM architecture)"; \
	fi

windows-x64:
@if [ "$(UNAME_S)" = "Windows_NT" ] || [ "$(OS)" = "Windows_NT" ]; then \
 echo "Building for Windows (native)..."; \
 flutter pub get; \
 flutter pub outdated; \
 flutter build windows --release; \
 else \
 echo "Windows build only supported on native Windows systems"; \
 fi

linux-x64:
	@if [ "$(UNAME_S)" = "Linux" ]; then \
		echo "Building for Linux x64..."; \
		$(FLUTTER) build linux --release --target-platform=linux-x64; \
		mv build/linux/x64/release/bundle/xstream build/linux/x64/release/bundle/xstream-x64; \
	else \
		echo "Linux x64 build only supported on Linux systems"; \
	fi

linux-arm64:
	@if [ "$(UNAME_S)" = "Linux" ]; then \
		if [ "$(UNAME_M)" = "aarch64" ] || [ "$(UNAME_M)" = "arm64" ]; then \
			echo "Building for Linux arm64..."; \
			$(FLUTTER) build linux --release --target-platform=linux-arm64; \
			mv build/linux/arm64/release/bundle/xstream build/linux/arm64/release/bundle/xstream-arm64; \
		else \
			echo "❌ Cross-build from x64 to arm64 is not supported. Please run this on an arm64 host."; \
			exit 0; \
		fi \
	else \
		echo "Linux arm64 build only supported on Linux systems"; \
	fi

android-arm64:
	@if [ "$(UNAME_S)" = "Linux" ] || [ "$(UNAME_S)" = "Darwin" ]; then \
		echo "Building for Android arm64..."; \
		./build_scripts/build_android_xray.sh; \
		$(FLUTTER) build apk --release; \
	else \
		echo "Android build not supported on this platform"; \
	fi

android-libxray:
	./build_scripts/build_android_xray.sh

ios-arm64:
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		echo "Building for iOS arm64..."; \
		$(FLUTTER) build ios --release --no-codesign; \
		cd build/ios/iphoneos && zip -r xstream.app.zip Runner.app; \
	else \
		echo "iOS build only supported on macOS"; \
	fi

clean:
	echo "Cleaning build outputs..."
	$(FLUTTER) clean
	rm -rf macos/Flutter/ephemeral
	xattr -rc .
