#!/usr/bin/env bash
# Packages a Linux `offsend` binary into a release tarball.
set -euo pipefail

VERSION="${1:?Usage: $0 <version> <arch> [binary-path] [output-path]}"
ARCH="${2:?Usage: $0 <version> <arch> [binary-path] [output-path]}"
BINARY="${3:-}"

# shellcheck source=../lib/repo-paths.sh
source "$(cd "$(dirname "$0")" && pwd)/../lib/repo-paths.sh"

if [[ -z "$BINARY" ]]; then
  BINARY="$REPO_ROOT/target/release/offsend"
fi

if [[ ! -x "$BINARY" ]]; then
  echo "offsend binary is not executable at $BINARY" >&2
  exit 1
fi

OUTPUT="${4:-$REPO_ROOT/build/offsend-cli-${VERSION}-linux-${ARCH}.tar.gz}"
if [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$REPO_ROOT/$OUTPUT"
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

install -m 0755 "$BINARY" "$stage/offsend"
mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
tar -C "$stage" -czf "$OUTPUT" offsend

echo "Created $OUTPUT"
