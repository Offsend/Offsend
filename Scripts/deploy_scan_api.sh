#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if command -v fly >/dev/null 2>&1; then
  FLY=fly
elif command -v flyctl >/dev/null 2>&1; then
  FLY=flyctl
else
  echo "error: flyctl is not installed. See https://fly.io/docs/hands-on/install-flyctl/" >&2
  exit 1
fi

"$FLY" deploy --config Server/fly.toml --dockerfile Server/Dockerfile "$@"
