#!/usr/bin/env bash
set -euo pipefail

platform="${1:-}"
arch="${2:-}"

flutter pub get

case "$platform" in
  linux)
    ./build_scripts/build_linux.sh
    flutter test --reporter expanded || true
    flutter build linux --release -v
    bash ./build_scripts/package_linux_bundle.sh
    if ! command -v nfpm >/dev/null 2>&1; then
      go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.43.3
      export PATH="$(go env GOPATH)/bin:$PATH"
    fi
    bash ./build_scripts/package_linux_native_packages.sh
    ;;
  windows)
    ./build_scripts/build_windows.sh
    flutter build windows --release
    pwsh -File ./build_scripts/package_windows_bundle.ps1
    pwsh -File ./build_scripts/package_windows_msi.ps1
    ;;
  macos)
    make "build-macos-${arch}"
    ;;
  android)
    ./build_scripts/build_android_apk.sh
    ;;
  ios)
    IOS_NO_CODESIGN=1 ./build_scripts/build_ios_ipa.sh
    (
      cd build/ios/iphoneos
      rm -f XStream.app.zip
      zip -qry XStream.app.zip Runner.app
    )
    ;;
  *)
    echo "Unsupported platform: $platform" >&2
    exit 1
    ;;
esac
