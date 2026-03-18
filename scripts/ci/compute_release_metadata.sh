#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
  echo "GITHUB_OUTPUT is required" >&2
  exit 1
fi

if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  release_tag="${GITHUB_REF_NAME}"
  release_title="Release ${GITHUB_REF_NAME}"
  release_notes="Automated release for ${GITHUB_REF_NAME}"
elif [[ "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" ]]; then
  release_tag="manual-${GITHUB_RUN_NUMBER:-0}"
  release_title="Manual Build ${GITHUB_RUN_NUMBER:-0}"
  release_notes="Automated manual build from ${GITHUB_SHA:-unknown}"
else
  release_tag="nightly-${GITHUB_RUN_NUMBER:-0}"
  release_title="Nightly Build ${GITHUB_RUN_NUMBER:-0}"
  release_notes="Automated nightly build from ${GITHUB_SHA:-unknown}"
fi

{
  echo "release_tag=${release_tag}"
  echo "release_title=${release_title}"
  echo "release_notes=${release_notes}"
} >> "$GITHUB_OUTPUT"
