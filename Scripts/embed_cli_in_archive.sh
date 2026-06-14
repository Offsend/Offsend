#!/usr/bin/env bash
# Injects the OffsendCLI product into the archived app bundle so that
# `xcodebuild -exportArchive` re-signs it together with the rest of the bundle.
#
# The CLI builds with SKIP_INSTALL=YES (to keep the .xcarchive a valid single-app
# archive), so it is not present under the archive's Products. It is located in the
# archive build products instead. Runs in the workflow, outside Xcode's user-script
# sandbox, so reading the build products is allowed.
set -euo pipefail

ARCHIVE_PATH="${1:?Usage: $0 <path-to-Offsend.xcarchive> <derived-data-path> [app-name]}"
DERIVED_DATA="${2:?Usage: $0 <path-to-Offsend.xcarchive> <derived-data-path> [app-name]}"
APP_NAME="${3:-Offsend}"

if [[ ! -d "$DERIVED_DATA/Build" ]]; then
  echo "error: build products directory not found at $DERIVED_DATA/Build" >&2
  exit 1
fi

# Locate the executable named 'offsend', excluding the dSYM bundle (its DWARF file is also
# named 'offsend'). Prefer the archive's BuildProductsPath, then fall back to any match.
find_cli() {
  /usr/bin/find "$DERIVED_DATA/Build" -type f -name offsend -not -path '*.dSYM/*' "$@" 2>/dev/null
}

CLI_SRC="$(find_cli -path '*BuildProductsPath*' | head -n 1)"
if [[ -z "$CLI_SRC" ]]; then
  CLI_SRC="$(find_cli | head -n 1)"
fi

if [[ -z "$CLI_SRC" || ! -f "$CLI_SRC" ]]; then
  echo "error: built OffsendCLI product 'offsend' not found under $DERIVED_DATA/Build" >&2
  exit 1
fi

if ! file -b "$CLI_SRC" | grep -q "Mach-O.*executable"; then
  echo "error: located 'offsend' at $CLI_SRC is not a Mach-O executable" >&2
  exit 1
fi

APP_HELPERS="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app/Contents/Helpers"
CLI_DEST="${APP_HELPERS}/offsend"

mkdir -p "$APP_HELPERS"
cp -f "$CLI_SRC" "$CLI_DEST"
chmod +x "$CLI_DEST"

echo "Embedded archived offsend CLI from $CLI_SRC -> $CLI_DEST"
