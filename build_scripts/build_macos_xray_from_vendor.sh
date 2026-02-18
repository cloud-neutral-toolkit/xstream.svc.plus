#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor/Xray-core"
OUT_DIR="$ROOT_DIR/macos/Resources/xray"

if [ ! -d "$VENDOR_DIR" ]; then
  echo "[error] vendor/Xray-core not found. run: git submodule update --init --recursive" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "[error] go not found in PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

build_target() {
  local arch="$1"
  local output="$2"
  echo "[info] building xray for darwin/$arch -> $output"
  (
    cd "$VENDOR_DIR"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" \
      go build -trimpath -buildvcs=false \
      -ldflags="-s -w -buildid=" \
      -o "$TMP_DIR/$output" ./main
  )
  cp -f "$TMP_DIR/$output" "$OUT_DIR/$output"
  chmod 755 "$OUT_DIR/$output"
}

build_target arm64 xray
build_target amd64 xray-x86_64

if [ ! -f "$OUT_DIR/xray" ] || [ ! -f "$OUT_DIR/xray-x86_64" ]; then
  echo "[error] build output missing" >&2
  exit 1
fi

fetch_dat() {
  local name="$1"
  local url
  case "$name" in
    geoip.dat)
      url="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
      ;;
    geosite.dat)
      url="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
      ;;
    *)
      echo "[error] unsupported data file: $name" >&2
      exit 1
      ;;
  esac

  echo "[info] downloading $name from $url"
  if command -v wget >/dev/null 2>&1; then
    wget -O "$OUT_DIR/$name" --tries=3 --timeout=20 "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 20 "$url" -o "$OUT_DIR/$name"
  else
    echo "[error] neither wget nor curl found in PATH" >&2
    exit 1
  fi
}

fetch_dat geoip.dat
fetch_dat geosite.dat

echo "[ok] built vendor xray binaries:"
ls -lh "$OUT_DIR/xray" "$OUT_DIR/xray-x86_64"
ls -lh "$OUT_DIR/geoip.dat" "$OUT_DIR/geosite.dat"
