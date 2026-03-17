#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${1:-release-artifacts}"
tag="${RELEASE_TAG:-daily-${GITHUB_RUN_NUMBER:-0}}"
title="${RELEASE_TITLE:-Daily Build ${GITHUB_RUN_NUMBER:-0}}"

if ! gh release view "$tag" >/dev/null 2>&1; then
  gh release create "$tag" --title "$title" --notes "Automated daily build"
fi

mapfile -d '' files < <(find "$artifact_dir" -type f -print0)

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "No release artifacts found in $artifact_dir" >&2
  exit 1
fi

for file in "${files[@]}"; do
  gh release upload "$tag" "$file" --clobber
done
