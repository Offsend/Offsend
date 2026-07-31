#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/repo-paths.sh
source "$(cd "$(dirname "$0")" && pwd)/../lib/repo-paths.sh"
cd "$REPO_ROOT"

if command -v fly >/dev/null 2>&1; then
  FLY=fly
elif command -v flyctl >/dev/null 2>&1; then
  FLY=flyctl
else
  echo "error: flyctl is not installed. See https://fly.io/docs/hands-on/install-flyctl/" >&2
  exit 1
fi

"$FLY" deploy "$REPO_ROOT" \
  --config "$SERVER_ROOT/fly.toml" \
  --dockerfile "$SERVER_ROOT/Dockerfile" \
  "$@"
