#!/usr/bin/env bash
set -euo pipefail

platform_name="${1:-}"
file_pattern="${2:-}"
remote_path="${3:-}"
artifact_dir="${ARTIFACT_DIR:-release-artifacts}"

if [[ -z "${RSYNC_SSH_KEY:-}" || -z "${VPS_HOST:-}" ]]; then
  echo "VPS sync skipped because RSYNC_SSH_KEY or VPS_HOST is not configured."
  exit 0
fi

mkdir -p ~/.ssh
printf '%s' "$RSYNC_SSH_KEY" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
ssh-keyscan -H "$VPS_HOST" >> ~/.ssh/known_hosts

file="$(find "$artifact_dir" -name "$file_pattern" | head -n 1 || true)"
if [[ -z "$file" ]]; then
  echo "Artifact not found for pattern: $file_pattern" >&2
  exit 1
fi

echo "Uploading $file to /data/update-server/$remote_path"
rsync -av "$file" "root@${VPS_HOST}:/data/update-server/${remote_path}" --delete

if [[ "$platform_name" == "windows" ]]; then
  msix_file="$(find "$artifact_dir" -name '*.msix' | head -n 1 || true)"
  if [[ -n "$msix_file" ]]; then
    rsync -av "$msix_file" \
      "root@${VPS_HOST}:/data/update-server/xstream-windows-latest/xstream-windows-latest.msix" \
      --delete
  fi
fi
