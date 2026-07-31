#!/usr/bin/env bash
# Bootstrap Tuist project for the macOS app.
set -euo pipefail

# shellcheck source=../lib/repo-paths.sh
source "$(cd "$(dirname "$0")" && pwd)/../lib/repo-paths.sh"

cd "$MACOS_APP_ROOT"

if ! command -v tuist >/dev/null 2>&1; then
  echo "Tuist is required. Install it with: brew install tuist"
  exit 1
fi

tuist install
tuist generate
