#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GO_CORE_DIR="$ROOT_DIR/go_core"
JNI_LIBS_DIR="$ROOT_DIR/android/app/src/main/jniLibs"
LIBXRAY_DIR="$ROOT_DIR/libXray"

if [[ ! -d "$LIBXRAY_DIR" || ! -f "$LIBXRAY_DIR/go.mod" ]]; then
  echo "libXray submodule is missing. Run:"
  echo "  git submodule update --init --recursive libXray"
  exit 1
fi

resolve_android_sdk_root() {
  local local_props="$ROOT_DIR/android/local.properties"
  local candidates=()

  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    candidates+=("${ANDROID_SDK_ROOT}")
  fi
  if [[ -n "${ANDROID_HOME:-}" ]]; then
    candidates+=("${ANDROID_HOME}")
  fi

  if [[ -f "$local_props" ]]; then
    local raw_sdk_dir
    raw_sdk_dir="$(grep '^sdk.dir=' "$local_props" | head -n1 | cut -d'=' -f2- || true)"
    raw_sdk_dir="${raw_sdk_dir//\\:/:}"
    raw_sdk_dir="${raw_sdk_dir//\\=/=}"
    raw_sdk_dir="${raw_sdk_dir//$'\r'/}"
    if [[ -n "$raw_sdk_dir" ]]; then
      candidates+=("$raw_sdk_dir")
    fi
  fi

  candidates+=(
    "$HOME/Library/Android/sdk"
    "$HOME/Android/Sdk"
    "/opt/homebrew/share/android-commandlinetools"
  )

  local c
  for c in "${candidates[@]}"; do
    if [[ -n "$c" && -d "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

ANDROID_SDK_ROOT_RESOLVED="$(resolve_android_sdk_root || true)"

ANDROID_NDK_ROOT="${ANDROID_NDK_HOME:-}"
if [[ -z "$ANDROID_NDK_ROOT" && -n "${ANDROID_SDK_ROOT_RESOLVED}" && -d "${ANDROID_SDK_ROOT_RESOLVED}/ndk" ]]; then
  ANDROID_NDK_ROOT="$(ls -1d "${ANDROID_SDK_ROOT_RESOLVED}"/ndk/* 2>/dev/null | sort -V | tail -n1 || true)"
fi

if [[ -z "$ANDROID_NDK_ROOT" || ! -d "$ANDROID_NDK_ROOT" ]]; then
  echo "ANDROID NDK not found."
  echo "Resolved Android SDK root: ${ANDROID_SDK_ROOT_RESOLVED:-<none>}"
  echo "Please install NDK (for example: sdkmanager 'ndk;27.1.12297006')"
  echo "or set ANDROID_NDK_HOME explicitly."
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
