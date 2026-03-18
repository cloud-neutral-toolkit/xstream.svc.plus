.DEFAULT_GOAL := help

FLUTTER ?= flutter
POD ?= pod
IOS_DEVICE ?=
IOS_NO_RESIDENT ?= 0
MCP_MODE ?= dev
XCODE_DERIVED_DATA ?= $(HOME)/Library/Developer/Xcode/DerivedData

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

MAKE_SCRIPT_DIR := scripts/make
RUN_TARGET_SCRIPT := $(MAKE_SCRIPT_DIR)/run-target.sh

BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
BUILD_ID := $(shell git rev-parse --short HEAD)
BUILD_DATE := $(shell date "+%Y-%m-%d")

MACOS_APP_BUNDLE := build/macos/Build/Products/Release/xstream.app
MACOS_BUILD_LOCK_DIR := build/.macos-build.lock
MACOS_BUILD_LOCK_PID_FILE := $(MACOS_BUILD_LOCK_DIR)/pid

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

COMMON_ENV := FLUTTER="$(FLUTTER)" BRANCH="$(BRANCH)" BUILD_ID="$(BUILD_ID)" BUILD_DATE="$(BUILD_DATE)"
MACOS_ENV := UNAME_S="$(UNAME_S)" UNAME_M="$(UNAME_M)" $(COMMON_ENV) DMG_NAME="$(DMG_NAME)" MACOS_APP_BUNDLE="$(MACOS_APP_BUNDLE)" MACOS_BUILD_LOCK_DIR="$(MACOS_BUILD_LOCK_DIR)" MACOS_BUILD_LOCK_PID_FILE="$(MACOS_BUILD_LOCK_PID_FILE)"
WINDOWS_ENV := UNAME_S="$(UNAME_S)" OS="$(OS)" $(COMMON_ENV)
LINUX_ENV := UNAME_S="$(UNAME_S)" UNAME_M="$(UNAME_M)" $(COMMON_ENV)
IOS_ENV := UNAME_S="$(UNAME_S)" FLUTTER="$(FLUTTER)" IOS_DEVICE="$(IOS_DEVICE)" IOS_NO_RESIDENT="$(IOS_NO_RESIDENT)" BRANCH="$(BRANCH)" BUILD_ID="$(BUILD_ID)" BUILD_DATE="$(BUILD_DATE)"
ANDROID_ENV := UNAME_S="$(UNAME_S)" FLUTTER="$(FLUTTER)" BRANCH="$(BRANCH)" BUILD_ID="$(BUILD_ID)" BUILD_DATE="$(BUILD_DATE)"
MCP_ENV := MCP_MODE="$(MCP_MODE)" FLUTTER="$(FLUTTER)" BRANCH="$(BRANCH)" BUILD_ID="$(BUILD_ID)" BUILD_DATE="$(BUILD_DATE)"

define run_target
	@$(strip $(1)) $(RUN_TARGET_SCRIPT) $(2)
endef

.PHONY: \
	help clean icon \
	build-all build-desktop build-mobile \
	build-macos build-macos-x64 build-macos-arm64 \
	run-macos-debug fix-macos-signing sync-macos-config reset-macos-xcode-version \
	build-windows build-windows-x64 build-windows-icon \
	build-linux build-linux-x64 build-linux-arm64 package-linux-deb package-linux-rpm package-linux-all \
	build-windows-single-file \
	build-ios build-ios-app build-ios-ipa install-ios-debug install-ios-release deploy-ios-device \
	build-android build-android-apk build-android-libxray \
	mcp mcp-bootstrap mcp-doctor mcp-install mcp-start-dev mcp-start-runtime

help:
	@printf "Xstream build metadata: branch=%s build=%s date=%s\n\n" "$(BRANCH)" "$(BUILD_ID)" "$(BUILD_DATE)"
	@printf '%s\n' \
		'Usage: make <target>' \
		'' \
		'Build' \
		'  build-all                 Build all supported desktop and mobile targets' \
		'  build-desktop             Build macOS, Windows, and Linux targets' \
		'  build-mobile              Build iOS and Android targets' \
		'' \
		'macOS' \
		'  build-macos               Build all macOS release targets supported on the host' \
		'  build-macos-x64           Build the macOS x64 release app and DMG on Intel Mac' \
		'  build-macos-arm64         Build the macOS ARM64 release app and DMG on Apple Silicon' \
		'  run-macos-debug           Launch the macOS app in Flutter debug mode' \
		'  fix-macos-signing         Reset macOS signing-related state before a fresh build' \
		'  sync-macos-config         Sync pubspec.yaml version → Generated.xcconfig (run before Xcode Archive)' \
		'  reset-macos-xcode-version Clean Flutter/Xcode caches, resync version config, and reinstall macOS pods' \
		'' \
		'Windows' \
		'  build-windows             Build all Windows targets supported on the host' \
		'  build-windows-x64         Build the Windows x64 release bundle on native Windows' \
		'  build-windows-single-file Build a single-file Windows launcher that self-extracts the runtime' \
		'  build-windows-icon        Regenerate the Windows .ico asset' \
		'' \
		'Linux' \
		'  build-linux               Build all Linux targets supported on the host' \
		'  build-linux-x64           Build the Linux x64 release bundle on Linux' \
		'  build-linux-arm64         Build the Linux ARM64 release bundle on Linux ARM64' \
		'  package-linux-deb         Build Linux x64 release and package a .deb' \
		'  package-linux-rpm         Build Linux x64 release and package a .rpm' \
		'  package-linux-all         Build Linux x64 release and package both .deb and .rpm' \
		'' \
		'iOS' \
		'  build-ios                 Build the iOS app bundle and IPA on macOS' \
		'  build-ios-app             Build the iOS release Runner.app bundle and zip payload' \
		'  build-ios-ipa             Build the iOS release IPA package' \
		'  install-ios-debug         Install a debug build to an attached iPhone' \
		'  install-ios-release       Build and install a release build to an attached iPhone' \
		'  deploy-ios-device         Run the custom iOS device deployment helper' \
		'' \
		'Android' \
		'  build-android             Build Android release artifacts' \
		'  build-android-apk         Build the Android release APK' \
		'  build-android-libxray     Build Android libxray artifacts only' \
		'' \
		'Utility' \
		'  icon                      Regenerate application icons for Flutter targets' \
		'  clean                     Clean Flutter and generated build outputs'

clean:
	$(call run_target,FLUTTER="$(FLUTTER)",clean)

icon:
	$(call run_target,FLUTTER="$(FLUTTER)",icon)

build-all:
	@$(MAKE) 'build-desktop' 'build-mobile'

build-desktop:
	@$(MAKE) 'build-macos' 'build-windows' 'build-linux'

build-mobile:
	@$(MAKE) 'build-ios' 'build-android'

build-macos:
	@$(MAKE) 'build-macos-x64' 'build-macos-arm64'

build-macos-x64:
	$(call run_target,$(MACOS_ENV),macos-intel)

build-macos-arm64:
	$(call run_target,$(MACOS_ENV),macos-arm64)

run-macos-debug:
	$(call run_target,UNAME_S="$(UNAME_S)" FLUTTER="$(FLUTTER)" BRANCH="$(BRANCH)" BUILD_ID="$(BUILD_ID)" BUILD_DATE="$(BUILD_DATE)",macos-debug-run)

fix-macos-signing:
	$(call run_target,FLUTTER="$(FLUTTER)",fix-macos-signing)

sync-macos-config:
	$(call run_target,FLUTTER="$(FLUTTER)",sync-macos-config)

reset-macos-xcode-version:
	"$(FLUTTER)" clean
	rm -rf macos/Flutter/generated
	rm -rf macos/Flutter/ephemeral
	rm -rf ios/Flutter/ephemeral
	rm -rf "$(XCODE_DERIVED_DATA)"/*
	"$(FLUTTER)" pub get
	@$(MAKE) sync-macos-config
	"$(POD)" install --project-directory=macos

build-windows:
	@$(MAKE) 'build-windows-x64'

build-windows-x64:
	$(call run_target,$(WINDOWS_ENV),windows-x64)

build-windows-single-file:
	$(call run_target,$(WINDOWS_ENV),windows-single-file)

build-windows-icon:
	$(call run_target,$(COMMON_ENV),windows-icon)

build-linux:
	@$(MAKE) 'build-linux-x64' 'build-linux-arm64'

build-linux-x64:
	$(call run_target,$(LINUX_ENV),linux-x64)

build-linux-arm64:
	$(call run_target,$(LINUX_ENV),linux-arm64)

package-linux-deb:
	$(call run_target,$(LINUX_ENV),linux-package-deb)

package-linux-rpm:
	$(call run_target,$(LINUX_ENV),linux-package-rpm)

package-linux-all:
	@$(MAKE) 'package-linux-deb' 'package-linux-rpm'

build-ios:
	@$(MAKE) 'build-ios-app' 'build-ios-ipa'

build-ios-app:
	$(call run_target,$(IOS_ENV),ios-arm64)

build-ios-ipa:
	$(call run_target,$(COMMON_ENV),ios-ipa)

install-ios-debug:
	$(call run_target,$(IOS_ENV),ios-install-debug)

install-ios-release:
	$(call run_target,$(IOS_ENV),ios-install-release)

deploy-ios-device:
	$(call run_target,$(COMMON_ENV),ios-deploy-device)

build-android:
	@$(MAKE) 'build-android-apk'

build-android-apk:
	$(call run_target,$(ANDROID_ENV),android-apk)

build-android-libxray:
	$(call run_target,$(COMMON_ENV),android-libxray)

mcp:
	$(call run_target,$(MCP_ENV),mcp)

mcp-bootstrap:
	$(call run_target,MCP_MODE=bootstrap $(COMMON_ENV),xcode-debug-bootstrap)

mcp-doctor:
	$(call run_target,MCP_MODE=doctor $(COMMON_ENV),xcode-mcp-doctor)

mcp-install:
	$(call run_target,MCP_MODE=install $(COMMON_ENV),xstream-mcp-install)

mcp-start-dev:
	$(call run_target,MCP_MODE=start-dev $(COMMON_ENV),xstream-mcp-start-dev)

mcp-start-runtime:
	$(call run_target,MCP_MODE=start-runtime $(COMMON_ENV),xstream-mcp-start-runtime)
