# Makefile for XStream project

FLUTTER = flutter
PROJECT_NAME = XStream
APP_NAME := Xstream
ICON_SRC := assets/logo.png
ICON_DST := macos/Runner/Assets.xcassets/AppIcon.appiconset
MACOS_APP_BUNDLE := build/macos/Build/Products/Release/xstream.app
MACOS_BUILD_LOCK_DIR := build/.macos-build.lock
MACOS_BUILD_LOCK_PID_FILE := $(MACOS_BUILD_LOCK_DIR)/pid

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

.PHONY: all macos-intel macos-arm64 macos-debug-run macos-vendor-xray windows-x64 linux-x64 linux-arm64 android-arm64 android-libxray ios-arm64 ios-install-debug ios-install-release xcode-debug-bootstrap xcode-mcp-doctor xstream-mcp-install xstream-mcp-start xstream-mcp-start-dev xstream-mcp-start-runtime clean

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
		set -e; \
		echo "Building for macOS (Intel)..."; \
		if [ "$$(id -u)" = "0" ]; then \
			if [ "$$XSTREAM_SUDO_DELEGATED" = "1" ]; then \
				echo "❌ Failed to switch from root to regular user. Please run build as a regular user shell."; \
				exit 1; \
			fi; \
			if [ -z "$$SUDO_USER" ]; then \
				echo "❌ Root shell detected without SUDO_USER. Please run: sudo make macos-intel (from a regular user)."; \
				exit 1; \
			fi; \
			echo "↪ Detected sudo mode. Switching build to user: $$SUDO_USER"; \
			for path in macos/Flutter/ephemeral ios/Flutter/ephemeral linux/flutter/ephemeral windows/flutter/ephemeral .dart_tool build; do \
				if [ -e "$$path" ]; then \
					chown -R "$$SUDO_USER" "$$path" || true; \
				fi; \
			done; \
			exec sudo -H -u "$$SUDO_USER" env XSTREAM_SUDO_DELEGATED=1 PATH="$$PATH" make macos-intel; \
		fi; \
		if ! mkdir "$(MACOS_BUILD_LOCK_DIR)" 2>/dev/null; then \
			lock_pid=""; \
			stale_lock=0; \
			if [ -f "$(MACOS_BUILD_LOCK_PID_FILE)" ]; then \
				lock_pid="$$(cat "$(MACOS_BUILD_LOCK_PID_FILE)" 2>/dev/null || true)"; \
				if [ -n "$$lock_pid" ] && ! kill -0 "$$lock_pid" 2>/dev/null; then \
					stale_lock=1; \
				fi; \
			else \
				stale_lock=1; \
			fi; \
			if [ "$$stale_lock" = "1" ]; then \
				echo "⚠️ Detected stale macOS build lock. Auto-cleaning: $(MACOS_BUILD_LOCK_DIR)"; \
				rm -f "$(MACOS_BUILD_LOCK_PID_FILE)" >/dev/null 2>&1 || true; \
				rmdir "$(MACOS_BUILD_LOCK_DIR)" >/dev/null 2>&1 || true; \
				if ! mkdir "$(MACOS_BUILD_LOCK_DIR)" 2>/dev/null; then \
					echo "❌ Another macOS build is already running (lock: $(MACOS_BUILD_LOCK_DIR))."; \
					echo "   Wait for it to finish, then retry."; \
					exit 1; \
				fi; \
			else \
				echo "❌ Another macOS build is already running (lock: $(MACOS_BUILD_LOCK_DIR))."; \
				if [ -n "$$lock_pid" ]; then \
					echo "   Active build PID: $$lock_pid"; \
				fi; \
				echo "   Wait for it to finish, or remove lock after confirming no build process is active."; \
				exit 1; \
			fi; \
		fi; \
		echo "$$$$" > "$(MACOS_BUILD_LOCK_PID_FILE)"; \
		trap 'rm -f "$(MACOS_BUILD_LOCK_PID_FILE)" >/dev/null 2>&1 || true; rmdir "$(MACOS_BUILD_LOCK_DIR)" >/dev/null 2>&1 || true' EXIT INT TERM; \
		if ! command -v pod >/dev/null 2>&1; then \
			echo "❌ CocoaPods not installed or not in a valid state. Install with: brew install cocoapods"; \
			exit 1; \
		fi; \
		if ! pod --version >/dev/null 2>&1; then \
			echo "❌ CocoaPods command exists but failed. Reinstall with: brew reinstall cocoapods"; \
			exit 1; \
		fi; \
		./build_scripts/build_macos_xray_from_vendor.sh; \
		$(FLUTTER) build macos --release \
			--dart-define=BRANCH_NAME=$(BRANCH) \
			--dart-define=BUILD_ID=$(BUILD_ID) \
			--dart-define=BUILD_DATE=$(BUILD_DATE); \
		if [ ! -d "$(MACOS_APP_BUNDLE)" ]; then \
			echo "❌ Build finished but app bundle was not found: $(MACOS_APP_BUNDLE)"; \
			exit 1; \
		fi; \
		./scripts/install-runtime-mcp.sh "$(MACOS_APP_BUNDLE)" amd64; \
			if ! command -v create-dmg >/dev/null 2>&1; then \
				echo "❌ create-dmg not found. Install with: brew install create-dmg"; \
				exit 1; \
			fi; \
			rm -f "build/macos/$(DMG_NAME)" "build/macos"/rw.*."$(DMG_NAME)" || true; \
			create-dmg \
				--no-internet-enable \
				--skip-jenkins \
				--hdiutil-retries 10 \
				--volname "XStream Installer" \
				--window-pos 200 120 \
				--window-size 800 400 \
			--icon-size 100 \
			--app-drop-link 600 185 \
			build/macos/$(DMG_NAME) \
			$(MACOS_APP_BUNDLE); \
	else \
		echo "Skipping macOS Intel build (not on Intel architecture)"; \
	fi

macos-arm64:
	@if [ "$(UNAME_S)" = "Darwin" ] && [ "$(UNAME_M)" = "arm64" ]; then \
		set -e; \
		echo "Building for macOS (ARM64)..."; \
		if [ "$$(id -u)" = "0" ]; then \
			if [ "$$XSTREAM_SUDO_DELEGATED" = "1" ]; then \
				echo "❌ Failed to switch from root to regular user. Please run build as a regular user shell."; \
				exit 1; \
			fi; \
			if [ -z "$$SUDO_USER" ]; then \
				echo "❌ Root shell detected without SUDO_USER. Please run: sudo make macos-arm64 (from a regular user)."; \
				exit 1; \
			fi; \
			echo "↪ Detected sudo mode. Switching build to user: $$SUDO_USER"; \
			for path in macos/Flutter/ephemeral ios/Flutter/ephemeral linux/flutter/ephemeral windows/flutter/ephemeral .dart_tool build; do \
				if [ -e "$$path" ]; then \
					chown -R "$$SUDO_USER" "$$path" || true; \
				fi; \
			done; \
			exec sudo -H -u "$$SUDO_USER" env XSTREAM_SUDO_DELEGATED=1 PATH="$$PATH" make macos-arm64; \
		fi; \
		if ! mkdir "$(MACOS_BUILD_LOCK_DIR)" 2>/dev/null; then \
			lock_pid=""; \
			stale_lock=0; \
			if [ -f "$(MACOS_BUILD_LOCK_PID_FILE)" ]; then \
				lock_pid="$$(cat "$(MACOS_BUILD_LOCK_PID_FILE)" 2>/dev/null || true)"; \
				if [ -n "$$lock_pid" ] && ! kill -0 "$$lock_pid" 2>/dev/null; then \
					stale_lock=1; \
				fi; \
			else \
				stale_lock=1; \
			fi; \
			if [ "$$stale_lock" = "1" ]; then \
				echo "⚠️ Detected stale macOS build lock. Auto-cleaning: $(MACOS_BUILD_LOCK_DIR)"; \
				rm -f "$(MACOS_BUILD_LOCK_PID_FILE)" >/dev/null 2>&1 || true; \
				rmdir "$(MACOS_BUILD_LOCK_DIR)" >/dev/null 2>&1 || true; \
				if ! mkdir "$(MACOS_BUILD_LOCK_DIR)" 2>/dev/null; then \
					echo "❌ Another macOS build is already running (lock: $(MACOS_BUILD_LOCK_DIR))."; \
					echo "   Wait for it to finish, then retry."; \
					exit 1; \
				fi; \
			else \
				echo "❌ Another macOS build is already running (lock: $(MACOS_BUILD_LOCK_DIR))."; \
				if [ -n "$$lock_pid" ]; then \
					echo "   Active build PID: $$lock_pid"; \
				fi; \
				echo "   Wait for it to finish, or remove lock after confirming no build process is active."; \
				exit 1; \
			fi; \
		fi; \
		echo "$$$$" > "$(MACOS_BUILD_LOCK_PID_FILE)"; \
		trap 'rm -f "$(MACOS_BUILD_LOCK_PID_FILE)" >/dev/null 2>&1 || true; rmdir "$(MACOS_BUILD_LOCK_DIR)" >/dev/null 2>&1 || true' EXIT INT TERM; \
		if ! command -v pod >/dev/null 2>&1; then \
			echo "❌ CocoaPods not installed or not in a valid state. Install with: brew install cocoapods"; \
			exit 1; \
		fi; \
		if ! pod --version >/dev/null 2>&1; then \
			echo "❌ CocoaPods command exists but failed. Reinstall with: brew reinstall cocoapods"; \
			exit 1; \
		fi; \
		./build_scripts/build_macos_xray_from_vendor.sh; \
		$(FLUTTER) build macos --release \
			--dart-define=BRANCH_NAME=$(BRANCH) \
			--dart-define=BUILD_ID=$(BUILD_ID) \
			--dart-define=BUILD_DATE=$(BUILD_DATE); \
			if [ ! -d "$(MACOS_APP_BUNDLE)" ]; then \
				echo "❌ Build finished but app bundle was not found: $(MACOS_APP_BUNDLE)"; \
				exit 1; \
			fi; \
			if [ -f "$(MACOS_APP_BUNDLE)/Contents/Resources/xray-x86_64" ]; then \
				echo "Pruning non-target xray binary from ARM64 package: xray-x86_64"; \
				rm -f "$(MACOS_APP_BUNDLE)/Contents/Resources/xray-x86_64"; \
			fi; \
			if [ -f "$(MACOS_APP_BUNDLE)/Contents/Resources/xray.x86_64" ]; then \
				echo "Pruning non-target xray binary from ARM64 package: xray.x86_64"; \
				rm -f "$(MACOS_APP_BUNDLE)/Contents/Resources/xray.x86_64"; \
			fi; \
			./scripts/install-runtime-mcp.sh "$(MACOS_APP_BUNDLE)" arm64; \
				if ! command -v create-dmg >/dev/null 2>&1; then \
					echo "❌ create-dmg not found. Install with: brew install create-dmg"; \
					exit 1; \
				fi; \
			rm -f "build/macos/$(DMG_NAME)" "build/macos"/rw.*."$(DMG_NAME)" || true; \
			create-dmg \
				--no-internet-enable \
				--skip-jenkins \
				--hdiutil-retries 10 \
				--volname "XStream Installer" \
				--window-pos 200 120 \
				--window-size 800 400 \
			--icon-size 100 \
			--app-drop-link 600 185 \
			build/macos/$(DMG_NAME) \
			$(MACOS_APP_BUNDLE); \
	else \
		echo "Skipping macOS ARM64 build (not on ARM architecture)"; \
	fi

macos-debug-run:
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		echo "Run XStream on macOS (debug, no resident)..."; \
		$(FLUTTER) run -d macos --debug --no-resident; \
	else \
		echo "macOS debug run is only supported on macOS"; \
	fi

macos-vendor-xray:
	./build_scripts/build_macos_xray_from_vendor.sh

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

ios-install-debug:
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		DEVICE_ID="$${IOS_DEVICE:-$$(flutter devices | awk -F'•' '/• ios •/ && first=="" {gsub(/ /,"",$$2); first=$$2} END {print first}')}"; \
		if [ -z "$$DEVICE_ID" ]; then \
			echo "❌ No iOS device found. Connect an iPhone or set IOS_DEVICE=<udid>."; \
			exit 1; \
		fi; \
		echo "Installing debug build to iOS device: $$DEVICE_ID"; \
		if [ "$${IOS_NO_RESIDENT:-0}" = "1" ]; then \
			$(FLUTTER) run -d "$$DEVICE_ID" --debug --no-resident; \
		else \
			$(FLUTTER) run -d "$$DEVICE_ID" --debug; \
		fi; \
	else \
		echo "iOS install is only supported on macOS"; \
	fi

ios-install-release:
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		DEVICE_ID="$${IOS_DEVICE:-$$(flutter devices | awk -F'•' '/• ios •/ && first=="" {gsub(/ /,"",$$2); first=$$2} END {print first}')}"; \
		if [ -z "$$DEVICE_ID" ]; then \
			echo "❌ No iOS device found. Connect an iPhone or set IOS_DEVICE=<udid>."; \
			exit 1; \
		fi; \
		echo "Installing release build to iOS device: $$DEVICE_ID"; \
		$(FLUTTER) run -d "$$DEVICE_ID" --release --no-resident; \
	else \
		echo "iOS install is only supported on macOS"; \
	fi

xcode-debug-bootstrap:
	./scripts/xcode-debug-bootstrap.sh

xcode-mcp-doctor:
	./scripts/xcode-debug-bootstrap.sh
	@echo "Xcode MCP workspace paths (recommended):"
	@echo "  iOS:   $(PWD)/ios/Runner.xcworkspace"
	@echo "  macOS: $(PWD)/macos/Runner.xcworkspace"
	@echo "Note: building .xcodeproj directly may miss CocoaPods plugin modules."

xstream-mcp-install:
	cd tools/xstream-mcp-server && go mod tidy

xstream-mcp-start:
	./scripts/start-xstream-dev-mcp-server.sh

xstream-mcp-start-dev:
	./scripts/start-xstream-dev-mcp-server.sh

xstream-mcp-start-runtime:
	./scripts/start-xstream-runtime-mcp-server.sh

clean:
	echo "Cleaning build outputs..."
	$(FLUTTER) clean
	rm -rf macos/Flutter/ephemeral
	xattr -rc .
