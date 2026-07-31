#!/usr/bin/env bash
# Builds the release `offsend` binary via Rust (crates/offsend-cli).
set -euo pipefail

# shellcheck source=../lib/repo-paths.sh
source "$(cd "$(dirname "$0")" && pwd)/../lib/repo-paths.sh"

VERSION="${OFFSEND_CLI_VERSION:?Set OFFSEND_CLI_VERSION (e.g. 0.0.6)}"

cd "$REPO_ROOT"

cargo build -p offsend-cli --release

BIN_PATH="$REPO_ROOT/target/release/offsend"
test -x "$BIN_PATH"

echo "Built CLI $VERSION at $BIN_PATH"
