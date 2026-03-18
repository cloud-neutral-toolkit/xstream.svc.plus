#!/usr/bin/env bash
set -euo pipefail

flutter_version="${1:?flutter version is required}"

case "${RUNNER_OS:-}" in
  Linux)
    archive="stable/linux/flutter_linux_${flutter_version}-stable.tar.xz"
    ;;
  macOS)
    archive="stable/macos/flutter_macos_${flutter_version}-stable.zip"
    ;;
  *)
    echo "Unsupported runner OS: ${RUNNER_OS:-unknown}" >&2
    exit 1
    ;;
esac

install_root="${RUNNER_TEMP:?RUNNER_TEMP is required}/flutter-sdk"
rm -rf "$install_root"
mkdir -p "$install_root"

curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/${archive}" -o "$install_root/flutter-sdk.archive"
if [[ "$archive" == *.tar.xz ]]; then
  tar -xJf "$install_root/flutter-sdk.archive" -C "$install_root"
else
  ditto -x -k "$install_root/flutter-sdk.archive" "$install_root"
fi

echo "$install_root/flutter/bin" >> "${GITHUB_PATH:?GITHUB_PATH is required}"
"$install_root/flutter/bin/flutter" --version
