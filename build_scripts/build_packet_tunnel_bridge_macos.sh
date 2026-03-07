#!/usr/bin/env bash
set -euo pipefail

if [[ "${PLATFORM_NAME:-}" != "macosx" ]]; then
  echo "[xray-bridge] skip non-macos platform: ${PLATFORM_NAME:-unknown}"
  exit 0
fi

# Add common Go paths for Xcode environment
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Find go binary
GO_BIN=$(which go || echo "/opt/homebrew/bin/go")
if ! command -v "$GO_BIN" &> /dev/null; then
  if [[ -f "/usr/local/bin/go" ]]; then
    GO_BIN="/usr/local/bin/go"
  elif [[ -f "/opt/homebrew/bin/go" ]]; then
    GO_BIN="/opt/homebrew/bin/go"
  else
    echo "error: go command not found. Please install Go." >&2
    exit 1
  fi
fi

ROOT_DIR="${SRCROOT}/.."
GO_CORE_DIR="${ROOT_DIR}/go_core"
OUTPUT_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
OUTPUT_LIB="${OUTPUT_DIR}/libxray_bridge.dylib"
TMP_OUT_DIR="${TARGET_TEMP_DIR}/xray-bridge"
TMP_LIB="${TMP_OUT_DIR}/libxray_bridge.dylib"

if [[ ! -d "${GO_CORE_DIR}" ]]; then
  echo "error: go_core directory not found: ${GO_CORE_DIR}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
mkdir -p "${TMP_OUT_DIR}"

ARCH="${CURRENT_ARCH:-}"
if [[ -z "${ARCH}" || "${ARCH}" == "undefined_arch" ]]; then
  ARCH="${NATIVE_ARCH_ACTUAL:-}"
fi
if [[ -z "${ARCH}" || "${ARCH}" == "undefined_arch" ]]; then
  ARCH="$(echo "${ARCHS:-}" | awk '{print $1}')"
fi
if [[ -z "${ARCH}" || "${ARCH}" == "undefined_arch" ]]; then
  ARCH="$(uname -m)"
fi
if [[ "${ARCH}" == "x86_64h" ]]; then
  ARCH="x86_64"
fi

echo "[xray-bridge] building for darwin/${ARCH} -> ${TMP_LIB}"
(
  cd "${GO_CORE_DIR}"
  export CGO_ENABLED=1
  export GOOS=darwin
  export GOARCH="${ARCH}"
  export CC="$(xcrun --sdk macosx --find clang)"
  export CGO_CFLAGS="-isysroot $(xcrun --sdk macosx --show-sdk-path)"
  export CGO_LDFLAGS="-isysroot $(xcrun --sdk macosx --show-sdk-path)"
  "$GO_BIN" build -trimpath -buildmode=c-shared -o "${TMP_LIB}" ./bridge_ios.go
)

if [[ ! -f "${TMP_LIB}" ]]; then
  echo "error: failed to build ${TMP_LIB}" >&2
  exit 1
fi

cp -f "${TMP_LIB}" "${OUTPUT_LIB}"
rm -f "${OUTPUT_DIR}/libxray_bridge.h"
chmod 755 "${OUTPUT_LIB}"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -n "${SIGN_IDENTITY}" && "${SIGN_IDENTITY}" != "-" ]]; then
  echo "[xray-bridge] signing with identity ${EXPANDED_CODE_SIGN_IDENTITY_NAME:-unknown}"
  /usr/bin/codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${OUTPUT_LIB}"
fi

echo "[xray-bridge] built: ${OUTPUT_LIB}"
