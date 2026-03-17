#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required to clean daily tags." >&2
  exit 1
fi

GITHUB_REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "$GITHUB_REPO" ]]; then
  remote_url="$(git config --get remote.origin.url || true)"
  GITHUB_REPO="$(printf '%s' "$remote_url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
fi

if [[ -z "$GITHUB_REPO" ]]; then
  echo "Unable to resolve GitHub repository slug." >&2
  exit 1
fi

NOW="$(date +%s)"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"
MAX_AGE="$((MAX_AGE_HOURS * 60 * 60))"

echo "Cleaning old daily-* tags and GitHub releases (keep recent ${MAX_AGE_HOURS}h)..."

mapfile -t daily_tags < <(git tag --list 'daily-*')

for tag in "${daily_tags[@]}"; do
  TAG_TIME="$(git log -1 --format=%ct "$tag")"
  AGE="$((NOW - TAG_TIME))"

  if (( AGE > MAX_AGE )); then
    echo "Deleting tag: $tag (age: $((AGE / 3600))h)"
    gh release delete "$tag" --repo "$GITHUB_REPO" --yes --cleanup-tag || true
    git tag -d "$tag" >/dev/null 2>&1 || true
    git push origin ":refs/tags/$tag" >/dev/null 2>&1 || true
  else
    echo "Keeping recent tag: $tag"
  fi
done

echo "Cleanup done."
