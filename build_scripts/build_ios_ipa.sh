#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_METHOD="${IOS_EXPORT_METHOD:-app-store}"
IPA_DIR="$ROOT_DIR/build/ios/ipa"
APP_DIR="$ROOT_DIR/build/ios/iphoneos"
BRANCH="${BRANCH:-$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)}"
BUILD_ID="${BUILD_ID:-$(git -C "$ROOT_DIR" rev-parse --short HEAD)}"
BUILD_DATE="${BUILD_DATE:-$(date '+%Y-%m-%d')}"
UNAME_S="${UNAME_S:-$(uname -s)}"
NO_CODESIGN="${IOS_NO_CODESIGN:-0}"

if [[ "$UNAME_S" != "Darwin" ]]; then
  echo "iOS IPA build is only supported on macOS"
  exit 0
fi

cd "$ROOT_DIR"

echo ">>> Building iOS native bridge (.a) ..."
./build_scripts/build_ios_xray.sh

rm -rf "$IPA_DIR"
mkdir -p "$IPA_DIR"

if [[ "$NO_CODESIGN" == "1" ]]; then
  echo ">>> Building unsigned iOS app bundle for CI packaging ..."
  flutter build ios --release --no-codesign \
    --dart-define=BRANCH_NAME="$BRANCH" \
    --dart-define=BUILD_ID="$BUILD_ID" \
    --dart-define=BUILD_DATE="$BUILD_DATE"

  if [[ ! -d "$APP_DIR/Runner.app" ]]; then
    echo "Unsigned iOS build completed but Runner.app was not found in: $APP_DIR"
    exit 1
  fi

  echo ">>> Packaging unsigned IPA payload ..."
  mkdir -p "$IPA_DIR/Payload"
  cp -R "$APP_DIR/Runner.app" "$IPA_DIR/Payload/"
  (
    cd "$IPA_DIR"
    zip -qry XStream.ipa Payload
  )
else
  echo ">>> Building signed iOS IPA (export method: $EXPORT_METHOD) ..."
  flutter build ipa --release \
    --export-method "$EXPORT_METHOD" \
    --dart-define=BRANCH_NAME="$BRANCH" \
    --dart-define=BUILD_ID="$BUILD_ID" \
    --dart-define=BUILD_DATE="$BUILD_DATE"
fi

IPA_PATH="$(find "$IPA_DIR" -maxdepth 1 -type f -name '*.ipa' | head -n1 || true)"
if [[ -z "$IPA_PATH" ]]; then
  echo "iOS IPA build completed but no .ipa found in: $IPA_DIR"
  exit 1
fi

echo ">>> IPA ready:"
echo "    $IPA_PATH"
