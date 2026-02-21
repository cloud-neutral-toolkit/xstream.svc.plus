#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_ID="${IOS_DEVICE:-}"

cd "$ROOT_DIR"

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(flutter devices --machine | python3 -c 'import json,sys; devices=json.load(sys.stdin); ios=[d for d in devices if d.get("targetPlatform")=="ios"]; print((ios[0].get("id","") if ios else ""), end="")')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No iOS device found. Connect a device or set IOS_DEVICE=<udid>."
  exit 1
fi

echo ">>> Deploying release build to iOS device: $DEVICE_ID"
flutter run -d "$DEVICE_ID" --release --no-resident
