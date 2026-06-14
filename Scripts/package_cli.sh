#!/usr/bin/env bash
# Packages the embedded offsend CLI plus app frameworks for Homebrew distribution.
set -euo pipefail

APP_PATH="${1:?Usage: $0 <path-to-Offsend.app> <output-zip>}"
OUTPUT_ZIP="${2:?Usage: $0 <path-to-Offsend.app> <output-zip>}"
if [[ "$OUTPUT_ZIP" != /* ]]; then
  OUTPUT_ZIP="$(pwd)/$OUTPUT_ZIP"
fi

CLI_PATH="${APP_PATH}/Contents/Helpers/offsend"
FRAMEWORKS_DIR="${APP_PATH}/Contents/Frameworks"

if [[ ! -f "$CLI_PATH" ]]; then
  echo "Embedded CLI not found at $CLI_PATH" >&2
  exit 1
fi

if [[ ! -d "$FRAMEWORKS_DIR" ]]; then
  echo "Frameworks directory not found at $FRAMEWORKS_DIR" >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp "$CLI_PATH" "$stage/offsend"
chmod +x "$stage/offsend"

mkdir -p "$stage/Frameworks"

queue=("$stage/offsend")
copied_frameworks=""

while ((${#queue[@]})); do
  current="${queue[0]}"
  queue=("${queue[@]:1}")

  while IFS= read -r dependency; do
    framework_name="$(sed -E 's#.*@rpath/([^/]+\.framework)/.*#\1#' <<<"$dependency")"
    [[ "$framework_name" == *.framework ]] || continue
    if [[ "$copied_frameworks" == *"|$framework_name|"* ]]; then
      continue
    fi

    source_framework="$FRAMEWORKS_DIR/$framework_name"
    if [[ ! -d "$source_framework" ]]; then
      echo "Required framework not found in app bundle: $framework_name" >&2
      exit 1
    fi

    ditto "$source_framework" "$stage/Frameworks/$framework_name"
    copied_frameworks="${copied_frameworks}|${framework_name}|"

    binary_name="${framework_name%.framework}"
    framework_binary="$stage/Frameworks/$framework_name/Versions/A/$binary_name"
    if [[ -f "$framework_binary" ]]; then
      queue+=("$framework_binary")
    fi
  done < <(otool -L "$current" | sed -n 's#^[[:space:]]*\(@rpath/.*\.framework/.*\) (.*#\1#p')
done

if ! otool -l "$stage/offsend" | grep -q "@executable_path/Frameworks"; then
  install_name_tool -add_rpath "@executable_path/Frameworks" "$stage/offsend"
fi

mkdir -p "$(dirname "$OUTPUT_ZIP")"
rm -f "$OUTPUT_ZIP"
(
  cd "$stage"
  zip -q -r -X "$OUTPUT_ZIP" offsend Frameworks
)

echo "Created $OUTPUT_ZIP"
