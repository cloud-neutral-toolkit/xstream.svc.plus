# Makefile for XStream project

FLUTTER = flutter
PROJECT_NAME = XStream
APP_NAME := Xstream
ICON_SRC := assets/logo.png
ICON_DST := macos/Runner/Assets.xcassets/AppIcon.appiconset
MACOS_APP_BUNDLE := build/macos/Build/Products/Release/xstream.app
MACOS_BUILD_LOCK_DIR := build/.macos-build.lock
MACOS_BUILD_LOCK_PID_FILE := $(MACOS_BUILD_LOCK_DIR)/pid
MAKE_SCRIPT_DIR := scripts/make
RUN_TARGET_SCRIPT := $(MAKE_SCRIPT_DIR)/run-target.sh

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
BUILD_ID := $(shell git rev-parse --short HEAD)
BUILD_DATE := $(shell date "+%Y-%m-%d")
MCP_MODE ?= dev

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

.PHONY: all windows-icon icon fix-macos-signing macos-intel macos-arm64 macos-debug-run macos-vendor-xray windows-x64 linux-x64 linux-arm64 android-arm64 android-libxray android-apk ios-arm64 ios-ipa ios-install-debug ios-install-release ios-deploy-device mcp xcode-debug-bootstrap xcode-mcp-doctor xstream-mcp-install xstream-mcp-start xstream-mcp-start-dev xstream-mcp-start-runtime clean

all: macos-intel macos-arm64 windows-x64 linux-x64 linux-arm64 android-arm64 ios-arm64

windows-icon:
	@$(RUN_TARGET_SCRIPT) windows-icon

icon:
	@FLUTTER="$(FLUTTER)" $(RUN_TARGET_SCRIPT) icon

fix-macos-signing:
	@FLUTTER="$(FLUTTER)" $(RUN_TARGET_SCRIPT) fix-macos-signing

macos-intel:
	@UNAME_S="$(UNAME_S)" UNAME_M="$(UNAME_M)" FLUTTER="$(FLUTTER)" BRANCH="$(BRANCH)" BUILD_ID="$(BUILD_ID)" BUILD_DATE="$(BUILD_DATE)" DMG_NAME="$(DMG_NAME)" MACOS_APP_BUNDLE="$(MACOS_APP_BUNDLE)" MACOS_BUILD_LOCK_DIR="$(MACOS_BUILD_LOCK_DIR)" MACOS_BUILD_LOCK_PID_FILE="$(MACOS_BUILD_LOCK_PID_FILE)" $(RUN_TARGET_SCRIPT) macos-intel

macos-arm64:
	@UNAME_S="$(UNAME_S)" UNAME_M="$(UNAME_M)" FLUTTER="$(FLUTTER)" BRANCH="$(BRANCH)" BUILD_ID="$(BUILD_ID)" BUILD_DATE="$(BUILD_DATE)" DMG_NAME="$(DMG_NAME)" MACOS_APP_BUNDLE="$(MACOS_APP_BUNDLE)" MACOS_BUILD_LOCK_DIR="$(MACOS_BUILD_LOCK_DIR)" MACOS_BUILD_LOCK_PID_FILE="$(MACOS_BUILD_LOCK_PID_FILE)" $(RUN_TARGET_SCRIPT) macos-arm64

macos-debug-run:
	@UNAME_S="$(UNAME_S)" FLUTTER="$(FLUTTER)" $(RUN_TARGET_SCRIPT) macos-debug-run

macos-vendor-xray:
	@$(RUN_TARGET_SCRIPT) macos-vendor-xray

windows-x64:
	@UNAME_S="$(UNAME_S)" OS="$(OS)" FLUTTER="$(FLUTTER)" $(RUN_TARGET_SCRIPT) windows-x64

linux-x64:
	@UNAME_S="$(UNAME_S)" FLUTTER="$(FLUTTER)" $(RUN_TARGET_SCRIPT) linux-x64

linux-arm64:
	@UNAME_S="$(UNAME_S)" UNAME_M="$(UNAME_M)" FLUTTER="$(FLUTTER)" $(RUN_TARGET_SCRIPT) linux-arm64

android-arm64:
	@UNAME_S="$(UNAME_S)" FLUTTER="$(FLUTTER)" $(RUN_TARGET_SCRIPT) android-arm64

android-libxray:
	@$(RUN_TARGET_SCRIPT) android-libxray

android-apk:
	@$(RUN_TARGET_SCRIPT) android-apk

ios-arm64:
	@UNAME_S="$(UNAME_S)" FLUTTER="$(FLUTTER)" $(RUN_TARGET_SCRIPT) ios-arm64

ios-ipa:
	@$(RUN_TARGET_SCRIPT) ios-ipa

ios-install-debug:
	@UNAME_S="$(UNAME_S)" FLUTTER="$(FLUTTER)" IOS_DEVICE="$(IOS_DEVICE)" IOS_NO_RESIDENT="$(IOS_NO_RESIDENT)" $(RUN_TARGET_SCRIPT) ios-install-debug

ios-install-release:
	@UNAME_S="$(UNAME_S)" FLUTTER="$(FLUTTER)" IOS_DEVICE="$(IOS_DEVICE)" $(RUN_TARGET_SCRIPT) ios-install-release

ios-deploy-device:
	@$(RUN_TARGET_SCRIPT) ios-deploy-device

xcode-debug-bootstrap:
	@MCP_MODE=bootstrap $(RUN_TARGET_SCRIPT) xcode-debug-bootstrap

xcode-mcp-doctor:
	@MCP_MODE=doctor $(RUN_TARGET_SCRIPT) xcode-mcp-doctor

xstream-mcp-install:
	@MCP_MODE=install $(RUN_TARGET_SCRIPT) xstream-mcp-install

xstream-mcp-start:
	@MCP_MODE=start-dev $(RUN_TARGET_SCRIPT) xstream-mcp-start

xstream-mcp-start-dev:
	@MCP_MODE=start-dev $(RUN_TARGET_SCRIPT) xstream-mcp-start-dev

xstream-mcp-start-runtime:
	@MCP_MODE=start-runtime $(RUN_TARGET_SCRIPT) xstream-mcp-start-runtime

mcp:
	@MCP_MODE="$(MCP_MODE)" $(RUN_TARGET_SCRIPT) mcp

clean:
	@FLUTTER="$(FLUTTER)" $(RUN_TARGET_SCRIPT) clean
