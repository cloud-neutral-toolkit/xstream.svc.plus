#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${1:-release-artifacts}"
tag="${RELEASE_TAG:-daily-${GITHUB_RUN_NUMBER:-0}}"
title="${RELEASE_TITLE:-Daily Build ${GITHUB_RUN_NUMBER:-0}}"
notes="${RELEASE_NOTES:-Automated build}"

if ! gh release view "$tag" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  gh release create "$tag" --repo "${GITHUB_REPOSITORY}" --title "$title" --notes "$notes"
else
  gh release edit "$tag" --repo "${GITHUB_REPOSITORY}" --title "$title" --notes "$notes"
fi

mapfile -d '' files < <(find "$artifact_dir" -type f -print0)

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "No release artifacts found in $artifact_dir" >&2
  exit 1
fi

for file in "${files[@]}"; do
  gh release upload "$tag" "$file" --repo "${GITHUB_REPOSITORY}" --clobber
done
