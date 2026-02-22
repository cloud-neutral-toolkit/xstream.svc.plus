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

download_file() {
  local url="$1"
  local output="$2"
  if command -v wget >/dev/null 2>&1; then
    wget -O "$output" --tries=3 --timeout=20 "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 20 "$url" -o "$output"
  else
    echo "[error] neither wget nor curl found in PATH" >&2
    exit 1
  fi
}

download_text() {
  local url="$1"
  if command -v wget >/dev/null 2>&1; then
    wget -qO- --tries=2 --timeout=10 "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 --connect-timeout 10 "$url"
  else
    echo "[error] neither wget nor curl found in PATH" >&2
    exit 1
  fi
}

calc_sha256() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    echo "[error] no sha256 tool found (shasum/sha256sum)" >&2
    exit 1
  fi
}

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
  local sha_url
  case "$name" in
    geoip.dat)
      url="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
      sha_url="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat.sha256sum"
      ;;
    geosite.dat)
      url="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
      sha_url="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat.sha256sum"
      ;;
    *)
      echo "[error] unsupported data file: $name" >&2
      exit 1
      ;;
  esac

  local out_file="$OUT_DIR/$name"
  local remote_hash=""
  local local_hash=""

  remote_hash="$(download_text "$sha_url" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  if [ -n "$remote_hash" ] && [ -f "$out_file" ]; then
    local_hash="$(calc_sha256 "$out_file")"
    if [ "$local_hash" = "$remote_hash" ]; then
      echo "[info] $name already up to date (sha256 matched), skip download"
      return 0
    fi
    echo "[info] $name hash changed, updating local file"
  elif [ -f "$out_file" ]; then
    echo "[warn] cannot fetch remote hash for $name, proceed to download latest"
  fi

  echo "[info] downloading $name from $url"
  download_file "$url" "$out_file"

  if [ -n "$remote_hash" ]; then
    local_hash="$(calc_sha256 "$out_file")"
    if [ "$local_hash" != "$remote_hash" ]; then
      echo "[error] sha256 mismatch after downloading $name" >&2
      echo "[error] expected: $remote_hash" >&2
      echo "[error] actual:   $local_hash" >&2
      exit 1
    fi
    echo "[info] $name verified (sha256 matched)"
  fi
}

fetch_dat geoip.dat
fetch_dat geosite.dat

echo "[ok] built vendor xray binaries:"
ls -lh "$OUT_DIR/xray" "$OUT_DIR/xray-x86_64"
ls -lh "$OUT_DIR/geoip.dat" "$OUT_DIR/geosite.dat"
