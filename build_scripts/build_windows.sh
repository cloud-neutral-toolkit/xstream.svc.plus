#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"

PATCH_FILE="$DIR/build_scripts/patches/xray-core-wintun-session-retry.patch"
XRAY_CORE_DIR="$DIR/vendor/Xray-core"
XRAY_PATCH_APPLIED=0

apply_xray_windows_patch() {
  if [[ ! -f "$PATCH_FILE" ]]; then
    return
  fi

  if git -C "$XRAY_CORE_DIR" apply --check "$PATCH_FILE" >/dev/null 2>&1; then
    git -C "$XRAY_CORE_DIR" apply "$PATCH_FILE"
    XRAY_PATCH_APPLIED=1
    return
  fi

  if git -C "$XRAY_CORE_DIR" apply -R --check "$PATCH_FILE" >/dev/null 2>&1; then
    return
  fi

  echo "Failed to apply bundled Xray-core Windows patch: $PATCH_FILE" >&2
  exit 1
}

cleanup_xray_windows_patch() {
  if [[ "$XRAY_PATCH_APPLIED" == "1" ]]; then
    git -C "$XRAY_CORE_DIR" restore --source=HEAD --worktree -- proxy/tun/tun_windows.go
  fi
}

trap cleanup_xray_windows_patch EXIT

apply_xray_windows_patch

cd "$DIR/go_core"

# The Windows bridge requires cgo. Prefer a user-provided compiler, then
# fall back to the common Chocolatey MinGW-w64 installation path.
export CGO_ENABLED=1

if [[ -z "${CC:-}" ]]; then
  if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    CC="$(command -v x86_64-w64-mingw32-gcc)"
  elif [[ -x "/c/ProgramData/mingw64/mingw64/bin/x86_64-w64-mingw32-gcc.exe" ]]; then
    CC="/c/ProgramData/mingw64/mingw64/bin/x86_64-w64-mingw32-gcc.exe"
  else
    echo "Missing MinGW-w64 compiler x86_64-w64-mingw32-gcc." >&2
    echo "Install MinGW-w64 or set CC explicitly before running this script." >&2
    exit 1
  fi
fi

export CC

GOOS=windows GOARCH=amd64 go build -buildmode=c-shared \
  -ldflags="-linkmode external -extldflags '-static'" \
  -o ../bindings/libgo_native_bridge.dll \
  ./bridge_windows.go
