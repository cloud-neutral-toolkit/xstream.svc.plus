#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_METHOD="${IOS_EXPORT_METHOD:-app-store}"
IPA_DIR="$ROOT_DIR/build/ios/ipa"
BRANCH="${BRANCH:-$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)}"
BUILD_ID="${BUILD_ID:-$(git -C "$ROOT_DIR" rev-parse --short HEAD)}"
BUILD_DATE="${BUILD_DATE:-$(date '+%Y-%m-%d')}"
UNAME_S="${UNAME_S:-$(uname -s)}"

if [[ "$UNAME_S" != "Darwin" ]]; then
  echo "iOS IPA build is only supported on macOS"
  exit 0
fi

cd "$ROOT_DIR"

echo ">>> Building iOS native bridge (.a) ..."
./build_scripts/build_ios_xray.sh

echo ">>> Building iOS IPA (export method: $EXPORT_METHOD) ..."
flutter build ipa --release \
  --export-method "$EXPORT_METHOD" \
  --dart-define=BRANCH_NAME="$BRANCH" \
  --dart-define=BUILD_ID="$BUILD_ID" \
  --dart-define=BUILD_DATE="$BUILD_DATE"

IPA_PATH="$(find "$IPA_DIR" -maxdepth 1 -type f -name '*.ipa' | head -n1 || true)"
if [[ -z "$IPA_PATH" ]]; then
  echo "iOS IPA build completed but no .ipa found in: $IPA_DIR"
  exit 1
fi

echo ">>> IPA ready:"
echo "    $IPA_PATH"
