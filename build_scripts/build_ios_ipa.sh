#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_METHOD="${IOS_EXPORT_METHOD:-development}"
IPA_DIR="$ROOT_DIR/build/ios/ipa"

cd "$ROOT_DIR"

echo ">>> Building iOS native bridge (.a) ..."
./build_scripts/build_ios_xray.sh

echo ">>> Building iOS IPA (export method: $EXPORT_METHOD) ..."
flutter build ipa --release --export-method "$EXPORT_METHOD"

IPA_PATH="$(find "$IPA_DIR" -maxdepth 1 -type f -name '*.ipa' | head -n1 || true)"
if [[ -z "$IPA_PATH" ]]; then
  echo "iOS IPA build completed but no .ipa found in: $IPA_DIR"
  exit 1
fi

echo ">>> IPA ready:"
echo "    $IPA_PATH"
