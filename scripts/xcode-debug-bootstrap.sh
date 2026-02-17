#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ensure_flutter_lldbinit() {
  local platform_dir="$1"
  local flutter_dir="$ROOT_DIR/$platform_dir/Flutter"
  local src="$flutter_dir/ephemeral/flutter_lldbinit"
  local dst="$flutter_dir/flutter_lldbinit"
  local helper="$flutter_dir/ephemeral/flutter_lldb_helper.py"

  mkdir -p "$flutter_dir/ephemeral"

  if [[ ! -f "$src" ]]; then
    cat > "$src" <<'EOF'
command script import "$FLUTTER_ROOT/packages/flutter_tools/bin/lldb_commands.py"
settings set target.inline-breakpoint-strategy always
EOF
  fi

  cp "$src" "$dst"

  # Some Flutter-generated lldbinit imports a relative helper; keep a fallback
  # helper to avoid Xcode LLDB init failures before the first Flutter build.
  if [[ ! -f "$helper" ]]; then
    cat > "$helper" <<'EOF'
def __lldb_init_module(debugger, _dict):
    pass
EOF
  fi
}

ensure_app_filename() {
  local platform_dir="$1"
  local flutter_dir="$ROOT_DIR/$platform_dir/Flutter"
  local app_name="$2"
  mkdir -p "$flutter_dir/generated" "$flutter_dir/ephemeral"
  echo "$app_name" > "$flutter_dir/generated/.app_filename"
  echo "$app_name" > "$flutter_dir/ephemeral/.app_filename"
}

echo "[xcode-debug] flutter pub get"
flutter pub get

echo "[xcode-debug] pod install (ios)"
(
  cd ios
  pod install
)

echo "[xcode-debug] pod install (macos)"
(
  cd macos
  pod install
)

echo "[xcode-debug] prepare LLDB init + app filename"
ensure_flutter_lldbinit "ios"
ensure_flutter_lldbinit "macos"
ensure_app_filename "ios" "Runner.app"
ensure_app_filename "macos" "xstream.app"

echo "[xcode-debug] done"
echo "Open Xcode workspaces:"
echo "  - $ROOT_DIR/ios/Runner.xcworkspace"
echo "  - $ROOT_DIR/macos/Runner.xcworkspace"
