#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${1:-}"
TARGET_ARCH="${2:-}"

if [ -z "$APP_BUNDLE" ]; then
  echo "usage: $0 <app_bundle_path> [arm64|amd64]" >&2
  exit 1
fi

case "$APP_BUNDLE" in
  /*) ;;
  *) APP_BUNDLE="$ROOT_DIR/$APP_BUNDLE" ;;
esac

if [ ! -d "$APP_BUNDLE" ]; then
  echo "app bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

if [ -z "$TARGET_ARCH" ]; then
  MACHINE_ARCH="$(uname -m)"
  case "$MACHINE_ARCH" in
    arm64)
      TARGET_ARCH="arm64"
      ;;
    x86_64)
      TARGET_ARCH="amd64"
      ;;
    *)
      echo "unsupported machine arch: $MACHINE_ARCH" >&2
      exit 1
      ;;
  esac
fi

if [ "$TARGET_ARCH" != "arm64" ] && [ "$TARGET_ARCH" != "amd64" ]; then
  echo "unsupported target arch: $TARGET_ARCH" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "go is required to package runtime mcp server" >&2
  exit 1
fi

SERVER_SRC="$ROOT_DIR/tools/xstream-mcp-server"
if [ ! -f "$SERVER_SRC/main.go" ]; then
  echo "xstream-mcp-server source not found: $SERVER_SRC" >&2
  exit 1
fi

RUNTIME_DIR="$APP_BUNDLE/Contents/Resources/runtime-tools/xstream-mcp"
mkdir -p "$RUNTIME_DIR"

BIN_PATH="$RUNTIME_DIR/xstream-mcp-server"
LAUNCHER_PATH="$RUNTIME_DIR/start-xstream-mcp-server.sh"
README_PATH="$RUNTIME_DIR/README.txt"

(
  cd "$SERVER_SRC"
  CGO_ENABLED=0 GOOS=darwin GOARCH="$TARGET_ARCH" go build -trimpath -ldflags='-s -w' -o "$BIN_PATH" .
)

cat > "$LAUNCHER_PATH" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Runtime mode: no repo is required; server will inspect standard macOS paths.
exec "$SCRIPT_DIR/xstream-mcp-server"
LAUNCHER
chmod +x "$LAUNCHER_PATH"

cat > "$README_PATH" <<'README'
XStream Runtime MCP Server

- Binary: ./xstream-mcp-server
- Launcher: ./start-xstream-mcp-server.sh
- Transport: stdio (MCP)

This runtime package is embedded inside the macOS app bundle to support
post-install debugging and external MCP-based orchestration.
README

echo "runtime mcp packaged: $RUNTIME_DIR"
