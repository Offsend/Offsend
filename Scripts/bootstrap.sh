#!/usr/bin/env bash
set -euo pipefail

if ! command -v tuist >/dev/null 2>&1; then
  echo "Tuist is required. Install it with: brew install tuist"
  exit 1
fi

tuist install
tuist generate
