#!/usr/bin/env bash
# Deprecated path shim. Prefer:
#   curl -fsSL https://install.offsend.io/cli | bash
#   ./scripts/cli/install.sh
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/cli/install.sh" "$@"
