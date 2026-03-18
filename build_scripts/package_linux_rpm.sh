#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="${VERSION:-$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)}"
ARCH="${ARCH:-x86_64}"
DIST_DIR="$PROJECT_ROOT/dist/linux"
PACKAGE_ROOT="$DIST_DIR/package-root"
NFPM_BIN="$PROJECT_ROOT/.tools/nfpm"

if [[ ! -x "$NFPM_BIN" ]]; then
  "$PROJECT_ROOT/build_scripts/package_linux_deb.sh" >/dev/null
fi

mkdir -p "$DIST_DIR"
chmod 0755 packaging/nfpm/postinstall.sh

VERSION="$VERSION" "$NFPM_BIN" package \
  --packager rpm \
  --config packaging/nfpm/nfpm.yaml \
  --target "$DIST_DIR/xstream-${VERSION}.${ARCH}.rpm"

echo "Built $DIST_DIR/xstream-${VERSION}.${ARCH}.rpm"
