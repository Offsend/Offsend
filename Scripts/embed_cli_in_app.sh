#!/usr/bin/env bash
# Embeds the OffsendCLI product into an already-exported, signed Offsend.app and re-seals it.
#
# The CLI builds with SKIP_INSTALL=YES, so it is not part of the .xcarchive and is therefore not
# handled by `xcodebuild -exportArchive`. (When the CLI was injected before export, exportArchive
# re-signed it as a foreign helper WITHOUT the hardened runtime, failing notarization.) Instead we
# embed it into the exported app, sign the CLI ourselves with the hardened runtime + a secure
# timestamp, then re-sign (re-seal) the outer app around it. This runs in the release workflow,
# outside Xcode's user-script sandbox, so reading the build products is allowed.
set -euo pipefail

APP_PATH="${1:?Usage: $0 <Offsend.app> <derived-data-path> <team-id> <entitlements>}"
DERIVED_DATA="${2:?Usage: $0 <Offsend.app> <derived-data-path> <team-id> <entitlements>}"
TEAM_ID="${3:?Usage: $0 <Offsend.app> <derived-data-path> <team-id> <entitlements>}"
ENTITLEMENTS="${4:?Usage: $0 <Offsend.app> <derived-data-path> <team-id> <entitlements>}"

test -d "$APP_PATH" || { echo "error: app not found at $APP_PATH" >&2; exit 1; }
test -f "$ENTITLEMENTS" || { echo "error: entitlements not found at $ENTITLEMENTS" >&2; exit 1; }
test -d "$DERIVED_DATA/Build" || { echo "error: build products not found at $DERIVED_DATA/Build" >&2; exit 1; }

SIGN_IDENTITY="$(
  security find-identity -v -p codesigning |
    sed -n "s/.*\"\(Developer ID Application: .*(${TEAM_ID})\)\".*/\1/p" |
    head -n 1
)"
test -n "$SIGN_IDENTITY" || { echo "error: Developer ID Application identity not found for team ${TEAM_ID}" >&2; exit 1; }

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
