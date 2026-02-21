#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APK_PATH="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"

cd "$ROOT_DIR"

echo ">>> Building Android native bridge (.so) ..."
./build_scripts/build_android_xray.sh

echo ">>> Building Android release APK ..."
flutter build apk --release

if [[ ! -f "$APK_PATH" ]]; then
  echo "APK build completed but output not found: $APK_PATH"
  exit 1
fi

echo ">>> APK ready:"
echo "    $APK_PATH"
