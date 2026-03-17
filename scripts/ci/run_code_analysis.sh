#!/usr/bin/env bash
set -euo pipefail

if ! command -v git-secrets >/dev/null 2>&1; then
  rm -rf /tmp/git-secrets
  git clone https://github.com/awslabs/git-secrets.git /tmp/git-secrets
  sudo make install -C /tmp/git-secrets
fi

git secrets --install
git secrets --scan
flutter pub get
flutter analyze
