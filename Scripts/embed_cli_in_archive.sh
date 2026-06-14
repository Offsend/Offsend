#!/usr/bin/env bash
# Embeds the archived OffsendCLI product into the archived app bundle.
set -euo pipefail

ARCHIVE_PATH="${1:?Usage: $0 <path-to-Offsend.xcarchive>}"
APP_NAME="${2:-Offsend}"

CLI_SRC="${ARCHIVE_PATH}/Products/usr/local/bin/offsend"
APP_HELPERS="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app/Contents/Helpers"
CLI_DEST="${APP_HELPERS}/offsend"

if [[ ! -f "$CLI_SRC" ]]; then
  echo "error: OffsendCLI archived product not found at $CLI_SRC" >&2
  exit 1
fi

mkdir -p "$APP_HELPERS"
cp -f "$CLI_SRC" "$CLI_DEST"
chmod +x "$CLI_DEST"

echo "Embedded archived offsend CLI at $CLI_DEST"
