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

# Read-gate seal mode: deny hands the agent a sealed copy path (context.read.on_secret: seal).
seal_read_repo="$workdir/seal-read"
seal_read_home="$workdir/seal-read-home"
mkdir -p "$seal_read_repo" "$seal_read_home"
printf '%s\n' \
  "version: 1" \
  "" \
  "context:" \
  "  read:" \
  "    on_secret: seal" > "$seal_read_repo/.offsend.yml"
HOME="$seal_read_home" "$CLI_PATH" keygen --default >/dev/null

# offsend:ignore-next-line
read_seal_payload='{"file_path":"/repo/creds.env","content":"AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"}'
set +e
read_seal_out="$(printf '%s' "$read_seal_payload" | HOME="$seal_read_home" "$CLI_PATH" check --adapter cursor --read-gate --no-notify --working-directory "$seal_read_repo" 2>/dev/null)"
set -e
if ! echo "$read_seal_out" | grep -q '"deny"'; then
  echo "Expected seal-mode read-gate to still deny" >&2
  echo "$read_seal_out" >&2
  exit 1
fi
if ! echo "$read_seal_out" | grep -q 'agent_message'; then
  echo "Expected seal-mode deny to include agent_message" >&2
  echo "$read_seal_out" >&2
  exit 1
fi
# JSON-escaped slashes (\/) must be unescaped before extracting the path.
sealed_copy_path="$(echo "$read_seal_out" | sed 's|\\/|/|g' | { grep -o '/[^"]*offsend-seal/sealed-[^"]*\.txt' || true; } | head -1)"
if [[ -z "$sealed_copy_path" || ! -f "$sealed_copy_path" ]]; then
  echo "Expected seal-mode deny to reference an existing sealed copy" >&2
  echo "$read_seal_out" >&2
  exit 1
fi
if ! grep -q '{{' "$sealed_copy_path" || grep -q 'AKIA1234567890ABCDEF' "$sealed_copy_path"; then
  echo "Expected sealed copy to contain tokens and no plaintext secret" >&2
  cat "$sealed_copy_path" >&2
  exit 1
fi
# Read-gate must allow reading the sealed copy itself.
set +e
sealed_copy_allow="$(printf '%s' "{\"file_path\":\"$sealed_copy_path\"}" | HOME="$seal_read_home" "$CLI_PATH" check --adapter cursor --read-gate --no-notify --working-directory "$seal_read_repo" 2>/dev/null)"
set -e
if ! echo "$sealed_copy_allow" | grep -q '"allow"'; then
  echo "Expected read-gate to allow the sealed copy path" >&2
  echo "$sealed_copy_allow" >&2
  exit 1
fi
# offsend check on the sealed copy is clean (seal tokens are not live secrets).
if ! "$CLI_PATH" check "$sealed_copy_path" --fail-on block --quiet; then
  echo "Expected offsend check on the sealed copy to pass" >&2
  exit 1
fi
rm -f "$sealed_copy_path"

# Without a key, seal mode degrades to the plain deny (no agent_message).
no_seal_key_home="$workdir/seal-read-nokey"
mkdir -p "$no_seal_key_home"
set +e
read_nokey_out="$(printf '%s' "$read_seal_payload" | HOME="$no_seal_key_home" "$CLI_PATH" check --adapter cursor --read-gate --no-notify --working-directory "$seal_read_repo" 2>/dev/null)"
set -e
if ! echo "$read_nokey_out" | grep -q '"deny"'; then
  echo "Expected read-gate deny without seal key" >&2
  echo "$read_nokey_out" >&2
  exit 1
fi
if echo "$read_nokey_out" | grep -q 'agent_message'; then
  echo "Expected no sealed-copy agent_message without a key" >&2
  echo "$read_nokey_out" >&2
  exit 1
fi

# Shell gate asks before the agent runs offsend unseal.
set +e
unseal_ask="$(printf '%s' '{"command":"offsend unseal sealed.txt"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
set -e
if ! echo "$unseal_ask" | grep -q '"ask"'; then
  echo "Expected shell-gate ask for offsend unseal" >&2
  echo "$unseal_ask" >&2
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
if ! grep -q "check-shell.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected shell-gate on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ ! -x "$repo/.offsend/hooks/check-shell.sh" ]]; then
  echo "Expected check-shell.sh wrapper" >&2
  exit 1
fi
if ! grep -q "audit.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected foreign beforeShellExecution hook to survive shell-gate merge" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "check-mcp.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected mcp-gate on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "beforeMCPExecution" "$repo/.cursor/hooks.json"; then
  echo "Expected beforeMCPExecution on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ ! -x "$repo/.offsend/hooks/check-mcp.sh" ]]; then
  echo "Expected check-mcp.sh wrapper" >&2
  exit 1
fi
if ! grep -q "failClosed" "$repo/.cursor/hooks.json"; then
  echo "Expected failClosed on MCP/subagent Cursor gates" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "check-subagent.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected subagent-gate on by default for Cursor" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "subagentStart" "$repo/.cursor/hooks.json"; then
  echo "Expected subagentStart on by default for Cursor" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ ! -x "$repo/.offsend/hooks/check-subagent.sh" ]]; then
  echo "Expected check-subagent.sh wrapper" >&2
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

# Shell gate is on by default: ask on sensitive paths, allow otherwise.
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

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-shell-gate
if grep -q "check-shell.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-shell-gate to remove the check-shell.sh entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "audit.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected foreign beforeShellExecution hook to survive shell-gate removal" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ -e "$repo/.offsend/hooks/check-shell.sh" ]]; then
  echo "Expected --no-shell-gate to remove orphan check-shell.sh" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-shell-gate
if ! grep -q "check-shell.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-shell-gate alias to add check-shell.sh" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

# MCP gate: sensitive path → ask; clean args → allow; fail-open; policy deny; install toggles.
mcp_ask="$(printf '%s' '{"server":"github","tool_name":"read_file","tool_input":{"path":".env"}}' | "$CLI_PATH" check --adapter cursor --mcp-gate --no-notify 2>/dev/null)"
if ! echo "$mcp_ask" | grep -q '"ask"'; then
  echo "Expected mcp-gate ask for .env in tool args" >&2
  echo "$mcp_ask" >&2
  exit 1
fi
mcp_allow="$(printf '%s' '{"server":"github","tool_name":"search","tool_input":{"q":"README"}}' | "$CLI_PATH" check --adapter cursor --mcp-gate --no-notify 2>/dev/null)"
if ! echo "$mcp_allow" | grep -q '"allow"'; then
  echo "Expected mcp-gate allow for clean tool args" >&2
  echo "$mcp_allow" >&2
  exit 1
fi
mcp_fail_open="$(printf '%s' 'not-json' | "$CLI_PATH" check --adapter cursor --mcp-gate --no-notify 2>/dev/null)"
if ! echo "$mcp_fail_open" | grep -q 'permission'; then
  echo "Expected mcp-gate fail-open permission:allow" >&2
  echo "$mcp_fail_open" >&2
  exit 1
fi

mcp_policy_repo="$workdir/mcp-policy"
mkdir -p "$mcp_policy_repo"
printf '%s\n' \
  "version: 1" \
  "" \
  "context:" \
  "  mcp:" \
  "    mode: deny" \
  "    deny:" \
  "      - postgres" > "$mcp_policy_repo/.offsend.yml"
mcp_deny="$(printf '%s' '{"server":"postgres","tool_name":"query","tool_input":"{}"}' | "$CLI_PATH" check --adapter cursor --mcp-gate --no-notify --working-directory "$mcp_policy_repo" 2>/dev/null)"
if ! echo "$mcp_deny" | grep -q '"deny"'; then
  echo "Expected mcp-gate deny for context.mcp.deny postgres" >&2
  echo "$mcp_deny" >&2
  exit 1
fi
# Explicit mode: deny fails closed on unrecognized hook input (no silent allow).
mcp_invalid_deny="$(printf '%s' 'not-json' | "$CLI_PATH" check --adapter cursor --mcp-gate --no-notify --working-directory "$mcp_policy_repo" 2>/dev/null)"
if ! echo "$mcp_invalid_deny" | grep -q '"deny"'; then
  echo "Expected mcp-gate deny for invalid input under context.mcp.mode deny" >&2
  echo "$mcp_invalid_deny" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-mcp-gate
if grep -q "check-mcp.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-mcp-gate to remove the check-mcp.sh entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ -e "$repo/.offsend/hooks/check-mcp.sh" ]]; then
  echo "Expected --no-mcp-gate to remove orphan check-mcp.sh" >&2
  exit 1
fi
if ! grep -q "check-subagent.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-mcp-gate to keep subagent-gate" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-mcp-gate
if ! grep -q "check-mcp.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-mcp-gate alias to add check-mcp.sh" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

# MCP response gate: Cursor observe-only ({}), Claude warn/seal, fail-open, install toggles.
if ! grep -q "check-mcp-out.sh" "$repo/.cursor/hooks.json" || ! grep -q "afterMCPExecution" "$repo/.cursor/hooks.json"; then
  echo "Expected mcp-response-gate on by default (afterMCPExecution + check-mcp-out.sh)" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ ! -x "$repo/.offsend/hooks/check-mcp-out.sh" ]]; then
  echo "Expected check-mcp-out.sh wrapper" >&2
  exit 1
fi

# offsend:ignore-next-line
mcpresp_cursor_payload='{"tool_name":"query","command":"postgres","result_json":"AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"}'
set +e
mcpresp_cursor_out="$(printf '%s' "$mcpresp_cursor_payload" | "$CLI_PATH" check --adapter cursor --mcp-response-gate --no-notify 2>/tmp/offsend-mcpresp-stderr.$$)"
set -e
mcpresp_cursor_stderr="$(cat /tmp/offsend-mcpresp-stderr.$$)"
rm -f /tmp/offsend-mcpresp-stderr.$$
if [[ "$mcpresp_cursor_out" != "{}" ]]; then
  echo "Expected cursor mcp-response-gate stdout {} (observe-only)" >&2
  echo "$mcpresp_cursor_out" >&2
  exit 1
fi
if ! echo "$mcpresp_cursor_stderr" | grep -qi 'secrets'; then
  echo "Expected cursor mcp-response-gate stderr warning" >&2
  echo "$mcpresp_cursor_stderr" >&2
  exit 1
fi
if echo "$mcpresp_cursor_stderr" | grep -q 'AKIA'; then
  echo "mcp-response-gate stderr must not contain secret material" >&2
  exit 1
fi

mcpresp_warn_repo="$workdir/mcpresp-warn"
mkdir -p "$mcpresp_warn_repo"
printf '%s\n' \
  "version: 1" \
  "" \
  "context:" \
  "  mcp:" \
  "    responses: warn" > "$mcpresp_warn_repo/.offsend.yml"
# offsend:ignore-next-line
mcpresp_claude_payload='{"tool_name":"mcp__github__get_secret","tool_response":"AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"}'
set +e
mcpresp_warn_out="$(printf '%s' "$mcpresp_claude_payload" | "$CLI_PATH" check --adapter claude --mcp-response-gate --no-notify --working-directory "$mcpresp_warn_repo" 2>/dev/null)"
set -e
if ! echo "$mcpresp_warn_out" | grep -q 'additionalContext'; then
  echo "Expected claude warn mode additionalContext" >&2
  echo "$mcpresp_warn_out" >&2
  exit 1
fi
if echo "$mcpresp_warn_out" | grep -q 'updatedToolOutput'; then
  echo "warn mode must not rewrite tool output" >&2
  echo "$mcpresp_warn_out" >&2
  exit 1
fi

mcpresp_seal_repo="$workdir/mcpresp-seal"
mcpresp_seal_home="$workdir/mcpresp-seal-home"
mkdir -p "$mcpresp_seal_repo" "$mcpresp_seal_home"
printf '%s\n' \
  "version: 1" \
  "" \
  "context:" \
  "  mcp:" \
  "    responses: seal" > "$mcpresp_seal_repo/.offsend.yml"
HOME="$mcpresp_seal_home" "$CLI_PATH" keygen --default >/dev/null
set +e
mcpresp_seal_out="$(printf '%s' "$mcpresp_claude_payload" | HOME="$mcpresp_seal_home" "$CLI_PATH" check --adapter claude --mcp-response-gate --no-notify --working-directory "$mcpresp_seal_repo" 2>/dev/null)"
set -e
if ! echo "$mcpresp_seal_out" | grep -q 'updatedToolOutput'; then
  echo "Expected claude seal mode updatedToolOutput" >&2
  echo "$mcpresp_seal_out" >&2
  exit 1
fi
if ! echo "$mcpresp_seal_out" | grep -q 'updatedMCPToolOutput'; then
  echo "Expected claude seal mode legacy updatedMCPToolOutput alias" >&2
  echo "$mcpresp_seal_out" >&2
  exit 1
fi
if echo "$mcpresp_seal_out" | grep -q 'AKIA1234567890ABCDEF'; then
  echo "Sealed output must not contain the plaintext secret" >&2
  exit 1
fi
if ! echo "$mcpresp_seal_out" | grep -q 'v1\.'; then
  echo "Expected sealed output to contain seal tokens" >&2
  echo "$mcpresp_seal_out" >&2
  exit 1
fi

set +e
mcpresp_fail_open="$(printf '%s' 'not-json' | "$CLI_PATH" check --adapter claude --mcp-response-gate --no-notify 2>/dev/null)"
set -e
if [[ "$mcpresp_fail_open" != "{}" ]]; then
  echo "Expected mcp-response-gate fail-open {}" >&2
  echo "$mcpresp_fail_open" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-mcp-response-gate
if grep -q "check-mcp-out.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-mcp-response-gate to remove the check-mcp-out.sh entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ -e "$repo/.offsend/hooks/check-mcp-out.sh" ]]; then
  echo "Expected --no-mcp-response-gate to remove orphan check-mcp-out.sh" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-mcp-response-gate
if ! grep -q "check-mcp-out.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-mcp-response-gate alias to add check-mcp-out.sh" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

# Subagent gate (Cursor): secret in task → deny; clean task → allow; fail-open; install toggles.
# offsend:ignore-next-line
subagent_deny="$(printf '%s' '{"task":"use AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF","subagent_type":"explore"}' | "$CLI_PATH" check --adapter cursor --subagent-gate --no-notify 2>/dev/null)"
if ! echo "$subagent_deny" | grep -q '"deny"'; then
  echo "Expected subagent-gate deny for secret-shaped task" >&2
  echo "$subagent_deny" >&2
  exit 1
fi
subagent_allow="$(printf '%s' '{"task":"Explore the auth module","subagent_type":"explore"}' | "$CLI_PATH" check --adapter cursor --subagent-gate --no-notify 2>/dev/null)"
if ! echo "$subagent_allow" | grep -q '"allow"'; then
  echo "Expected subagent-gate allow for clean task" >&2
  echo "$subagent_allow" >&2
  exit 1
fi
subagent_fail_open="$(printf '%s' 'not-json' | "$CLI_PATH" check --adapter cursor --subagent-gate --no-notify 2>/dev/null)"
if ! echo "$subagent_fail_open" | grep -q 'permission'; then
  echo "Expected subagent-gate fail-open permission:allow" >&2
  echo "$subagent_fail_open" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-subagent-gate
if grep -q "check-subagent.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-subagent-gate to remove the check-subagent.sh entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if [[ -e "$repo/.offsend/hooks/check-subagent.sh" ]]; then
  echo "Expected --no-subagent-gate to remove orphan check-subagent.sh" >&2
  exit 1
fi
if ! grep -q "check-mcp.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-subagent-gate to keep mcp-gate" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-subagent-gate
if ! grep -q "check-subagent.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-subagent-gate alias to add check-subagent.sh" >&2
  cat "$repo/.cursor/hooks.json" >&2
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
if ! grep -q "PostToolUse" "$combined/.claude/settings.json" || ! grep -q "check-mcp-out.sh" "$combined/.claude/settings.json"; then
  echo "Expected default claude install to add PostToolUse mcp-response-gate" >&2
  cat "$combined/.claude/settings.json" >&2
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
if [[ ! -x "$combined/.offsend/hooks/check-mcp.sh" ]] || ! grep -q "beforeMCPExecution" "$combined/.cursor/hooks.json"; then
  echo "Expected default install to keep cursor mcp-gate after multi-target install" >&2
  cat "$combined/.cursor/hooks.json" >&2
  ls -la "$combined/.offsend/hooks/" >&2
  exit 1
fi
if [[ ! -x "$combined/.offsend/hooks/check-subagent.sh" ]] || ! grep -q "subagentStart" "$combined/.cursor/hooks.json"; then
  echo "Expected default install to keep cursor subagent-gate after multi-target install" >&2
  cat "$combined/.cursor/hooks.json" >&2
  ls -la "$combined/.offsend/hooks/" >&2
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

# offsend ignore --local: append patterns to existing AI ignore files, create the set when absent.
ignore_dir="$workdir/ignore-proj"
mkdir -p "$ignore_dir/secrets"
printf '%s\n' "# mine" > "$ignore_dir/.cursorignore"

"$CLI_PATH" ignore --local --path "$ignore_dir" secrets 'config/prod.json'
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
"$CLI_PATH" ignore --local --path "$ignore_fresh" '*.pem' --format json | grep -q '"createdRelativePaths"'
if ! grep -q '\*.pem' "$ignore_fresh/.cursorignore" || ! grep -q '\*.pem' "$ignore_fresh/.claudeignore"; then
  echo "Expected ignore to create the standard set with the pattern" >&2
  exit 1
fi
if [[ -e "$ignore_fresh/.gitignore" ]]; then
  echo "Expected ignore to never touch .gitignore" >&2
  exit 1
fi

# history audit: discover planted Cursor transcript under $HOME and flag secret shapes.
hist_repo="$workdir/hist-repo"
hist_home="$workdir/hist-home"
mkdir -p "$hist_repo"
# Match OffsendHistoryService.cursorProjectSlug (standardized path, no symlink resolve).
hist_slug="$(python3 -c "import os; p=os.path.abspath('$hist_repo'); print(p.lstrip('/').replace('/', '-').replace(' ', '-'))")"
hist_dir="$hist_home/.cursor/projects/$hist_slug/agent-transcripts/session-1"
mkdir -p "$hist_dir"
# offsend:ignore-next-line
printf '%s\n' '{"role":"user","content":"AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"}' > "$hist_dir/session-1.jsonl"

set +e
hist_audit="$(HOME="$hist_home" "$CLI_PATH" history audit --path "$hist_repo" --format json 2>/dev/null)"
hist_status="$?"
set -e
if [[ "$hist_status" -ne 1 ]]; then
  echo "Expected history audit to exit 1 with findings, got $hist_status" >&2
  echo "$hist_audit" >&2
  exit 1
fi
if ! echo "$hist_audit" | grep -Eq '"filesScanned"[[:space:]]*:[[:space:]]*1'; then
  echo "Expected history audit filesScanned:1" >&2
  echo "$hist_audit" >&2
  exit 1
fi
if ! echo "$hist_audit" | grep -Eq '"filesWithFindings"[[:space:]]*:[[:space:]]*1'; then
  echo "Expected history audit filesWithFindings:1" >&2
  echo "$hist_audit" >&2
  exit 1
fi

set +e
hist_scrub="$(HOME="$hist_home" "$CLI_PATH" history scrub --path "$hist_repo" --format json 2>/dev/null)"
hist_scrub_status="$?"
set -e
if [[ "$hist_scrub_status" -ne 0 ]]; then
  echo "Expected history scrub dry-run to exit 0, got $hist_scrub_status" >&2
  echo "$hist_scrub" >&2
  exit 1
fi
if ! echo "$hist_scrub" | grep -Eq '"dryRun"[[:space:]]*:[[:space:]]*true'; then
  echo "Expected history scrub dry-run dryRun:true" >&2
  echo "$hist_scrub" >&2
  exit 1
fi
if ! echo "$hist_scrub" | grep -Eq '"redactionCount"[[:space:]]*:[[:space:]]*[1-9]'; then
  echo "Expected history scrub dry-run redactionCount >= 1" >&2
  echo "$hist_scrub" >&2
  exit 1
fi
if grep -q 'AKIA1234567890ABCDEF' "$hist_dir/session-1.jsonl"; then
  : # dry-run must leave the secret on disk
else
  echo "Expected history scrub dry-run to leave transcript unchanged" >&2
  cat "$hist_dir/session-1.jsonl" >&2
  exit 1
fi


# --- offsend sync orchestration ---
sync_repo="$workdir/sync-repo"
sync_home="$workdir/sync-home"
mkdir -p "$sync_repo" "$sync_home"
git -C "$sync_repo" init >/dev/null
git -C "$sync_repo" config user.email "ci@example.com"
git -C "$sync_repo" config user.name "Offsend CI"

printf '%s\n' \
  "version: 1" \
  "" \
  "ignore:" \
  "  commit: true" \
  "  patterns:" \
  "    - \"secrets/\"" \
  "hooks:" \
  "  publish: false" > "$sync_repo/.offsend.yml"

set +e
HOME="$sync_home" "$CLI_PATH" sync --path "$sync_repo" --dry-run --format json >/tmp/offsend-sync-dry.$$ 2>/tmp/offsend-sync-dry-err.$$
sync_dry_status="$?"
set -e
if [[ "$sync_dry_status" -ne 0 ]]; then
  echo "Expected sync --dry-run to exit 0, got $sync_dry_status" >&2
  cat /tmp/offsend-sync-dry-err.$$ >&2
  exit 1
fi
if [[ -f "$sync_repo/.cursorignore" ]]; then
  echo "Expected sync --dry-run not to write .cursorignore" >&2
  exit 1
fi
if ! grep -q '"dryRun"[[:space:]]*:[[:space:]]*true' /tmp/offsend-sync-dry.$$; then
  echo "Expected sync --dry-run JSON dryRun:true" >&2
  cat /tmp/offsend-sync-dry.$$ >&2
  exit 1
fi
if ! grep -q '"skipped"[[:space:]]*:[[:space:]]*true' /tmp/offsend-sync-dry.$$; then
  echo "Expected sync --dry-run JSON hooks.skipped:true" >&2
  cat /tmp/offsend-sync-dry.$$ >&2
  exit 1
fi
rm -f /tmp/offsend-sync-dry.$$ /tmp/offsend-sync-dry-err.$$

HOME="$sync_home" "$CLI_PATH" sync --path "$sync_repo" --no-hooks --format json >/tmp/offsend-sync-nohooks.$$
if [[ ! -f "$sync_repo/.cursorignore" ]]; then
  echo "Expected sync --no-hooks to materialize .cursorignore" >&2
  exit 1
fi
if [[ -f "$sync_repo/.git/hooks/pre-commit" ]]; then
  echo "Expected sync --no-hooks not to install git pre-commit hook" >&2
  exit 1
fi
if ! grep -q '"reason"[[:space:]]*:[[:space:]]*"--no-hooks"' /tmp/offsend-sync-nohooks.$$; then
  echo "Expected sync --no-hooks JSON reason --no-hooks" >&2
  cat /tmp/offsend-sync-nohooks.$$ >&2
  exit 1
fi
rm -f /tmp/offsend-sync-nohooks.$$

HOME="$sync_home" "$CLI_PATH" sync --path "$sync_repo" --format json >/tmp/offsend-sync-full.$$ 2>/tmp/offsend-sync-full-err.$$
if [[ ! -f "$sync_repo/.git/hooks/pre-commit" ]]; then
  echo "Expected sync to install git pre-commit hook" >&2
  cat /tmp/offsend-sync-full-err.$$ >&2
  exit 1
fi
if ! grep -q '"skipped"[[:space:]]*:[[:space:]]*false' /tmp/offsend-sync-full.$$; then
  echo "Expected sync JSON hooks.skipped:false" >&2
  cat /tmp/offsend-sync-full.$$ >&2
  exit 1
fi
# Idempotent second run should succeed.
HOME="$sync_home" "$CLI_PATH" sync --path "$sync_repo" --format json >/tmp/offsend-sync-idem.$$
rm -f /tmp/offsend-sync-full.$$ /tmp/offsend-sync-full-err.$$ /tmp/offsend-sync-idem.$$

# Foreign git hook: warn + skip git, still install AI hooks, exit 0.
foreign_repo="$workdir/sync-foreign"
mkdir -p "$foreign_repo/.git/hooks"
git -C "$foreign_repo" init >/dev/null
git -C "$foreign_repo" config user.email "ci@example.com"
git -C "$foreign_repo" config user.name "Offsend CI"
printf '%s\n' '#!/bin/sh' 'echo foreign-pre-commit' > "$foreign_repo/.git/hooks/pre-commit"
chmod +x "$foreign_repo/.git/hooks/pre-commit"
cp "$sync_repo/.offsend.yml" "$foreign_repo/.offsend.yml"

set +e
HOME="$sync_home" "$CLI_PATH" sync --path "$foreign_repo" --format json >/tmp/offsend-sync-foreign.$$ 2>/tmp/offsend-sync-foreign-err.$$
foreign_status="$?"
set -e
if [[ "$foreign_status" -ne 0 ]]; then
  echo "Expected sync with foreign git hook to exit 0, got $foreign_status" >&2
  cat /tmp/offsend-sync-foreign-err.$$ >&2
  exit 1
fi
if ! grep -q 'foreign-pre-commit' "$foreign_repo/.git/hooks/pre-commit"; then
  echo "Expected foreign git hook to be preserved" >&2
  exit 1
fi
if ! grep -qi 'git hook skipped' /tmp/offsend-sync-foreign-err.$$ \
  && ! grep -q '"warning"' /tmp/offsend-sync-foreign.$$; then
  echo "Expected warning about skipped git hook (stderr or JSON)" >&2
  cat /tmp/offsend-sync-foreign-err.$$ >&2
  cat /tmp/offsend-sync-foreign.$$ >&2
  exit 1
fi
if [[ ! -f "$foreign_repo/.cursor/hooks.json" && ! -f "$foreign_repo/.claude/settings.json" ]]; then
  echo "Expected AI-editor hooks to install despite foreign git hook" >&2
  exit 1
fi
rm -f /tmp/offsend-sync-foreign.$$ /tmp/offsend-sync-foreign-err.$$

# Missing config should fail.
empty_repo="$workdir/sync-empty"
mkdir -p "$empty_repo"
git -C "$empty_repo" init >/dev/null
set +e
HOME="$sync_home" "$CLI_PATH" sync --path "$empty_repo" >/dev/null 2>/tmp/offsend-sync-missing.$$
missing_status="$?"
set -e
if [[ "$missing_status" -ne 2 ]]; then
  echo "Expected sync without .offsend.yml to exit 2, got $missing_status" >&2
  cat /tmp/offsend-sync-missing.$$ >&2
  exit 1
fi
rm -f /tmp/offsend-sync-missing.$$

echo "CLI E2E smoke passed."
