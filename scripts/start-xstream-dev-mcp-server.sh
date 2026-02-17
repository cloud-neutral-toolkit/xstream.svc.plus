#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/tools/xstream-mcp-server"

export XSTREAM_ROOT="$ROOT_DIR"

if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT_DIR/.env"
  set +a
fi

cd "$SERVER_DIR"
exec go run .
