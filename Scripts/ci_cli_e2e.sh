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

staged_tmp="$workdir/staged-tmp"
mkdir -p "$staged_tmp"
set +e
TMPDIR="$staged_tmp" "$CLI_PATH" check --staged --working-directory "$repo" --fail-on block --quiet
check_status="$?"
set -e

if [[ "$check_status" -ne 1 ]]; then
  echo "Expected check --staged to fail with findings, got exit code $check_status" >&2
  exit 1
fi
if compgen -G "$staged_tmp/offsend-staged-*" >/dev/null; then
  echo "Expected staged temporary files to be cleaned up" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target git --cli-path "$CLI_PATH"

set +e
git -C "$repo" commit -m "blocked by offsend hook"
commit_status="$?"
set -e

if [[ "$commit_status" -eq 0 ]]; then
  echo "Expected pre-commit hook to block commit with staged secret" >&2
  exit 1
fi

"$CLI_PATH" hook uninstall --path "$repo" --target git
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

printf '%s\n' '%PDF-1.4 fake' > "$repo/scan.pdf"
git -C "$repo" add scan.pdf

set +e
check_pdf_output="$("$CLI_PATH" check --staged --working-directory "$repo" --verbose 2>&1)"
check_pdf_status="$?"
set -e

if [[ "$check_pdf_status" -ne 2 ]]; then
  echo "Expected check on unscannable PDF to exit 2, got exit code $check_pdf_status" >&2
  echo "$check_pdf_output" >&2
  exit 1
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  if ! echo "$check_pdf_output" | grep -q "Unsupported format (.pdf)"; then
    echo "Expected Linux check to report unsupported PDF format" >&2
    echo "$check_pdf_output" >&2
    exit 1
  fi
else
  if ! echo "$check_pdf_output" | grep -qE "Invalid PDF|Unsupported format"; then
    echo "Expected macOS check to skip PDF with Invalid PDF or Unsupported format" >&2
    echo "$check_pdf_output" >&2
    exit 1
  fi
fi

# Prompt stdin check + adapters.
set +e
stdin_json_output="$(printf '%s' 'AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF' | "$CLI_PATH" check --stdin --format json --fail-on none --quiet)"
stdin_json_status="$?"
set -e
if [[ "$stdin_json_status" -ne 0 ]]; then
  echo "Expected check --stdin --fail-on none to exit 0, got $stdin_json_status" >&2
  exit 1
fi
if ! echo "$stdin_json_output" | grep -q 'awsAccessKeyId\|<stdin>'; then
  echo "Expected check --stdin JSON to mention the finding" >&2
  echo "$stdin_json_output" >&2
  exit 1
fi

hook_payload='{"prompt":"AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF please deploy"}'
set +e
adapter_output="$(printf '%s' "$hook_payload" | "$CLI_PATH" check --adapter cursor --hook-policy advise --no-notify 2>/tmp/offsend-adapter-stderr.$$)"
adapter_status="$?"
set -e
adapter_stderr="$(cat /tmp/offsend-adapter-stderr.$$)"
rm -f /tmp/offsend-adapter-stderr.$$
if [[ "$adapter_status" -ne 0 ]]; then
  echo "Expected check --adapter cursor --hook-policy advise to exit 0, got $adapter_status" >&2
  echo "$adapter_output" >&2
  echo "$adapter_stderr" >&2
  exit 1
fi
if ! echo "$adapter_output" | grep -q '"continue"'; then
  echo "Expected cursor adapter stdout to include continue" >&2
  echo "$adapter_output" >&2
  exit 1
fi
if ! echo "$adapter_stderr" | grep -qi 'offsend'; then
  echo "Expected cursor adapter stderr advice" >&2
  echo "$adapter_stderr" >&2
  exit 1
fi
if echo "$adapter_stderr" | grep -q 'AKIA'; then
  echo "stderr must not contain secret material" >&2
  echo "$adapter_stderr" >&2
  exit 1
fi

set +e
soft_block_output="$(printf '%s' "$hook_payload" | "$CLI_PATH" check --adapter cursor --hook-policy soft-block --no-notify 2>/dev/null)"
soft_block_status="$?"
set -e
if [[ "$soft_block_status" -ne 0 ]]; then
  echo "Expected cursor soft-block to exit 0, got $soft_block_status" >&2
  exit 1
fi
if ! echo "$soft_block_output" | grep -q '"continue":false\|"continue": false'; then
  echo "Expected cursor soft-block continue:false" >&2
  echo "$soft_block_output" >&2
  exit 1
fi

set +e
claude_output="$(printf '%s' "$hook_payload" | "$CLI_PATH" check --adapter claude --hook-policy advise --no-notify 2>/dev/null)"
set -e
if ! echo "$claude_output" | grep -q 'systemMessage'; then
  echo "Expected claude advise systemMessage" >&2
  echo "$claude_output" >&2
  exit 1
fi

windsurf_payload='{"agent_action_name":"pre_user_prompt","tool_info":{"user_prompt":"AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF please deploy"}}'
set +e
printf '%s' "$windsurf_payload" | "$CLI_PATH" check --adapter windsurf --hook-policy block --no-notify >/dev/null 2>/tmp/offsend-windsurf-stderr.$$
windsurf_status="$?"
set -e
if [[ "$windsurf_status" -ne 2 ]]; then
  echo "Expected windsurf block to exit 2, got $windsurf_status" >&2
  cat /tmp/offsend-windsurf-stderr.$$ >&2
  rm -f /tmp/offsend-windsurf-stderr.$$
  exit 1
fi
rm -f /tmp/offsend-windsurf-stderr.$$

# Fail-open on invalid hook JSON.
set +e
fail_open_stderr="$(printf '%s' 'not-json' | "$CLI_PATH" check --adapter cursor --hook-policy soft-block --no-notify 2>&1 >/tmp/offsend-fail-open-out.$$)"
fail_open_status="$?"
fail_open_output="$(cat /tmp/offsend-fail-open-out.$$)"
rm -f /tmp/offsend-fail-open-out.$$
set -e
if [[ "$fail_open_status" -ne 0 ]]; then
  echo "Expected fail-open exit 0, got $fail_open_status" >&2
  exit 1
fi
if ! echo "$fail_open_output" | grep -q '"continue":true\|"continue": true'; then
  echo "Expected fail-open continue:true" >&2
  echo "$fail_open_output" >&2
  exit 1
fi
if ! echo "$fail_open_stderr" | grep -q 'invalid_json'; then
  echo "Expected fail-open stderr code invalid_json" >&2
  echo "$fail_open_stderr" >&2
  exit 1
fi
if echo "$fail_open_stderr" | grep -qE "/Users/|/home/"; then
  echo "fail-open stderr must not leak home paths" >&2
  echo "$fail_open_stderr" >&2
  exit 1
fi

# Invalid --hook-policy must fail-open (not exit 2).
set +e
invalid_policy_stderr="$(printf '%s' '{"prompt":"hi"}' | "$CLI_PATH" check --adapter cursor --hook-policy hard-block --no-notify 2>&1 >/tmp/offsend-invalid-policy-out.$$)"
invalid_policy_status="$?"
invalid_policy_output="$(cat /tmp/offsend-invalid-policy-out.$$)"
rm -f /tmp/offsend-invalid-policy-out.$$
set -e
if [[ "$invalid_policy_status" -ne 0 ]]; then
  echo "Expected invalid hook-policy fail-open exit 0, got $invalid_policy_status" >&2
  exit 1
fi
if ! echo "$invalid_policy_output" | grep -q '"continue":true\|"continue": true'; then
  echo "Expected invalid hook-policy fail-open continue:true" >&2
  echo "$invalid_policy_output" >&2
  exit 1
fi
if ! echo "$invalid_policy_stderr" | grep -q 'invalid_hook_policy'; then
  echo "Expected invalid hook-policy stderr code invalid_hook_policy" >&2
  echo "$invalid_policy_stderr" >&2
  exit 1
fi

# block without seal key differs from soft-block; with key attempts seal.
no_key_home="$workdir/no-key-home"
mkdir -p "$no_key_home"
set +e
block_no_key_out="$(printf '%s' "$hook_payload" | HOME="$no_key_home" "$CLI_PATH" check --adapter cursor --hook-policy block --no-notify 2>/tmp/offsend-block-stderr.$$)"
block_no_key_status="$?"
set -e
if [[ "$block_no_key_status" -ne 0 ]]; then
  echo "Expected cursor block exit 0, got $block_no_key_status" >&2
  exit 1
fi
if ! echo "$block_no_key_out" | grep -qi 'seal unavailable\|Blocked'; then
  echo "Expected block user_message to mention seal unavailable" >&2
  echo "$block_no_key_out" >&2
  cat /tmp/offsend-block-stderr.$$ >&2
  rm -f /tmp/offsend-block-stderr.$$
  exit 1
fi
if ! grep -q 'keygen --default' /tmp/offsend-block-stderr.$$; then
  echo "Expected block stderr keygen --default hint" >&2
  cat /tmp/offsend-block-stderr.$$ >&2
  rm -f /tmp/offsend-block-stderr.$$
  exit 1
fi
rm -f /tmp/offsend-block-stderr.$$

seal_key="$repo/.offsend-seal-test.key"
"$CLI_PATH" keygen -o "$seal_key"
set +e
block_with_key_out="$(printf '%s' "$hook_payload" | "$CLI_PATH" check --adapter cursor --hook-policy block --no-notify --key-file "$seal_key" 2>/dev/null)"
set -e
if ! echo "$block_with_key_out" | grep -qi 'clipboard\|Sealed'; then
  echo "Expected block with key to mention sealed clipboard" >&2
  echo "$block_with_key_out" >&2
  exit 1
fi

# Seal/unseal safe I/O contract.
seal_work="$workdir/seal-work"
mkdir -p "$seal_work/keys"
cp "$seal_key" "$seal_work/keys/work.key"
printf '%s' 'contact=user@example.com' > "$seal_work/input.txt"
"$CLI_PATH" seal input.txt --working-directory "$seal_work" --key-file keys/work.key -o sealed.txt --quiet
"$CLI_PATH" unseal sealed.txt --working-directory "$seal_work" --key-file keys/work.key -o restored.txt
if [[ "$(cat "$seal_work/restored.txt")" != 'contact=user@example.com' ]]; then
  echo "Expected relative --key-file to use --working-directory" >&2
  exit 1
fi

set +e
"$CLI_PATH" unseal sealed.txt --working-directory "$seal_work" --key-file keys/work.key -o restored.txt 2>/dev/null
overwrite_status="$?"
set -e
if [[ "$overwrite_status" -eq 0 ]]; then
  echo "Expected existing output to require --force" >&2
  exit 1
fi
"$CLI_PATH" unseal sealed.txt --working-directory "$seal_work" --key-file keys/work.key -o restored.txt --force

cp "$seal_work/sealed.txt" "$seal_work/in-place.txt"
"$CLI_PATH" unseal in-place.txt --working-directory "$seal_work" --key-file keys/work.key -o in-place.txt --force
if [[ "$(cat "$seal_work/in-place.txt")" != 'contact=user@example.com' ]]; then
  echo "Expected --force to support atomic in-place output" >&2
  exit 1
fi

printf '%s' 'target sentinel' > "$seal_work/target.txt"
ln -s target.txt "$seal_work/output-link.txt"
"$CLI_PATH" unseal sealed.txt --working-directory "$seal_work" --key-file keys/work.key -o output-link.txt --force
if [[ -L "$seal_work/output-link.txt" || "$(cat "$seal_work/target.txt")" != 'target sentinel' ]]; then
  echo "Expected --force to replace output symlink without modifying its target" >&2
  exit 1
fi

dd if=/dev/zero bs=1048576 count=2 2>/dev/null | tr '\0' a > "$seal_work/exact-limit.txt"
"$CLI_PATH" seal exact-limit.txt --working-directory "$seal_work" --key-file keys/work.key -o exact-limit.out --quiet
printf 'x' >> "$seal_work/exact-limit.txt"
set +e
"$CLI_PATH" seal exact-limit.txt --working-directory "$seal_work" --key-file keys/work.key --quiet >/dev/null 2>&1
oversize_status="$?"
set -e
if [[ "$oversize_status" -ne 2 ]]; then
  echo "Expected file input larger than 2 MiB to exit 2, got $oversize_status" >&2
  exit 1
fi

inline_key_secret='INLINE_KEY_MUST_NOT_APPEAR'
set +e
inline_key_error="$("$CLI_PATH" seal "$seal_work/input.txt" --key "$inline_key_secret" 2>&1)"
inline_key_status="$?"
set -e
if [[ "$inline_key_status" -eq 0 || "$inline_key_error" == *"$inline_key_secret"* ]]; then
  echo "Expected removed --key option to reject without echoing its value" >&2
  exit 1
fi

# Seal key storage: refuse overwrite, auto-resolve ~/.offsend/seal.key
offsend_home="$(mktemp -d)"
(
  export HOME="$offsend_home"
  "$CLI_PATH" keygen --default
  set +e
  "$CLI_PATH" keygen --default 2>/tmp/offsend-keygen-dup.$$
  dup_status="$?"
  set -e
  if [[ "$dup_status" -eq 0 ]]; then
    echo "Expected duplicate keygen --default to fail" >&2
    exit 1
  fi
  if ! grep -qi 'already exists' /tmp/offsend-keygen-dup.$$; then
    echo "Expected overwrite refusal message" >&2
    cat /tmp/offsend-keygen-dup.$$ >&2
    exit 1
  fi
  rm -f /tmp/offsend-keygen-dup.$$

  set +e
  block_default_out="$(printf '%s' "$hook_payload" | "$CLI_PATH" check --adapter cursor --hook-policy block --no-notify 2>/dev/null)"
  set -e
  if ! echo "$block_default_out" | grep -qi 'clipboard\|Sealed'; then
    echo "Expected block with default seal key to mention sealed clipboard" >&2
    echo "$block_default_out" >&2
    exit 1
  fi

  "$CLI_PATH" keygen --name work
  if [[ ! -f "$offsend_home/.offsend/keys/work.key" ]]; then
    echo "Expected named seal key file" >&2
    exit 1
  fi
)
rm -rf "$offsend_home"

# --stdin risk report vs --gate-secrets / adapter gate
email_payload='contact me at user@example.com'
set +e
email_gate="$(printf '%s' "$email_payload" | "$CLI_PATH" check --stdin --gate-secrets --no-secrets-only 2>/dev/null)"
email_gate_status="$?"
set -e
if [[ "$email_gate_status" -ne 0 ]]; then
  echo "Expected email-only gate exit 0, got $email_gate_status" >&2
  echo "$email_gate" >&2
  exit 1
fi
if ! echo "$email_gate" | grep -q '"hasSecrets":false\|"hasSecrets": false'; then
  echo "Expected email-only gate hasSecrets:false" >&2
  echo "$email_gate" >&2
  exit 1
fi
set +e
akia_gate="$(printf '%s' 'AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF' | "$CLI_PATH" check --stdin --gate-secrets 2>/dev/null)"
akia_gate_status="$?"
set -e
if [[ "$akia_gate_status" -eq 0 ]]; then
  echo "Expected AKIA gate to exit non-zero" >&2
  echo "$akia_gate" >&2
  exit 1
fi
if ! echo "$akia_gate" | grep -q '"hasSecrets":true\|"hasSecrets": true'; then
  echo "Expected AKIA gate hasSecrets:true" >&2
  echo "$akia_gate" >&2
  exit 1
fi

# Read-gate path denylist + fail-open shape
read_env='{"file_path":"/repo/.env"}'
read_kube='{"file_path":"/home/user/.kube/config"}'
read_readme='{"file_path":"/repo/README.md"}'
set +e
read_deny="$(printf '%s' "$read_env" | "$CLI_PATH" check --adapter cursor --read-gate --no-notify 2>/dev/null)"
read_kube_deny="$(printf '%s' "$read_kube" | "$CLI_PATH" check --adapter cursor --read-gate --no-notify 2>/dev/null)"
read_allow="$(printf '%s' "$read_readme" | "$CLI_PATH" check --adapter cursor --read-gate --no-notify 2>/dev/null)"
read_fail_open="$(printf '%s' 'not-json' | "$CLI_PATH" check --adapter cursor --read-gate --no-notify 2>/dev/null)"
set -e
if ! echo "$read_deny" | grep -q 'deny'; then
  echo "Expected read-gate deny for .env" >&2
  echo "$read_deny" >&2
  exit 1
fi
if ! echo "$read_kube_deny" | grep -q 'deny'; then
  echo "Expected read-gate deny for .kube/config" >&2
  echo "$read_kube_deny" >&2
  exit 1
fi
if ! echo "$read_allow" | grep -q 'allow'; then
  echo "Expected read-gate allow for README.md" >&2
  echo "$read_allow" >&2
  exit 1
fi
if ! echo "$read_fail_open" | grep -q 'permission'; then
  echo "Expected read-gate fail-open permission:allow (not continue)" >&2
  echo "$read_fail_open" >&2
  exit 1
fi
if echo "$read_fail_open" | grep -q 'continue'; then
  echo "read-gate fail-open must not use prompt-submit continue shape" >&2
  echo "$read_fail_open" >&2
  exit 1
fi
# Refuse missing repository paths and preserve foreign wrappers unless forced.
set +e
"$CLI_PATH" hook install --path "$repo/missing-project" --target cursor --cli-path "$CLI_PATH" >/dev/null 2>&1
missing_hook_status="$?"
set -e
if [[ "$missing_hook_status" -eq 0 || -e "$repo/missing-project" ]]; then
  echo "Expected AI hook install to reject a missing repository path" >&2
  exit 1
fi

mkdir -p "$repo/.offsend/hooks"
printf '%s\n' '#!/bin/sh' 'echo custom-wrapper' > "$repo/.offsend/hooks/check-prompt.sh"
set +e
"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" >/dev/null 2>&1
foreign_wrapper_status="$?"
set -e
if [[ "$foreign_wrapper_status" -eq 0 ]] || ! grep -q 'custom-wrapper' "$repo/.offsend/hooks/check-prompt.sh"; then
  echo "Expected AI hook install to preserve a foreign wrapper without --force" >&2
  exit 1
fi

# Preserve a foreign Cursor config hook, then merge Offsend.
mkdir -p "$repo/.cursor"
printf '%s\n' '{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [ { "command": "./hooks/audit.sh" } ]
  }
}' > "$repo/.cursor/hooks.json"

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --force
"$CLI_PATH" hook status --path "$repo" --target cursor
"$CLI_PATH" hook status --path "$repo" --target all --format json | grep -q '"targets"'
if ! "$CLI_PATH" hook status --path "$repo" --target all; then
  echo "hook status --target all should succeed when hooks are healthy" >&2
  exit 1
fi
if ! grep -q "check-prompt.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected cursor hooks.json to reference wrapper script" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "beforeShellExecution" "$repo/.cursor/hooks.json"; then
  echo "Expected merge to keep foreign beforeShellExecution hook" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q -- "--no-notify" "$repo/.offsend/hooks/check-prompt.sh"; then
  echo "Expected wrapper to pass --no-notify" >&2
  exit 1
fi
if ! grep -q "beforeReadFile" "$repo/.cursor/hooks.json"; then
  echo "Expected read-gate on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ ! -x "$repo/.offsend/hooks/check-read.sh" ]]; then
  echo "Expected check-read.sh wrapper" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-read-gate
if grep -q "beforeReadFile" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-read-gate to remove beforeReadFile" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ -e "$repo/.offsend/hooks/check-read.sh" ]]; then
  echo "Expected --no-read-gate to remove orphan check-read.sh" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-read-gate
if ! grep -q "beforeReadFile" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-read-gate alias to add beforeReadFile" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

# Shell gate is opt-in: ask on sensitive paths, allow otherwise.
# (The foreign beforeShellExecution audit.sh entry above must survive the merge.)
"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --shell-gate
if ! grep -q "check-shell.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --shell-gate to add the check-shell.sh entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ ! -x "$repo/.offsend/hooks/check-shell.sh" ]]; then
  echo "Expected check-shell.sh wrapper" >&2
  exit 1
fi
shell_ask="$(printf '%s' '{"command":"cat .env"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_ask" | grep -q '"ask"'; then
  echo "Expected shell-gate ask for 'cat .env'" >&2
  echo "$shell_ask" >&2
  exit 1
fi
shell_allow="$(printf '%s' '{"command":"ls -la src"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_allow" | grep -q '"allow"'; then
  echo "Expected shell-gate allow for 'ls -la src'" >&2
  echo "$shell_allow" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH"
if grep -q "check-shell.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected reinstall without --shell-gate to remove the check-shell.sh entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "audit.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected foreign beforeShellExecution hook to survive shell-gate removal" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ -e "$repo/.offsend/hooks/check-shell.sh" ]]; then
  echo "Expected reinstall without --shell-gate to remove orphan check-shell.sh" >&2
  exit 1
fi

"$CLI_PATH" hook uninstall --path "$repo" --target cursor
if grep -q "check-prompt.sh" "$repo/.cursor/hooks.json" 2>/dev/null; then
  echo "Expected uninstall to remove Offsend cursor hook entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "beforeShellExecution" "$repo/.cursor/hooks.json"; then
  echo "Expected uninstall to keep foreign hooks" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

# Default install/status/uninstall: git hook + detected AI editors ($HOME drives detection).
combined="$workdir/combined"
combined_home="$workdir/combined-home"
mkdir -p "$combined" "$combined_home/.codex"
git -C "$combined" init

HOME="$combined_home" "$CLI_PATH" hook install --path "$combined" --cli-path "$CLI_PATH"
if [[ ! -x "$combined/.git/hooks/pre-commit" ]]; then
  echo "Expected default install to add the git pre-commit hook" >&2
  exit 1
fi
if ! grep -q "check-prompt.sh" "$combined/.cursor/hooks.json"; then
  echo "Expected default install to add the cursor hook" >&2
  exit 1
fi
if ! grep -q "check-prompt.sh" "$combined/.claude/settings.json"; then
  echo "Expected default install to add the claude hook" >&2
  exit 1
fi
if ! grep -q "check-prompt.sh" "$combined/.codex/hooks.json"; then
  echo "Expected default install to add the codex hook (~/.codex detected)" >&2
  exit 1
fi
if [[ -e "$combined/.windsurf/hooks.json" ]]; then
  echo "Expected default install to skip windsurf (not detected)" >&2
  exit 1
fi
# Multi-target install must keep check-read.sh for cursor/claude even after
# installing gate-unsupported targets (codex) that run cleanup afterward.
if [[ ! -x "$combined/.offsend/hooks/check-read.sh" ]]; then
  echo "Expected default install to keep check-read.sh after codex install" >&2
  ls -la "$combined/.offsend/hooks/" >&2
  exit 1
fi
if ! grep -q "beforeReadFile" "$combined/.cursor/hooks.json"; then
  echo "Expected default install to keep cursor beforeReadFile" >&2
  cat "$combined/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook status --path "$combined"
"$CLI_PATH" hook status --path "$combined" --format json | grep -q '"git"'

"$CLI_PATH" hook uninstall --path "$combined"
if [[ -e "$combined/.git/hooks/pre-commit" ]]; then
  echo "Expected default uninstall to remove the git hook" >&2
  exit 1
fi
if grep -q "check-prompt.sh" "$combined/.cursor/hooks.json" 2>/dev/null; then
  echo "Expected default uninstall to remove the cursor hook" >&2
  exit 1
fi
set +e
"$CLI_PATH" hook status --path "$combined" >/dev/null
combined_status="$?"
set -e
if [[ "$combined_status" -ne 3 ]]; then
  echo "Expected combined status to exit 3 after uninstall, got $combined_status" >&2
  exit 1
fi

# offsend ignore: append patterns to existing AI ignore files, create the set when absent.
ignore_dir="$workdir/ignore-proj"
mkdir -p "$ignore_dir/secrets"
printf '%s\n' "# mine" > "$ignore_dir/.cursorignore"

"$CLI_PATH" ignore --path "$ignore_dir" secrets 'config/prod.json'
if ! grep -q "secrets/" "$ignore_dir/.cursorignore"; then
  echo "Expected ignore to append the directory pattern with a trailing slash" >&2
  cat "$ignore_dir/.cursorignore" >&2
  exit 1
fi
if ! grep -q "config/prod.json" "$ignore_dir/.cursorignore"; then
  echo "Expected ignore to append the file pattern" >&2
  exit 1
fi
if [[ -e "$ignore_dir/.claudeignore" ]]; then
  echo "Expected ignore to leave missing ignore files absent when one exists" >&2
  exit 1
fi

ignore_fresh="$workdir/ignore-fresh"
mkdir -p "$ignore_fresh"
"$CLI_PATH" ignore --path "$ignore_fresh" '*.pem' --format json | grep -q '"createdRelativePaths"'
if ! grep -q '\*.pem' "$ignore_fresh/.cursorignore" || ! grep -q '\*.pem' "$ignore_fresh/.claudeignore"; then
  echo "Expected ignore to create the standard set with the pattern" >&2
  exit 1
fi
if [[ -e "$ignore_fresh/.gitignore" ]]; then
  echo "Expected ignore to never touch .gitignore" >&2
  exit 1
fi

echo "CLI E2E smoke passed."
