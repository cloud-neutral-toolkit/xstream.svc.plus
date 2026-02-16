#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GO_CORE_DIR="$ROOT_DIR/go_core"
JNI_LIBS_DIR="$ROOT_DIR/android/app/src/main/jniLibs"

ANDROID_NDK_ROOT="${ANDROID_NDK_HOME:-}"
if [[ -z "$ANDROID_NDK_ROOT" && -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}/ndk" ]]; then
  ANDROID_NDK_ROOT="$(ls -1d "${ANDROID_HOME}"/ndk/* 2>/dev/null | sort -V | tail -n1 || true)"
fi

if [[ -z "$ANDROID_NDK_ROOT" || ! -d "$ANDROID_NDK_ROOT" ]]; then
  echo "ANDROID_NDK_HOME is not configured and no NDK was found under ANDROID_HOME/ndk."
  exit 1
fi

HOST_TAG=""
case "$(uname -s)" in
  Darwin)
    if [[ "$(uname -m)" == "arm64" ]]; then
      HOST_TAG="darwin-arm64"
    else
      HOST_TAG="darwin-x86_64"
    fi
    ;;
  Linux)
    if [[ "$(uname -m)" == "aarch64" ]]; then
      HOST_TAG="linux-arm64"
    else
      HOST_TAG="linux-x86_64"
    fi
    ;;
  *)
    echo "Unsupported host OS: $(uname -s)"
    exit 1
    ;;
esac

TOOLCHAIN_BIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/bin"
if [[ ! -d "$TOOLCHAIN_BIN" ]]; then
  echo "NDK toolchain not found: $TOOLCHAIN_BIN"
  exit 1
fi

build_one() {
  local abi="$1"
  local goarch="$2"
  local clang="$3"
  local goarm="${4:-}"
  local outdir="$JNI_LIBS_DIR/$abi"

  mkdir -p "$outdir"
  echo ">>> Building $abi ..."

  (
    cd "$GO_CORE_DIR"
    export CGO_ENABLED=1
    export GOOS=android
    export GOARCH="$goarch"
    export CC="$TOOLCHAIN_BIN/$clang"
    if [[ -n "$goarm" ]]; then
      export GOARM="$goarm"
    else
      unset GOARM || true
    fi
    go build -trimpath -buildmode=c-shared \
      -o "$outdir/libgo_native_bridge.so" \
      ./bridge_android.go
  )
}

build_one "arm64-v8a" "arm64" "aarch64-linux-android21-clang"
build_one "armeabi-v7a" "arm" "armv7a-linux-androideabi21-clang" "7"
build_one "x86_64" "amd64" "x86_64-linux-android21-clang"

echo ">>> Android libxray build complete:"
echo "    $JNI_LIBS_DIR"
