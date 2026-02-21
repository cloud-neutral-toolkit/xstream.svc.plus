#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$DIR/build/ios"
LIBXRAY_DIR="$DIR/libXray"

if [[ ! -d "$LIBXRAY_DIR" || ! -f "$LIBXRAY_DIR/go.mod" ]]; then
  echo "libXray submodule is missing. Run:"
  echo "  git submodule update --init --recursive libXray"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

cd "$DIR/go_core"

echo ">>> Building iOS static library..."

export CGO_ENABLED=1
export GOOS=ios
export GOARCH=arm64
export CC="$(xcrun --sdk iphoneos --find clang)"
export CGO_CFLAGS="-isysroot $(xcrun --sdk iphoneos --show-sdk-path)"

go mod download
go build -buildmode=c-archive -o "$OUTPUT_DIR/libxray.a" ./bridge_ios.go

echo ">>> Output: $OUTPUT_DIR/libxray.a"
