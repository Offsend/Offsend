#!/usr/bin/env bash
# Packages the embedded Rust offsend CLI for Homebrew distribution.
set -euo pipefail

APP_PATH="${1:?Usage: $0 <path-to-Offsend.app> <output-zip>}"
OUTPUT_ZIP="${2:?Usage: $0 <path-to-Offsend.app> <output-zip>}"
if [[ "$OUTPUT_ZIP" != /* ]]; then
  OUTPUT_ZIP="$(pwd)/$OUTPUT_ZIP"
fi

CLI_PATH="${APP_PATH}/Contents/Helpers/offsend"

if [[ ! -f "$CLI_PATH" ]]; then
  echo "Embedded CLI not found at $CLI_PATH" >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp "$CLI_PATH" "$stage/offsend"
chmod +x "$stage/offsend"

mkdir -p "$(dirname "$OUTPUT_ZIP")"
rm -f "$OUTPUT_ZIP"
(
  cd "$stage"
  zip -q -r -X "$OUTPUT_ZIP" offsend
)

echo "Created $OUTPUT_ZIP"
