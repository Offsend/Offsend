#!/usr/bin/env bash
# Copies the OffsendCLI product into the app bundle and re-signs it for notarization.
set -euo pipefail

CLI_SRC="${BUILT_PRODUCTS_DIR}/offsend"
APP_HELPERS="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Helpers"
CLI_DEST="${APP_HELPERS}/offsend"

if [[ ! -f "$CLI_SRC" ]]; then
  echo "error: OffsendCLI product not found at $CLI_SRC" >&2
  exit 1
fi

mkdir -p "$APP_HELPERS"
cp -f "$CLI_SRC" "$CLI_DEST"
chmod +x "$CLI_DEST"

if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --options runtime --timestamp "$CLI_DEST"
fi

echo "Embedded offsend CLI at $CLI_DEST"
