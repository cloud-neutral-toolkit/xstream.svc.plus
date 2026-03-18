#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUNDLE_DIR="$PROJECT_ROOT/build/linux/x64/release/bundle"
OUTPUT_DIR="$PROJECT_ROOT/build/linux/x64/release/packages"
STAGE_DIR="$OUTPUT_DIR/pkgroot"
NFPM_CONFIG="$OUTPUT_DIR/nfpm.yaml"

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Linux bundle directory not found: $BUNDLE_DIR" >&2
  exit 1
fi

if [[ ! -f "$BUNDLE_DIR/xstream" ]]; then
  echo "Linux bundle executable not found: $BUNDLE_DIR/xstream" >&2
  exit 1
fi

if ! command -v nfpm >/dev/null 2>&1; then
  echo "nfpm is required to build .deb/.rpm packages." >&2
  exit 1
fi

PUBSPEC_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$PROJECT_ROOT/pubspec.yaml" | head -n 1)"
APP_VERSION="${PUBSPEC_VERSION%%+*}"
RELEASE_NUMBER="1"
if [[ "$PUBSPEC_VERSION" == *"+"* ]]; then
  RELEASE_NUMBER="${PUBSPEC_VERSION#*+}"
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$STAGE_DIR/opt/xstream"
mkdir -p "$STAGE_DIR/usr/bin"
mkdir -p "$STAGE_DIR/usr/share/applications"
mkdir -p "$STAGE_DIR/usr/share/icons/hicolor/256x256/apps"

echo ">>> Staging Linux bundle for native packages ..."
rsync -a --delete "$BUNDLE_DIR/" "$STAGE_DIR/opt/xstream/"

cat > "$STAGE_DIR/usr/bin/xstream" <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH="/opt/xstream/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /opt/xstream/xstream "$@"
EOF
chmod +x "$STAGE_DIR/usr/bin/xstream"

cat > "$STAGE_DIR/usr/share/applications/xstream.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=XStream
Comment=Secure Tunnel desktop client
Exec=/usr/bin/xstream
Icon=xstream
Terminal=false
Categories=Utility;Network;
EOF

cp "$PROJECT_ROOT/assets/logo.png" \
  "$STAGE_DIR/usr/share/icons/hicolor/256x256/apps/xstream.png"

cat > "$NFPM_CONFIG" <<EOF
name: xstream
arch: amd64
platform: linux
version: ${APP_VERSION}
release: ${RELEASE_NUMBER}
section: default
priority: optional
maintainer: Xstream Team
description: |
  XStream desktop client for managing Secure Tunnel connections.
vendor: Xstream Team
homepage: https://github.com/cloud-neutral-toolkit/xstream.svc.plus
license: Apache-2.0
depends:
  - libgtk-3-0
  - libayatana-appindicator3-1
  - libx11-6
  - libstdc++6
overrides:
  rpm:
    depends:
      - gtk3
      - libX11
      - libstdc++
contents:
  - src: ${STAGE_DIR}/opt/xstream/
    dst: /opt/xstream
  - src: ${STAGE_DIR}/usr/bin/xstream
    dst: /usr/bin/xstream
    file_info:
      mode: 0755
  - src: ${STAGE_DIR}/usr/share/applications/xstream.desktop
    dst: /usr/share/applications/xstream.desktop
  - src: ${STAGE_DIR}/usr/share/icons/hicolor/256x256/apps/xstream.png
    dst: /usr/share/icons/hicolor/256x256/apps/xstream.png
EOF

echo ">>> Building .deb package ..."
nfpm pkg \
  --packager deb \
  --config "$NFPM_CONFIG" \
  --target "$OUTPUT_DIR/xstream-linux-amd64.deb"

echo ">>> Building .rpm package ..."
nfpm pkg \
  --packager rpm \
  --config "$NFPM_CONFIG" \
  --target "$OUTPUT_DIR/xstream-linux-x86_64.rpm"

echo ">>> Linux native packages ready:"
echo "    $OUTPUT_DIR/xstream-linux-amd64.deb"
echo "    $OUTPUT_DIR/xstream-linux-x86_64.rpm"
