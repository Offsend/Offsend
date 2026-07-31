#!/usr/bin/env bash
# Embeds the Rust offsend CLI into an already-exported, signed Offsend.app and re-seals it.
#
# Build with `cargo build -p offsend-cli --release` (or scripts/cli/build.sh) and set
# OFFSEND_CLI_SRC to that binary. The release workflow injects the prebuilt artifact this way
# so exportArchive never re-signs a foreign helper without the hardened runtime.
set -euo pipefail

APP_PATH="${1:?Usage: $0 <Offsend.app> <team-id> <entitlements>}"
TEAM_ID="${2:?Usage: $0 <Offsend.app> <team-id> <entitlements>}"
ENTITLEMENTS="${3:?Usage: $0 <Offsend.app> <team-id> <entitlements>}"

test -d "$APP_PATH" || { echo "error: app not found at $APP_PATH" >&2; exit 1; }
test -f "$ENTITLEMENTS" || { echo "error: entitlements not found at $ENTITLEMENTS" >&2; exit 1; }

CLI_SRC="${OFFSEND_CLI_SRC:-}"
if [[ -z "$CLI_SRC" || ! -f "$CLI_SRC" ]]; then
  echo "error: set OFFSEND_CLI_SRC to a built Rust offsend binary" >&2
  exit 1
fi
if ! file -b "$CLI_SRC" | grep -q "Mach-O.*executable"; then
  echo "error: OFFSEND_CLI_SRC at $CLI_SRC is not a Mach-O executable" >&2
  exit 1
fi

SIGN_IDENTITY="$(
  security find-identity -v -p codesigning |
    sed -n "s/.*\"\(Developer ID Application: .*(${TEAM_ID})\)\".*/\1/p" |
    head -n 1
)"
test -n "$SIGN_IDENTITY" || { echo "error: Developer ID Application identity not found for team ${TEAM_ID}" >&2; exit 1; }

APP_HELPERS="$APP_PATH/Contents/Helpers"
CLI_DEST="$APP_HELPERS/offsend"
mkdir -p "$APP_HELPERS"
cp -f "$CLI_SRC" "$CLI_DEST"
chmod +x "$CLI_DEST"

# Sign the CLI first (inside-out) with the hardened runtime, then re-seal the app around it.
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$CLI_DEST"
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Embedded + signed offsend CLI from $CLI_SRC -> $CLI_DEST"
