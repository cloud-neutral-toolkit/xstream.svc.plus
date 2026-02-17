#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${XSTREAM_RUNTIME_APP_PATH:-/Applications/xstream.app}"
RUNTIME_MCP="$APP_PATH/Contents/Resources/runtime-tools/xstream-mcp/start-xstream-mcp-server.sh"

if [ ! -x "$RUNTIME_MCP" ]; then
  echo "runtime mcp launcher not found: $RUNTIME_MCP" >&2
  echo "build and install app first (make macos-arm64/macos-intel)." >&2
  exit 1
fi

exec "$RUNTIME_MCP"
