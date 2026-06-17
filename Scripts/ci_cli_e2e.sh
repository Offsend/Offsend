#!/usr/bin/env bash
set -euo pipefail

CLI_INPUT="${1:?Usage: $0 <path-to-offsend-cli>}"
if [[ "$CLI_INPUT" = /* ]]; then
  CLI_PATH="$CLI_INPUT"
else
  CLI_PATH="$(pwd)/$CLI_INPUT"
fi

if [[ ! -x "$CLI_PATH" ]]; then
  echo "offsend CLI is not executable at $CLI_PATH" >&2
  exit 1
fi

"$CLI_PATH" --version
"$CLI_PATH" doctor --format json

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

repo="$workdir/repo"
mkdir -p "$repo"
git -C "$repo" init
git -C "$repo" config user.email "ci@example.com"
git -C "$repo" config user.name "Offsend CI"

# Use a realistic AKIA-shaped key; AWS doc sample `AKIAIOSFODNN7EXAMPLE` is filtered as a placeholder.
# offsend:ignore-next-line
printf '%s\n' "AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF" > "$repo/secrets.env"
git -C "$repo" add secrets.env

set +e
"$CLI_PATH" check --staged --working-directory "$repo" --fail-on block --quiet
check_status="$?"
set -e

if [[ "$check_status" -ne 1 ]]; then
  echo "Expected check --staged to fail with findings, got exit code $check_status" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --cli-path "$CLI_PATH"

set +e
git -C "$repo" commit -m "blocked by offsend hook"
commit_status="$?"
set -e

if [[ "$commit_status" -eq 0 ]]; then
  echo "Expected pre-commit hook to block commit with staged secret" >&2
  exit 1
fi

"$CLI_PATH" hook uninstall --path "$repo"
git -C "$repo" commit -m "commit succeeds after hook uninstall"

printf '%s\n' \
  "version: 1" \
  "" \
  "check:" \
  "  exclude:" \
  "    - secrets.env" > "$repo/.offsend.yml"

printf '%s\n' "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" > "$repo/secrets.env"
git -C "$repo" add .offsend.yml secrets.env

"$CLI_PATH" check --staged --working-directory "$repo" --fail-on block --quiet

echo "CLI E2E smoke passed."
