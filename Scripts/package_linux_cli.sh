#!/usr/bin/env bash
# Packages a Linux `offsend` binary into a release tarball.
set -euo pipefail

VERSION="${1:?Usage: $0 <version> <arch> [binary-path] [output-path]}"
ARCH="${2:?Usage: $0 <version> <arch> [binary-path] [output-path]}"
BINARY="${3:-.build/release/offsend}"

if [[ ! -x "$BINARY" ]]; then
  echo "offsend binary is not executable at $BINARY" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${4:-$ROOT/build/offsend-cli-${VERSION}-linux-${ARCH}.tar.gz}"
if [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$ROOT/$OUTPUT"
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

install -m 0755 "$BINARY" "$stage/offsend"
mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
tar -C "$stage" -czf "$OUTPUT" offsend

echo "Created $OUTPUT"
