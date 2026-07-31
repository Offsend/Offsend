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
# Doctor reflects the caller's workspace (may be unhealthy if hooks.enabled but
# not installed). Smoke: JSON + exit 0 (healthy) or 2 (unhealthy).
set +e
doctor_json="$("$CLI_PATH" doctor --format json 2>&1)"
doctor_status="$?"
set -e
printf '%s\n' "$doctor_json"
if [[ "$doctor_status" -ne 0 && "$doctor_status" -ne 2 ]]; then
  echo "Expected doctor --format json to exit 0 or 2, got $doctor_status" >&2
  exit 1
fi
if ! printf '%s\n' "$doctor_json" | grep -q '"healthy"'; then
  echo "Expected doctor JSON to include healthy" >&2
  exit 1
fi

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

# Trusting or forgetting editor-gate policy must require a real user TTY.
"$CLI_PATH" policy status --path "$repo" | grep -q "status: missing"
set +e
"$CLI_PATH" policy trust --path "$repo" >/dev/null 2>&1
policy_trust_status="$?"
"$CLI_PATH" policy forget --path "$repo" >/dev/null 2>&1
policy_forget_status="$?"
set -e
if [[ "$policy_trust_status" -eq 0 || "$policy_forget_status" -eq 0 ]]; then
  echo "Expected policy trust/forget to reject non-interactive execution" >&2
  exit 1
fi

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
# offsend:ignore-next-line
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
# offsend:ignore-next-line
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
# offsend:ignore-next-line
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
# offsend:ignore-next-line
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

# Semantic write-gate: executable host configuration denies; source files allow.
write_hooks="{\"tool_name\":\"Write\",\"cwd\":\"$repo\",\"tool_input\":{\"file_path\":\".cursor/hooks.json\",\"content\":\"{}\"}}"
write_envrc="{\"tool_name\":\"Write\",\"cwd\":\"$repo\",\"tool_input\":{\"file_path\":\".envrc\",\"content\":\"export PATH=./bin\"}}"
write_source="{\"tool_name\":\"Write\",\"cwd\":\"$repo\",\"tool_input\":{\"file_path\":\"Sources/App.swift\",\"content\":\"print(1)\"}}"
set +e
write_deny="$(printf '%s' "$write_hooks" | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
write_envrc_deny="$(printf '%s' "$write_envrc" | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
write_allow="$(printf '%s' "$write_source" | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
set -e
if ! echo "$write_deny" | grep -q '"deny"'; then
  echo "Expected write-gate deny for .cursor/hooks.json" >&2
  echo "$write_deny" >&2
  exit 1
fi
if ! echo "$write_envrc_deny" | grep -q '"deny"'; then
  echo "Expected write-gate deny for shell startup environment config" >&2
  echo "$write_envrc_deny" >&2
  exit 1
fi
if ! echo "$write_allow" | grep -q '"allow"'; then
  echo "Expected write-gate allow for ordinary source" >&2
  echo "$write_allow" >&2
  exit 1
fi

# Offsend's own policy is a trust surface: the agent must not rewrite it.
write_policy="{\"tool_name\":\"Write\",\"cwd\":\"$repo\",\"tool_input\":{\"file_path\":\".offsend.yml\",\"content\":\"version: 1\"}}"
# Editor settings mix preferences with execution, so the decision follows content.
settings_plain="{\"tool_name\":\"Write\",\"cwd\":\"$repo\",\"tool_input\":{\"file_path\":\".vscode/settings.json\",\"content\":\"{\\\"editor.tabSize\\\": 2}\"}}"
settings_exec="{\"tool_name\":\"Write\",\"cwd\":\"$repo\",\"tool_input\":{\"file_path\":\".vscode/settings.json\",\"content\":\"{\\\"python.defaultInterpreterPath\\\": \\\"/tmp/py\\\"}\"}}"
set +e
write_policy_deny="$(printf '%s' "$write_policy" | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
settings_plain_allow="$(printf '%s' "$settings_plain" | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
settings_exec_deny="$(printf '%s' "$settings_exec" | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
set -e
if ! echo "$write_policy_deny" | grep -q '"deny"'; then
  echo "Expected write-gate deny for .offsend.yml" >&2
  echo "$write_policy_deny" >&2
  exit 1
fi
if ! echo "$settings_plain_allow" | grep -q '"allow"'; then
  echo "Expected write-gate allow for ordinary editor settings" >&2
  echo "$settings_plain_allow" >&2
  exit 1
fi
if ! echo "$settings_exec_deny" | grep -q '"deny"'; then
  echo "Expected write-gate deny for interpreter path in editor settings" >&2
  echo "$settings_exec_deny" >&2
  exit 1
fi

# An Edit that swaps only the value names no key, so the gate has to read the
# settings file to see which setting the replacement lands on.
mkdir -p "$repo/.vscode"
printf '%s\n' '{"editor.tabSize": 2, "python.defaultInterpreterPath": "/usr/bin/python3"}' \
  > "$repo/.vscode/settings.json"
settings_value_swap="{\"tool_name\":\"Edit\",\"cwd\":\"$repo\",\"tool_input\":{\"file_path\":\".vscode/settings.json\",\"old_string\":\"/usr/bin/python3\",\"new_string\":\"/tmp/agent-bin/python\"}}"
settings_tab_swap="{\"tool_name\":\"Edit\",\"cwd\":\"$repo\",\"tool_input\":{\"file_path\":\".vscode/settings.json\",\"old_string\":\"2\",\"new_string\":\"4\"}}"
set +e
settings_value_deny="$(printf '%s' "$settings_value_swap" | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
settings_tab_allow="$(printf '%s' "$settings_tab_swap" | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
set -e
if ! echo "$settings_value_deny" | grep -q '"deny"'; then
  echo "Expected write-gate deny for in-place interpreter path swap" >&2
  echo "$settings_value_deny" >&2
  exit 1
fi
if ! echo "$settings_tab_allow" | grep -q '"allow"'; then
  echo "Expected write-gate allow for in-place ordinary setting swap" >&2
  echo "$settings_tab_allow" >&2
  exit 1
fi
rm -rf "$repo/.vscode"

# Cursor publishes no tool_input schema for file tools, so an unfamiliar key
# must still be classified. Cursor also ignores `ask` on preToolUse, so
# unreadable payloads have to render as deny there.
write_unknown_key="{\"tool_name\":\"Delete\",\"cwd\":\"$repo\",\"tool_input\":{\"target_paths\":[\"README.md\",\".cursor/hooks.json\"]}}"
set +e
write_unknown_deny="$(printf '%s' "$write_unknown_key" | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
write_empty="$(printf '' | "$CLI_PATH" check --adapter cursor --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
write_empty_claude="$(printf '' | "$CLI_PATH" check --adapter claude --write-gate --no-notify --working-directory "$repo" 2>/dev/null)"
set -e
if ! echo "$write_unknown_deny" | grep -q '"deny"'; then
  echo "Expected write-gate deny for unrecognized tool_input key naming a hook config" >&2
  echo "$write_unknown_deny" >&2
  exit 1
fi
if ! echo "$write_empty" | grep -q '"deny"'; then
  echo "Expected empty Cursor write-gate payload to deny (ask is not enforced)" >&2
  echo "$write_empty" >&2
  exit 1
fi
if ! echo "$write_empty_claude" | grep -q '"ask"'; then
  echo "Expected empty Claude write-gate payload to ask" >&2
  echo "$write_empty_claude" >&2
  exit 1
fi

# Hook input over the 2 MiB stdin limit fails closed: the payload (which
# carries the file body for Cursor) cannot be scanned, so the read is denied.
set +e
read_oversized="$(head -c 3000000 /dev/zero | tr '\0' 'a' | "$CLI_PATH" check --adapter cursor --read-gate --no-notify 2>/dev/null)"
set -e
if ! echo "$read_oversized" | grep -q '"deny"'; then
  echo "Expected read-gate deny for oversized stdin" >&2
  echo "$read_oversized" >&2
  exit 1
fi

# Read-gate seal mode: deny hands the agent a sealed copy path (context.read.on_secret: seal).
seal_read_repo="$workdir/seal-read"
seal_read_home="$workdir/seal-read-home"
mkdir -p "$seal_read_repo" "$seal_read_home"
printf '%s\n' \
  "version: 1" \
  "" \
  "check:" \
  "  detectors:" \
  "    disable:" \
  "      - email" \
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
# Directory membership is not trusted: plaintext planted beside a sealed copy
# must still be content-scanned and denied.
planted_plaintext="$(dirname "$sealed_copy_path")/plain.txt"
# offsend:ignore-next-line
printf '%s\n' 'AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF' > "$planted_plaintext"
set +e
planted_plaintext_out="$(printf '%s' "{\"file_path\":\"$planted_plaintext\"}" | HOME="$seal_read_home" "$CLI_PATH" check --adapter cursor --read-gate --no-notify --working-directory "$seal_read_repo" 2>/dev/null)"
set -e
if ! echo "$planted_plaintext_out" | grep -q '"deny"'; then
  echo "Expected read-gate to deny plaintext planted in the seal-copy directory" >&2
  echo "$planted_plaintext_out" >&2
  exit 1
fi
rm -f "$planted_plaintext"
# offsend check on the sealed copy is clean (seal tokens are not live secrets).
if ! HOME="$seal_read_home" "$CLI_PATH" check "$sealed_copy_path" --fail-on block --quiet; then
  echo "Expected offsend check on the sealed copy to pass" >&2
  exit 1
fi
rm -f "$sealed_copy_path"

# Seal mode ignores check.detectors.disable: PII must not remain plaintext.
read_seal_pii_payload='{"file_path":"/repo/customer.txt","content":"owner=security-team@corp.test"}'
read_seal_pii_out="$(printf '%s' "$read_seal_pii_payload" | HOME="$seal_read_home" "$CLI_PATH" check --adapter cursor --read-gate --no-notify --working-directory "$seal_read_repo" 2>/dev/null)"
pii_copy_path="$(echo "$read_seal_pii_out" | sed 's|\\/|/|g' | { grep -o '/[^"]*offsend-seal/sealed-[^"]*\.txt' || true; } | head -1)"
if [[ -z "$pii_copy_path" || ! -f "$pii_copy_path" ]] || grep -q 'security-team@corp.test' "$pii_copy_path"; then
  echo "Expected seal-mode to override disabled email detector and remove plaintext PII" >&2
  echo "$read_seal_pii_out" >&2
  exit 1
fi
rm -f "$pii_copy_path"

# Encoded terminal output is decoded/re-scanned and the encoded span is sealed.
# offsend:ignore-next-line
encoded_secret="$(printf '%s' 'OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyzABCDEF123456' | base64 | tr -d '\n')"
read_encoded_payload="$(printf '{"file_path":"/repo/terminal.txt","content":"%s"}' "$encoded_secret")"
read_encoded_out="$(printf '%s' "$read_encoded_payload" | HOME="$seal_read_home" "$CLI_PATH" check --adapter cursor --read-gate --no-notify --working-directory "$seal_read_repo" 2>/dev/null)"
encoded_copy_path="$(echo "$read_encoded_out" | sed 's|\\/|/|g' | { grep -o '/[^"]*offsend-seal/sealed-[^"]*\.txt' || true; } | head -1)"
if [[ -z "$encoded_copy_path" || ! -f "$encoded_copy_path" ]] \
   || grep -q "${encoded_secret:0:16}" "$encoded_copy_path"; then
  echo "Expected encoded secret dump to be sealed before terminal Read" >&2
  echo "$read_encoded_out" >&2
  exit 1
fi
rm -f "$encoded_copy_path"

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

# Shell gate stops the agent before it runs offsend unseal.
set +e
unseal_deny="$(printf '%s' '{"command":"offsend unseal sealed.txt"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
set -e
if ! echo "$unseal_deny" | grep -q '"deny"'; then
  echo "Expected shell-gate deny for offsend unseal" >&2
  echo "$unseal_deny" >&2
  exit 1
fi
# Refuse missing repository paths and preserve unrelated legacy wrapper files.
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
if [[ "$foreign_wrapper_status" -ne 0 ]] || ! grep -q 'custom-wrapper' "$repo/.offsend/hooks/check-prompt.sh"; then
  echo "Expected direct AI hook install to preserve an unrelated foreign wrapper" >&2
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
if ! grep -q "OFFSEND_MANAGED_HOOK=1" "$repo/.cursor/hooks.json"; then
  echo "Expected cursor hooks.json to invoke the managed Offsend CLI directly" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "beforeShellExecution" "$repo/.cursor/hooks.json"; then
  echo "Expected merge to keep foreign beforeShellExecution hook" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q -- "--no-notify" "$repo/.cursor/hooks.json"; then
  echo "Expected managed hook command to pass --no-notify" >&2
  exit 1
fi
if ! grep -q "beforeReadFile" "$repo/.cursor/hooks.json"; then
  echo "Expected read-gate on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "preToolUse" "$repo/.cursor/hooks.json" || ! grep -q -- "--write-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected semantic write-gate on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "afterFileEdit" "$repo/.cursor/hooks.json" || ! grep -q -- "--artifact-audit" "$repo/.cursor/hooks.json"; then
  echo "Expected post-write artifact provenance on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q -- "--shell-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected shell-gate on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "audit.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected foreign beforeShellExecution hook to survive shell-gate merge" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q -- "--mcp-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected mcp-gate on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "beforeMCPExecution" "$repo/.cursor/hooks.json"; then
  echo "Expected beforeMCPExecution on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "failClosed" "$repo/.cursor/hooks.json"; then
  echo "Expected failClosed on MCP/subagent Cursor gates" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q -- "--subagent-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected subagent-gate on by default for Cursor" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "subagentStart" "$repo/.cursor/hooks.json"; then
  echo "Expected subagentStart on by default for Cursor" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q '"Task"' "$repo/.cursor/hooks.json"; then
  echo "Expected preToolUse Task matcher with subagent-gate" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q '"Grep"' "$repo/.cursor/hooks.json" || ! grep -q -- "--grep-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected preToolUse Grep matcher with grep-gate" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-read-gate
if grep -q "beforeReadFile" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-read-gate to remove beforeReadFile" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if grep -q -- "--grep-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-read-gate to remove grep-gate" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-read-gate
if ! grep -q "beforeReadFile" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-read-gate alias to add beforeReadFile" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-write-gate
if grep -q -- "--write-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-write-gate to remove the managed preToolUse write entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-write-gate
if ! grep -q -- "--write-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-write-gate alias to restore semantic write protection" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

# Shell gate is on by default: deny on sensitive paths, allow otherwise.
shell_secret_deny="$(printf '%s' '{"command":"cat .env"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_secret_deny" | grep -q '"deny"'; then
  echo "Expected shell-gate deny for 'cat .env'" >&2
  echo "$shell_secret_deny" >&2
  exit 1
fi
# F1: adjacent string concat inside python -c must still deny sensitive paths.
shell_concat_deny="$(printf '%s' '{"command":"python3 -c '"'"'from pathlib import Path; Path(\"c\"+\"ert\"+\".p\"+\"em\").read_text()'"'"'"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_concat_deny" | grep -q '"deny"'; then
  echo "Expected shell-gate deny for python string-concat path to cert.pem" >&2
  echo "$shell_concat_deny" >&2
  exit 1
fi
shell_python_print_allow="$(printf '%s' '{"command":"python3 -c '"'"'print(1+1)'"'"'"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if echo "$shell_python_print_allow" | grep -Eq '"permission"[[:space:]]*:[[:space:]]*"(deny|ask)"'; then
  echo "Expected shell-gate allow for benign python3 -c print" >&2
  echo "$shell_python_print_allow" >&2
  exit 1
fi
shell_ignore_repo="$workdir/shell-ignore"
mkdir -p "$shell_ignore_repo"
printf '%s\n' \
  "version: 1" \
  "ignore:" \
  "  patterns:" \
  "    - fixtures/" > "$shell_ignore_repo/.offsend.yml"
shell_ignore_concat_deny="$(printf '%s' '{"command":"python3 -c '"'"'from pathlib import Path; list(Path(\"f\"+\"ixtures\").iterdir())'"'"'"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$shell_ignore_repo" 2>/dev/null)"
if ! echo "$shell_ignore_concat_deny" | grep -q '"deny"'; then
  echo "Expected shell-gate deny for reconstructed path protected by ignore.patterns" >&2
  echo "$shell_ignore_concat_deny" >&2
  exit 1
fi
shell_allow="$(printf '%s' '{"command":"ls -la src"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_allow" | grep -q '"allow"'; then
  echo "Expected shell-gate allow for 'ls -la src'" >&2
  echo "$shell_allow" >&2
  exit 1
fi
shell_exec_deny="$(printf '%s' "{\"cwd\":\"$repo\",\"command\":\"printf malicious > .cursor/hooks.json\"}" | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$repo" 2>/dev/null)"
if ! echo "$shell_exec_deny" | grep -q '"deny"'; then
  echo "Expected shell-gate hard deny for direct executable-config write" >&2
  echo "$shell_exec_deny" >&2
  exit 1
fi
shell_git_config_deny="$(printf '%s' '{"command":"git config core.hooksPath .agent-hooks"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_git_config_deny" | grep -q '"deny"'; then
  echo "Expected shell-gate hard deny for execution-sensitive git config" >&2
  echo "$shell_git_config_deny" >&2
  exit 1
fi
shell_git_config_read="$(printf '%s' '{"command":"git config --get core.hooksPath"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_git_config_read" | grep -q '"allow"'; then
  echo "Expected shell-gate allow for read-only git config" >&2
  echo "$shell_git_config_read" >&2
  exit 1
fi
shell_docker_deny="$(printf '%s' '{"command":"docker run --rm alpine id"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_docker_deny" | grep -q '"deny"'; then
  echo "Expected shell-gate hard deny for host-side container execution" >&2
  echo "$shell_docker_deny" >&2
  exit 1
fi
shell_docker_build="$(printf '%s' '{"command":"docker build ."}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_docker_build" | grep -q '"deny"'; then
  echo "Expected shell-gate deny for lower-risk daemon mutation in default deny mode" >&2
  echo "$shell_docker_build" >&2
  exit 1
fi
shell_docker_read="$(printf '%s' '{"command":"docker ps"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_docker_read" | grep -q '"allow"'; then
  echo "Expected shell-gate allow for Docker diagnostics" >&2
  echo "$shell_docker_read" >&2
  exit 1
fi
shell_env_deny="$(printf '%s' '{"command":"PATH=./bin:/usr/bin make"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$repo" 2>/dev/null)"
if ! echo "$shell_env_deny" | grep -q '"deny"'; then
  echo "Expected shell-gate hard deny for workspace PATH poisoning" >&2
  echo "$shell_env_deny" >&2
  exit 1
fi
shell_env_system="$(printf '%s' '{"command":"PATH=/opt/homebrew/bin:/usr/bin:$PATH make"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$repo" 2>/dev/null)"
if ! echo "$shell_env_system" | grep -q '"deny"'; then
  echo "Expected shell-gate deny for system-only PATH override in default deny mode" >&2
  echo "$shell_env_system" >&2
  exit 1
fi
shell_git_metadata="$(printf '%s' '{"command":"GIT_AUTHOR_NAME=Bot git status"}' | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify 2>/dev/null)"
if ! echo "$shell_git_metadata" | grep -q '"allow"'; then
  echo "Expected shell-gate allow for safe Git metadata environment" >&2
  echo "$shell_git_metadata" >&2
  exit 1
fi

# Stated non-goals: reading files by enumeration is NOT prevented.
#
# These vectors must stay ALLOWED. They are not oversights — a blocklist of
# filesystem API names, encodings, and interpreter invocation forms grows with
# the attacker's ingenuity, never closes, and produces false positives on
# ordinary code, so SECURITY.md ("Shell-gate rule admission") rejects such
# rules by policy. This block exists so that re-adding one fails CI and forces
# the boundary to be discussed rather than the table extended. Move the line
# here only together with an enforcement layer that actually closes it
# (an OS sandbox denying egress), never with another signature.
shell_nongoal_repo="$workdir/shell-non-goals"
mkdir -p "$shell_nongoal_repo/fixtures"
printf '%s\n' \
  "version: 1" \
  "ignore:" \
  "  patterns:" \
  "    - fixtures/" > "$shell_nongoal_repo/.offsend.yml"
# offsend:ignore-next-line
printf '%s\n' 'AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF' > "$shell_nongoal_repo/fixtures/.env"
shell_nongoal_payload() {
  python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1"
}
while IFS= read -r nongoal_command; do
  [[ -n "$nongoal_command" ]] || continue
  nongoal_out="$(shell_nongoal_payload "$nongoal_command" | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$shell_nongoal_repo" 2>/dev/null)"
  if echo "$nongoal_out" | grep -Eq '"permission"[[:space:]]*:[[:space:]]*"(deny|ask)"'; then
    echo "Expected ALLOW for a stated non-goal: $nongoal_command" >&2
    echo "Enumeration without a named path is out of the shell-gate's scope." >&2
    echo "See SECURITY.md, 'Shell-gate rule admission', before changing this." >&2
    echo "$nongoal_out" >&2
    exit 1
  fi
done <<'NONGOALS'
find . -type f -exec cat {} +
grep -rn 'sk-' .
tar cf - . | base64
python3 -c 'import io,glob,os; [print(io.FileIO(p).readall()) for p in glob.iglob("**/*", recursive=True) if os.path.isfile(p)]'
python3 -c 'import json; print(json.load(open("package.json")))'
NONGOALS
# A heredoc-fed walker is the same non-goal in multi-line form. Heredoc bodies are
# still swept for path *names*, so this stays allowed only while it names none.
shell_nongoal_heredoc="$(printf 'python3 <<%sPY%s\nimport pathlib\nprint([p.name for p in pathlib.Path(".").rglob("*")])\nPY' "'" "'")"
nongoal_heredoc_out="$(shell_nongoal_payload "$shell_nongoal_heredoc" | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$shell_nongoal_repo" 2>/dev/null)"
if echo "$nongoal_heredoc_out" | grep -Eq '"permission"[[:space:]]*:[[:space:]]*"(deny|ask)"'; then
  echo "Expected ALLOW for a heredoc walker that names no protected path" >&2
  echo "$nongoal_heredoc_out" >&2
  exit 1
fi
# The other half of the same rewiring: a name inside a heredoc body is still seen.
shell_heredoc_named="$(printf 'python3 <<%sPY%s\nprint(open("fixtures/app.log").read())\nPY' "'" "'")"
heredoc_named_out="$(shell_nongoal_payload "$shell_heredoc_named" | "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$shell_nongoal_repo" 2>/dev/null)"
if ! echo "$heredoc_named_out" | grep -q '"deny"'; then
  echo "Expected deny for a protected path named inside a heredoc body" >&2
  echo "$heredoc_named_out" >&2
  exit 1
fi

# context.shell.mode: ask reaches the gate only for a user-trusted policy.
shell_ask_repo="$workdir/shell-ask"
shell_ask_home="$workdir/shell-ask-home"
mkdir -p "$shell_ask_repo" "$shell_ask_home"
printf '%s\n' \
  "version: 1" \
  "" \
  "check:" \
  "  exclude:" \
  "    - docs/**" \
  "" \
  "context:" \
  "  shell:" \
  "    mode: ask" > "$shell_ask_repo/.offsend.yml"
mkdir -p "$shell_ask_repo/docs"
# offsend:ignore-next-line
printf '%s\n' 'AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF' > "$shell_ask_repo/docs/example.txt"
prompt_exclude_payload="$(printf '{"prompt":"review @docs/example.txt","cwd":"%s"}' "$shell_ask_repo")"

shell_untrusted_ask="$(printf '%s' '{"command":"cat .env"}' | HOME="$shell_ask_home" "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$shell_ask_repo" 2>/dev/null)"
if ! echo "$shell_untrusted_ask" | grep -q '"deny"'; then
  echo "Expected untrusted context.shell.mode: ask to stay at the deny default" >&2
  echo "$shell_untrusted_ask" >&2
  exit 1
fi
# Untrusted check.exclude is ignored, including for @mentions.
prompt_exclude_untrusted="$(printf '%s' "$prompt_exclude_payload" | HOME="$shell_ask_home" "$CLI_PATH" check --adapter cursor --hook-policy soft-block --no-notify --working-directory "$shell_ask_repo" 2>/dev/null)"
if ! echo "$prompt_exclude_untrusted" | grep -q '"continue":false\|"continue": false'; then
  echo "Expected untrusted check.exclude to be ignored for @file prompt scan" >&2
  echo "$prompt_exclude_untrusted" >&2
  exit 1
fi

# Trusting requires a real terminal, so drive the confirmation through a pty.
# The leading sleep matters: without it the prompt reads EOF before the answer
# arrives, and `policy trust` silently declines with exit code 0.
case "$(uname -s)" in
  Darwin)
    { sleep 1; printf 'y\ny\ny\n'; } | HOME="$shell_ask_home" \
      script -q /dev/null "$CLI_PATH" policy trust --path "$shell_ask_repo" >/dev/null 2>&1
    ;;
  *)
    { sleep 1; printf 'y\ny\ny\n'; } | HOME="$shell_ask_home" \
      script -qe -c "\"$CLI_PATH\" policy trust --path \"$shell_ask_repo\"" /dev/null >/dev/null 2>&1
    ;;
esac
if ! HOME="$shell_ask_home" "$CLI_PATH" policy status --path "$shell_ask_repo" | grep -q "status: trusted"; then
  echo "Expected pty-driven policy trust to record a snapshot" >&2
  HOME="$shell_ask_home" "$CLI_PATH" policy status --path "$shell_ask_repo" >&2
  exit 1
fi

prompt_exclude_trusted="$(printf '%s' "$prompt_exclude_payload" | HOME="$shell_ask_home" "$CLI_PATH" check --adapter cursor --hook-policy soft-block --no-notify --working-directory "$shell_ask_repo" 2>/dev/null)"
if ! echo "$prompt_exclude_trusted" | grep -q '"continue":true\|"continue": true'; then
  echo "Expected trusted check.exclude to skip @file content in prompt gate" >&2
  echo "$prompt_exclude_trusted" >&2
  exit 1
fi

shell_trusted_ask="$(printf '%s' '{"command":"cat .env"}' | HOME="$shell_ask_home" "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$shell_ask_repo" 2>/dev/null)"
if ! echo "$shell_trusted_ask" | grep -q '"ask"'; then
  echo "Expected trusted context.shell.mode: ask to downgrade the deny default" >&2
  echo "$shell_trusted_ask" >&2
  exit 1
fi
shell_trusted_deny="$(printf '%s' '{"command":"git config core.hooksPath .agent-hooks"}' | HOME="$shell_ask_home" "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$shell_ask_repo" 2>/dev/null)"
if ! echo "$shell_trusted_deny" | grep -q '"deny"'; then
  echo "Expected control-plane deny to survive mode: ask" >&2
  echo "$shell_trusted_deny" >&2
  exit 1
fi

# Shell-output audit: a printed secret is recorded and notified, never blocked.
shell_audit_repo="$workdir/shell-audit"
mkdir -p "$shell_audit_repo"
# The audit log lives in the user-local store, next to mcp-activity.log, so the
# assertions below read the last line rather than the whole file.
shell_audit_log="$HOME/Library/Application Support/Offsend/shell-output-audit.log"
if [[ ! -d "$(dirname "$shell_audit_log")" ]]; then
  shell_audit_log="${XDG_CONFIG_HOME:-$HOME/.config}/offsend/shell-output-audit.log"
fi
set +e
# offsend:ignore-next-line
shell_audit_out="$(printf '%s' '{"command":"printenv AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF","output":"AKIA1234567890ABCDEF","sandbox":false}' | "$CLI_PATH" check --adapter cursor --shell-audit --no-notify --working-directory "$shell_audit_repo" 2>"$workdir/shell-audit.err")"
shell_audit_status="$?"
set -e
if [[ "$shell_audit_status" -ne 0 ]]; then
  echo "Expected shell-audit to exit 0: a post-hoc finding must not look like a hook failure" >&2
  cat "$workdir/shell-audit.err" >&2
  exit 1
fi
if echo "$shell_audit_out" | grep -Eq '"permission"[[:space:]]*:[[:space:]]*"(deny|ask)"'; then
  echo "Expected shell-audit to stay observational, not emit a permission decision" >&2
  echo "$shell_audit_out" >&2
  exit 1
fi
if ! grep -q 'awsAccessKeyId' "$workdir/shell-audit.err"; then
  echo "Expected shell-audit to report the detected secret type on stderr" >&2
  cat "$workdir/shell-audit.err" >&2
  exit 1
fi
if [[ ! -f "$shell_audit_log" ]]; then
  echo "Expected shell-audit to record the finding in $shell_audit_log" >&2
  exit 1
fi
shell_audit_line="$(tail -n 1 "$shell_audit_log")"
if ! echo "$shell_audit_line" | grep -q 'awsAccessKeyId'; then
  echo "Expected the audit log to name the detector type" >&2
  echo "$shell_audit_line" >&2
  exit 1
fi
# The value is already in the model context; copying it to disk would only add a
# second exposure — including when the secret sits in the command itself.
if echo "$shell_audit_line" | grep -q 'AKIA1234567890ABCDEF'; then
  echo "Audit log must never contain the secret value" >&2
  exit 1
fi
if ! echo "$shell_audit_line" | grep -q 'OFFSEND_REDACTED_awsAccessKeyId'; then
  echo "Expected the logged command to keep a redaction marker in place of the secret" >&2
  echo "$shell_audit_line" >&2
  exit 1
fi
printf '%s' '{"command":"ls -la src","output":"README.md"}' | "$CLI_PATH" check --adapter cursor --shell-audit --no-notify --working-directory "$shell_audit_repo" >/dev/null 2>"$workdir/shell-audit-clean.err"
if [[ -s "$workdir/shell-audit-clean.err" ]]; then
  echo "Expected no shell-audit output for clean command output" >&2
  cat "$workdir/shell-audit-clean.err" >&2
  exit 1
fi
if ! grep -q -- "--shell-audit" "$repo/.cursor/hooks.json"; then
  echo "Expected shell-output audit on by default" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "afterShellExecution" "$repo/.cursor/hooks.json"; then
  echo "Expected afterShellExecution event for the shell-output audit" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-shell-audit
if grep -q -- "--shell-audit" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-shell-audit to remove the managed audit entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-shell-audit
if ! grep -q -- "--shell-audit" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-shell-audit alias to restore the audit entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-shell-gate
if grep -q -- "--shell-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-shell-gate to remove the managed shell-gate entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q "audit.sh" "$repo/.cursor/hooks.json"; then
  echo "Expected foreign beforeShellExecution hook to survive shell-gate removal" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-shell-gate
if ! grep -q -- "--shell-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-shell-gate alias to add the shell-gate command" >&2
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
# Same fail-closed policy for stdin over the 2 MiB limit under mode: deny.
set +e
mcp_oversized_deny="$(head -c 3000000 /dev/zero | tr '\0' 'a' | "$CLI_PATH" check --adapter cursor --mcp-gate --no-notify --working-directory "$mcp_policy_repo" 2>/dev/null)"
set -e
if ! echo "$mcp_oversized_deny" | grep -q '"deny"'; then
  echo "Expected mcp-gate deny for oversized stdin under context.mcp.mode deny" >&2
  echo "$mcp_oversized_deny" >&2
  exit 1
fi
# Without an explicit deny mode, oversized mcp-gate input keeps failing open.
set +e
mcp_oversized_open="$(head -c 3000000 /dev/zero | tr '\0' 'a' | "$CLI_PATH" check --adapter cursor --mcp-gate --no-notify 2>/dev/null)"
set -e
if ! echo "$mcp_oversized_open" | grep -q '"allow"'; then
  echo "Expected mcp-gate fail-open allow for oversized stdin without mode deny" >&2
  echo "$mcp_oversized_open" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-mcp-gate
if grep -q -- "--mcp-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-mcp-gate to remove the managed mcp-gate entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q -- "--subagent-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-mcp-gate to keep subagent-gate" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-mcp-gate
if ! grep -q -- "--mcp-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-mcp-gate alias to add the mcp-gate command" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

# MCP response gate: Cursor/Claude observe, warn, seal, fail-safe, install toggles.
if ! grep -q -- "--mcp-response-gate" "$repo/.cursor/hooks.json" || ! grep -q "postToolUse" "$repo/.cursor/hooks.json"; then
  echo "Expected mcp-response-gate on by default (postToolUse + direct CLI command)" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if grep -q "afterMCPExecution" "$repo/.cursor/hooks.json"; then
  echo "Legacy observe-only afterMCPExecution hook must be removed" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
# offsend:ignore-next-line
mcpresp_cursor_payload='{"tool_name":"MCP:postgres/query","tool_output":"{\"value\":\"AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF\"}"}'
set +e
mcpresp_cursor_out="$(printf '%s' "$mcpresp_cursor_payload" | "$CLI_PATH" check --adapter cursor --mcp-response-gate --no-notify 2>/tmp/offsend-mcpresp-stderr.$$)"
set -e
mcpresp_cursor_stderr="$(cat /tmp/offsend-mcpresp-stderr.$$)"
rm -f /tmp/offsend-mcpresp-stderr.$$
if [[ "$mcpresp_cursor_out" != "{}" ]]; then
  echo "Expected cursor mcp-response-gate default observe stdout {}" >&2
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

mcpresp_no_key_home="$workdir/mcpresp-no-key-home"
mkdir -p "$mcpresp_no_key_home"
set +e
mcpresp_no_key_out="$(printf '%s' "$mcpresp_cursor_payload" | HOME="$mcpresp_no_key_home" OFFSEND_SEAL_KEY= "$CLI_PATH" check --adapter cursor --mcp-response-gate --no-notify --working-directory "$mcpresp_seal_repo" 2>/dev/null)"
set -e
if ! echo "$mcpresp_no_key_out" | grep -q 'updated_mcp_tool_output'; then
  echo "Expected cursor seal mode without a key to withhold the MCP response" >&2
  echo "$mcpresp_no_key_out" >&2
  exit 1
fi
if echo "$mcpresp_no_key_out" | grep -q 'AKIA1234567890ABCDEF'; then
  echo "Cursor seal mode without a key must not pass through the plaintext secret" >&2
  exit 1
fi

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
mcpresp_cursor_seal_out="$(printf '%s' "$mcpresp_cursor_payload" | HOME="$mcpresp_seal_home" "$CLI_PATH" check --adapter cursor --mcp-response-gate --no-notify --working-directory "$mcpresp_seal_repo" 2>/dev/null)"
set -e
if ! echo "$mcpresp_cursor_seal_out" | grep -q 'updated_mcp_tool_output'; then
  echo "Expected cursor seal mode updated_mcp_tool_output" >&2
  echo "$mcpresp_cursor_seal_out" >&2
  exit 1
fi
if echo "$mcpresp_cursor_seal_out" | grep -q 'AKIA1234567890ABCDEF'; then
  echo "Cursor sealed output must not contain the plaintext secret" >&2
  exit 1
fi

set +e
mcpresp_oversized_out="$(
  {
    printf '%s' '{"tool_name":"MCP:test/large","tool_output":"'
    dd if=/dev/zero bs=2097153 count=1 2>/dev/null | tr '\0' 'a'
    printf '%s' '"}'
  } | "$CLI_PATH" check --adapter cursor --mcp-response-gate --no-notify 2>/dev/null
)"
set -e
if ! echo "$mcpresp_oversized_out" | grep -q 'updated_mcp_tool_output'; then
  echo "Expected oversized Cursor MCP response to be safely withheld" >&2
  echo "$mcpresp_oversized_out" >&2
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

# Already-sealed {{…}} tokens authenticated by --key-file must not re-flag in
# the response gate (same filtering as the read-gate).
mcpresp_key_repo="$workdir/mcpresp-key"
mkdir -p "$mcpresp_key_repo"
"$CLI_PATH" keygen -o "$mcpresp_key_repo/custom.key"
# offsend:ignore-next-line
printf '%s' 'AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF' > "$mcpresp_key_repo/secret.txt"
"$CLI_PATH" seal secret.txt --working-directory "$mcpresp_key_repo" --key-file custom.key -o sealed.txt --quiet
mcpresp_sealed_body="$(tr -d '\n' < "$mcpresp_key_repo/sealed.txt")"
set +e
mcpresp_sealed_out="$(printf '{"tool_name":"mcp__github__get","tool_response":"%s"}' "$mcpresp_sealed_body" | "$CLI_PATH" check --adapter claude --mcp-response-gate --no-notify --key-file "$mcpresp_key_repo/custom.key" 2>/tmp/offsend-mcpresp-key-stderr.$$)"
set -e
if [[ "$mcpresp_sealed_out" != "{}" ]]; then
  echo "Expected sealed tokens (custom key) in an MCP response to produce no findings" >&2
  echo "$mcpresp_sealed_out" >&2
  cat /tmp/offsend-mcpresp-key-stderr.$$ >&2
  rm -f /tmp/offsend-mcpresp-key-stderr.$$
  exit 1
fi
if grep -q 'contains secrets' /tmp/offsend-mcpresp-key-stderr.$$; then
  echo "Expected no secret warning for authenticated sealed tokens" >&2
  cat /tmp/offsend-mcpresp-key-stderr.$$ >&2
  rm -f /tmp/offsend-mcpresp-key-stderr.$$
  exit 1
fi
rm -f /tmp/offsend-mcpresp-key-stderr.$$

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-mcp-response-gate
if grep -q -- "--mcp-response-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-mcp-response-gate to remove the managed response-gate entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-mcp-response-gate
if ! grep -q -- "--mcp-response-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-mcp-response-gate alias to add the response-gate command" >&2
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
subagent_nested="$(printf '%s' '{"tool_name":"Task","tool_input":{"prompt":"use AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF","subagent_type":"explore"}}' | "$CLI_PATH" check --adapter cursor --subagent-gate --no-notify 2>/dev/null)"
if ! echo "$subagent_nested" | grep -q '"deny"'; then
  echo "Expected subagent-gate deny for nested tool_input secrets" >&2
  echo "$subagent_nested" >&2
  exit 1
fi
subagent_fail_closed="$(printf '%s' 'not-json' | "$CLI_PATH" check --adapter cursor --subagent-gate --no-notify 2>/dev/null)"
if ! echo "$subagent_fail_closed" | grep -q '"deny"'; then
  echo "Expected subagent-gate fail-closed deny for invalid JSON" >&2
  echo "$subagent_fail_closed" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --no-subagent-gate
if grep -q -- "--subagent-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-subagent-gate to remove the managed subagent-gate entry" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

if grep -q '"Task"' "$repo/.cursor/hooks.json"; then
  echo "Expected --no-subagent-gate to remove Task preToolUse matcher" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q -- "--mcp-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --no-subagent-gate to keep mcp-gate" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook install --path "$repo" --target cursor --cli-path "$CLI_PATH" --with-subagent-gate
if ! grep -q -- "--subagent-gate" "$repo/.cursor/hooks.json"; then
  echo "Expected --with-subagent-gate alias to add the subagent-gate command" >&2
  cat "$repo/.cursor/hooks.json" >&2
  exit 1
fi

"$CLI_PATH" hook uninstall --path "$repo" --target cursor
if grep -q "OFFSEND_MANAGED_HOOK=1" "$repo/.cursor/hooks.json" 2>/dev/null; then
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
if ! grep -q "OFFSEND_MANAGED_HOOK=1" "$combined/.cursor/hooks.json"; then
  echo "Expected default install to add the cursor hook" >&2
  exit 1
fi
if ! grep -q "OFFSEND_MANAGED_HOOK=1" "$combined/.claude/settings.json"; then
  echo "Expected default install to add the claude hook" >&2
  exit 1
fi
if ! grep -q "PostToolUse" "$combined/.claude/settings.json" || ! grep -q -- "--mcp-response-gate" "$combined/.claude/settings.json"; then
  echo "Expected default claude install to add PostToolUse mcp-response-gate" >&2
  cat "$combined/.claude/settings.json" >&2
  exit 1
fi
if ! grep -q "OFFSEND_MANAGED_HOOK=1" "$combined/.codex/hooks.json"; then
  echo "Expected default install to add the codex hook (~/.codex detected)" >&2
  exit 1
fi
if [[ -e "$combined/.windsurf/hooks.json" ]]; then
  echo "Expected default install to skip windsurf (not detected)" >&2
  exit 1
fi
# Multi-target install must keep direct gates for cursor/claude after
# installing gate-unsupported targets such as codex.
if ! grep -q "beforeReadFile" "$combined/.cursor/hooks.json"; then
  echo "Expected default install to keep cursor beforeReadFile" >&2
  cat "$combined/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q -- "--mcp-gate" "$combined/.cursor/hooks.json" || ! grep -q "beforeMCPExecution" "$combined/.cursor/hooks.json"; then
  echo "Expected default install to keep cursor mcp-gate after multi-target install" >&2
  cat "$combined/.cursor/hooks.json" >&2
  exit 1
fi
if ! grep -q -- "--subagent-gate" "$combined/.cursor/hooks.json" || ! grep -q "subagentStart" "$combined/.cursor/hooks.json"; then
  echo "Expected default install to keep cursor subagent-gate after multi-target install" >&2
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
if grep -q "OFFSEND_MANAGED_HOOK=1" "$combined/.cursor/hooks.json" 2>/dev/null; then
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

# hooks.enabled: false skips install; check --policy does not fail for missing hooks.
disabled_repo="$workdir/hooks-disabled"
mkdir -p "$disabled_repo"
git -C "$disabled_repo" init >/dev/null
git -C "$disabled_repo" config user.email "ci@example.com"
git -C "$disabled_repo" config user.name "Offsend CI"
printf '%s\n' \
  "version: 1" \
  "ignore:" \
  "  commit: true" \
  "  patterns: []" \
  "hooks:" \
  "  enabled: false" > "$disabled_repo/.offsend.yml"
HOME="$sync_home" "$CLI_PATH" sync --path "$disabled_repo" --format json >/tmp/offsend-hooks-disabled.$$
if [[ -f "$disabled_repo/.git/hooks/pre-commit" ]]; then
  echo "Expected hooks.enabled:false sync not to install git pre-commit" >&2
  exit 1
fi
if ! grep -q '"reason"[[:space:]]*:[[:space:]]*"hooks.enabled is false"' /tmp/offsend-hooks-disabled.$$; then
  echo "Expected sync JSON reason hooks.enabled is false" >&2
  cat /tmp/offsend-hooks-disabled.$$ >&2
  exit 1
fi
HOME="$sync_home" "$CLI_PATH" check --policy "$disabled_repo" --format json \
  >/tmp/offsend-hooks-disabled-policy.$$
if grep -q '"kind"[[:space:]]*:[[:space:]]*"hooks"' /tmp/offsend-hooks-disabled-policy.$$; then
  echo "Expected check --policy not to emit hooks findings when hooks.enabled is false" >&2
  cat /tmp/offsend-hooks-disabled-policy.$$ >&2
  exit 1
fi
rm -f /tmp/offsend-hooks-disabled.$$ /tmp/offsend-hooks-disabled-policy.$$

# hooks.enabled default true: check --policy fails until sync installs hooks.
required_repo="$workdir/hooks-required"
mkdir -p "$required_repo"
git -C "$required_repo" init >/dev/null
git -C "$required_repo" config user.email "ci@example.com"
git -C "$required_repo" config user.name "Offsend CI"
printf '%s\n' \
  "version: 1" \
  "ignore:" \
  "  commit: true" \
  "  patterns: []" \
  "hooks:" \
  "  publish: false" > "$required_repo/.offsend.yml"
set +e
HOME="$sync_home" "$CLI_PATH" check --policy "$required_repo" --format json \
  >/tmp/offsend-hooks-required-policy.$$ 2>/dev/null
required_policy_status="$?"
set -e
if [[ "$required_policy_status" -eq 0 ]]; then
  echo "Expected check --policy to fail when hooks.enabled (default) and hooks missing" >&2
  cat /tmp/offsend-hooks-required-policy.$$ >&2
  exit 1
fi
if ! grep -q '"id"[[:space:]]*:[[:space:]]*"git-pre-commit"' /tmp/offsend-hooks-required-policy.$$; then
  echo "Expected check --policy JSON to include git-pre-commit finding" >&2
  cat /tmp/offsend-hooks-required-policy.$$ >&2
  exit 1
fi
HOME="$sync_home" "$CLI_PATH" sync --path "$required_repo" >/dev/null
HOME="$sync_home" "$CLI_PATH" check --policy "$required_repo" --format json \
  >/tmp/offsend-hooks-required-ok.$$
if grep -q '"kind"[[:space:]]*:[[:space:]]*"hooks"' /tmp/offsend-hooks-required-ok.$$; then
  echo "Expected no hooks policy findings after sync installed hooks" >&2
  cat /tmp/offsend-hooks-required-ok.$$ >&2
  exit 1
fi
rm -f /tmp/offsend-hooks-required-policy.$$ /tmp/offsend-hooks-required-ok.$$

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

# --- sandbox: declaration -> native configs, verification, shell-gate bridge ---
# The layer the shell-gate declines to close. Assertions stay on Cursor because
# it is never wrapped by nono, so the outcome does not depend on what the CI
# machine happens to have installed.
sandbox_repo="$workdir/sandbox-repo"
sandbox_home="$workdir/sandbox-home"
mkdir -p "$sandbox_repo" "$sandbox_home"
git -C "$sandbox_repo" init >/dev/null
git -C "$sandbox_repo" config user.email "ci@example.com"
git -C "$sandbox_repo" config user.name "Offsend CI"
printf '%s\n' \
  "version: 1" \
  "" \
  "ignore:" \
  "  patterns:" \
  "    - \"secrets/\"" \
  "    - \"*.pem\"" \
  "" \
  "hooks:" \
  "  enabled: false" \
  "" \
  "sandbox:" \
  "  enabled: true" \
  "  network:" \
  "    default: deny" \
  "    allow: []" > "$sandbox_repo/.offsend.yml"

HOME="$sandbox_home" "$CLI_PATH" sync --path "$sandbox_repo" --no-hooks --format json \
  >/tmp/offsend-sandbox-sync.$$ 2>/tmp/offsend-sandbox-sync-err.$$
if [[ ! -f "$sandbox_repo/.cursor/sandbox.json" ]]; then
  echo "Expected sandbox.enabled to materialize .cursor/sandbox.json" >&2
  cat /tmp/offsend-sandbox-sync-err.$$ >&2
  exit 1
fi
if ! grep -q '"default"[[:space:]]*:[[:space:]]*"deny"' "$sandbox_repo/.cursor/sandbox.json"; then
  echo "Expected Cursor sandbox network default deny" >&2
  cat "$sandbox_repo/.cursor/sandbox.json" >&2
  exit 1
fi
if ! grep -q '"mechanism"[[:space:]]*:[[:space:]]*"cursorNative"' /tmp/offsend-sandbox-sync.$$; then
  echo "Expected sync JSON to name the mechanism chosen for cursor" >&2
  cat /tmp/offsend-sandbox-sync.$$ >&2
  exit 1
fi
# Basename globs cannot be expressed as sandbox paths and must be reported, not
# expanded against the current tree — an expanded list goes stale silently.
if ! grep -q '\*\.pem' /tmp/offsend-sandbox-sync.$$; then
  echo "Expected sync JSON to report *.pem as an uncovered sandbox pattern" >&2
  cat /tmp/offsend-sandbox-sync.$$ >&2
  exit 1
fi
rm -f /tmp/offsend-sandbox-sync.$$ /tmp/offsend-sandbox-sync-err.$$

set +e
HOME="$sandbox_home" "$CLI_PATH" check --policy "$sandbox_repo" --format json \
  >/tmp/offsend-sandbox-policy.$$ 2>/dev/null
sandbox_policy_status="$?"
set -e
if [[ "$sandbox_policy_status" -ne 0 ]]; then
  echo "Expected check --policy to pass on freshly synced sandbox configs, got $sandbox_policy_status" >&2
  cat /tmp/offsend-sandbox-policy.$$ >&2
  exit 1
fi
rm -f /tmp/offsend-sandbox-policy.$$

# Hook install rewrites .claude/settings.json, where the Claude sandbox block
# also lives. A full sync must leave that block intact, or verification would
# report drift against Offsend's own writes.
HOME="$sandbox_home" "$CLI_PATH" sync --path "$sandbox_repo" --format json >/dev/null 2>&1
if ! grep -q '"sandbox"' "$sandbox_repo/.claude/settings.json"; then
  echo "Expected hook install to preserve the Claude sandbox block" >&2
  cat "$sandbox_repo/.claude/settings.json" >&2
  exit 1
fi
set +e
HOME="$sandbox_home" "$CLI_PATH" check --policy "$sandbox_repo" --format json \
  >/tmp/offsend-sandbox-drift.$$ 2>/dev/null
sandbox_drift_status="$?"
set -e
if [[ "$sandbox_drift_status" -ne 0 ]]; then
  echo "Expected no sandbox drift after a full sync, got $sandbox_drift_status" >&2
  cat /tmp/offsend-sandbox-drift.$$ >&2
  exit 1
fi
rm -f /tmp/offsend-sandbox-drift.$$

# insecure_none keeps the file in place while removing the sandbox: exactly the
# kind of weakening verification exists for.
printf '%s\n' '{"type":"insecure_none","networkPolicy":{"default":"deny","allow":[]}}' \
  > "$sandbox_repo/.cursor/sandbox.json"
set +e
HOME="$sandbox_home" "$CLI_PATH" check --policy "$sandbox_repo" --format json \
  >/tmp/offsend-sandbox-weak.$$ 2>/dev/null
sandbox_weak_status="$?"
set -e
if [[ "$sandbox_weak_status" -eq 0 ]]; then
  echo "Expected check --policy to fail on a weakened sandbox (insecure_none)" >&2
  cat /tmp/offsend-sandbox-weak.$$ >&2
  exit 1
fi
if ! grep -q 'insecure_none' /tmp/offsend-sandbox-weak.$$; then
  echo "Expected the failing finding to name insecure_none" >&2
  cat /tmp/offsend-sandbox-weak.$$ >&2
  exit 1
fi
rm -f /tmp/offsend-sandbox-weak.$$

# The bridge: one boolean the editor states per command. A rewritten command
# cannot change it, which is why this rule is admissible while a signature is not.
sandbox_unsandboxed="$(printf '%s' '{"command":"ls","sandbox":false}' | HOME="$sandbox_home" "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$sandbox_repo" 2>/dev/null)"
if ! echo "$sandbox_unsandboxed" | grep -q '"deny"'; then
  echo "Expected shell-gate deny for an unsandboxed command under sandbox.enabled" >&2
  echo "$sandbox_unsandboxed" >&2
  exit 1
fi
sandbox_sandboxed="$(printf '%s' '{"command":"ls","sandbox":true}' | HOME="$sandbox_home" "$CLI_PATH" check --adapter cursor --shell-gate --no-notify --working-directory "$sandbox_repo" 2>/dev/null)"
if ! echo "$sandbox_sandboxed" | grep -q '"allow"'; then
  echo "Expected shell-gate allow for a sandboxed command" >&2
  echo "$sandbox_sandboxed" >&2
  exit 1
fi

echo "CLI E2E smoke passed."
