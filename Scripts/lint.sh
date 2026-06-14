#!/usr/bin/env bash
set -euo pipefail

if command -v swiftformat >/dev/null 2>&1; then
  swiftformat App Core Services
else
  echo "swiftformat is not installed; skipping formatting."
fi
