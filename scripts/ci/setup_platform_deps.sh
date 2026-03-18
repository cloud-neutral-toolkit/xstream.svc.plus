#!/usr/bin/env bash
set -euo pipefail

platform="${1:-}"

case "$platform" in
  linux)
    sudo apt-get update
    sudo apt-get install -y \
      clang \
      cmake \
      ninja-build \
      libgtk-3-dev \
      pkg-config \
      libx11-dev \
      binutils \
      libgl1-mesa-dev \
      libayatana-appindicator3-dev \
      imagemagick
    ;;
  android)
    ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
    export ANDROID_SDK_ROOT
    export ANDROID_HOME="$ANDROID_SDK_ROOT"

    if [[ -n "${GITHUB_ENV:-}" ]]; then
      {
        echo "ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
        echo "ANDROID_HOME=$ANDROID_SDK_ROOT"
      } >> "$GITHUB_ENV"
    fi

    sdkmanager=""
    for candidate in \
      "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
      "$ANDROID_SDK_ROOT/cmdline-tools/bin/sdkmanager" \
      "$ANDROID_SDK_ROOT/tools/bin/sdkmanager"; do
      if [[ -x "$candidate" ]]; then
        sdkmanager="$candidate"
        break
      fi
    done

    if [[ -z "$sdkmanager" ]]; then
      echo "Android sdkmanager not found under $ANDROID_SDK_ROOT" >&2
      exit 1
    fi

    if ! yes | "$sdkmanager" --licenses >/dev/null 2>&1; then
      echo "sdkmanager --licenses returned a non-zero status; continuing and letting package installation validate the Android SDK state." >&2
    fi
    "$sdkmanager" "ndk;27.1.12297006"

    flutter_bin="$(command -v flutter)"
    flutter_root="$(dirname "$(dirname "$flutter_bin")")"
    app_version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)"
    app_version="${app_version%%+*}"
    version_code="${GITHUB_RUN_NUMBER:-1}"

    cat > android/local.properties <<EOF
sdk.dir=$ANDROID_SDK_ROOT
flutter.sdk=$flutter_root
flutter.buildMode=release
flutter.versionName=$app_version
flutter.versionCode=$version_code
EOF
    ;;
  macos)
    brew install cocoapods create-dmg
    ;;
  ios)
    brew install cocoapods
    ;;
  windows)
    ;;
  *)
    echo "Unsupported platform: $platform" >&2
    exit 1
    ;;
esac
