#!/usr/bin/env bash
# Backward-compatible alias for Scripts/install.sh (Linux-only callers).
exec "$(cd "$(dirname "$0")" && pwd)/install.sh" "$@"
