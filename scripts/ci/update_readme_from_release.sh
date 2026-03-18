#!/usr/bin/env bash
set -euo pipefail

tag="${RELEASE_TAG:-daily-${GITHUB_RUN_NUMBER:-0}}"
release_json="/tmp/xstream-release-assets.json"

gh release view "$tag" --repo "${GITHUB_REPOSITORY}" --json assets > "$release_json"

python3 scripts/update_readme_downloads.py \
  --repo "${GITHUB_REPOSITORY}" \
  --tag "$tag" \
  --release-json "$release_json" \
  --readme README.md

if git diff --quiet -- README.md; then
  echo "README already up to date"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add README.md
git commit -m "docs: refresh README download links [skip ci]"
git push origin HEAD:main
