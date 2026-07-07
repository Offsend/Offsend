#!/usr/bin/env bash
# Builds the release `offsend` binary for Linux via SPM.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${OFFSEND_CLI_VERSION:?Set OFFSEND_CLI_VERSION (e.g. 0.0.6)}"

GENERATED="$ROOT/CLI/Sources/Generated/CLIVersionRelease.swift"
mkdir -p "$(dirname "$GENERATED")"
cat > "$GENERATED" <<EOF
enum CLIVersionRelease {
    static let marketing: String? = "$VERSION"
}
EOF

cd "$ROOT"

build_args=(--product offsend -c release)
if [[ "$(uname -s)" == "Linux" ]]; then
  build_args+=(--static-swift-stdlib)
fi

swift build "${build_args[@]}"

BIN_PATH="$(swift build -c release --show-bin-path)/offsend"
test -x "$BIN_PATH"

echo "Built Linux CLI $VERSION at $BIN_PATH"
