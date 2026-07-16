# CLI reference

The `offsend` command runs locally on **macOS and Linux** (x86_64 / arm64). Install:

```bash
curl -fsSL https://install.offsend.io/cli | bash
offsend doctor
```

Project rules live in [`.offsend.yml`](configuration.md) at the repository root. CLI flags override config when passed explicitly.

---

## Command overview

| Command | Purpose |
| --- | --- |
| [`offsend doctor`](#offsend-doctor) | Verify CLI, git, settings, hooks, seal key |
| [`offsend show`](#offsend-show) | List sensitive paths visible to AI tools (no file contents) |
| [`offsend prepare`](#offsend-prepare) | Create missing AI ignore files |
| [`offsend ignore`](#offsend-ignore) | Add paths or patterns to every AI ignore file |
| [`offsend check`](#offsend-check) | Scan files, staged changes, stdin, or editor hook JSON |
| [`offsend init`](#offsend-init) | Create `.offsend.yml` |
| [`offsend edit`](#offsend-edit) | Open `.offsend.yml` in `$EDITOR` |
| [`offsend hook`](#offsend-hook) | Install / remove / status for git and AI-editor hooks |
| [`offsend seal`](#offsend-seal) | Replace secrets with reversible seal tokens |
| [`offsend unseal`](#offsend-unseal) | Restore plaintext from seal tokens |
| [`offsend keygen`](#offsend-keygen) | Generate a 32-byte seal key |
| [`offsend report`](#offsend-report) | Anonymized JSON hygiene report (no paths) |

---

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | Findings (`offsend check` with `--fail-on block` or `warn`) |
| `2` | Error (invalid args, I/O, doctor unhealthy, …) |
| `3` | Hook not installed or broken (`offsend hook status`) |

---

## `offsend doctor`

Verify local setup: settings, CLI path, git, project config, optional AI hooks, seal key.

```bash
offsend doctor
offsend doctor --format json
```

| Flag | Description |
| --- | --- |
| `--format text\|json` | Output format (default: `text`) |

Exits `2` when any check has status `fail`. AI hooks and seal key warnings are informational (`warn`).

Checks include `ai-wrapper-prompt` / `ai-wrapper-read` (managed marker + version) when AI hooks are installed.

---

## `offsend show`

Read-only audit: which sensitive **paths** AI tools can see (ignore rules only — **does not read file contents**).

```bash
offsend show
offsend show ./my-project
offsend show --format json
```

| Argument / flag | Description |
| --- | --- |
| `[path]` | Directory to inspect (default: current directory) |
| `--format text\|json` | Output format |

Exits `0` when paths are exposed (informational). Exits `2` on errors (e.g. unreadable directory).

---

## `offsend prepare`

Create missing AI ignore files (`.cursorignore`, `.claudeignore`, `.aiexclude`, `.geminiignore`, …). Never overwrites existing ignore files unless `--sync-patterns` appends patterns.

```bash
offsend prepare
offsend prepare --dry-run
offsend prepare --sync-patterns
offsend prepare --format json
```

| Argument / flag | Description |
| --- | --- |
| `[path]` | Project directory (default: current directory) |
| `--dry-run` | Preview without writing |
| `--sync-patterns` | Append missing sensitive-data patterns to existing ignore files |
| `--format text\|json` | Output format |

Exits `2` on write errors.

---

## `offsend ignore`

Add paths or glob patterns to every AI ignore file in the project. Updates all ignore files that already exist (`.cursorignore`, `.claudeignore`, `.aiexclude`, …); if the project has none yet, the standard set is created first (same files as `offsend prepare`). `.gitignore` is never modified.

```bash
offsend ignore secrets/prod.json
offsend ignore secrets/ '*.pem'
offsend ignore config/prod.json --dry-run
offsend ignore '*.tfstate' --format json
```

| Argument / flag | Description |
| --- | --- |
| `<pattern...>` | Paths or gitignore-style globs to add |
| `--path DIR` | Project directory (default: current directory) |
| `--dry-run` | Preview without writing |
| `--format text\|json` | Output format |

Patterns are normalized against the project root: existing directories gain a trailing slash, absolute paths under the root become relative, globs pass through as-is. Lines already present are skipped, so the command is idempotent.

Note: this manages *editor* ignore files. Scanner exclusions live in `.offsend.yml` under `check.exclude`.

Exits `2` on write errors or paths outside the project.

---

## `offsend check`

Scan file contents for API keys, tokens, private keys, PII, and custom dictionary terms.

### File and git scans

```bash
offsend check README.md Sources/
offsend check --staged
offsend check --staged --fail-on block --quiet
offsend check . --policy
offsend check --format json --verbose
```

| Argument / flag | Description |
| --- | --- |
| `[paths…]` | Files or directories (recursive). Omit with `--staged`, `--policy`, or `--stdin` |
| `--staged` | Scan staged files only (exports git blobs to a temp dir) |
| `--policy` | Also run workspace policy checks (ignore files, exposed paths) |
| `--fail-on block\|warn\|none` | Exit policy (default from `.offsend.yml` or `block`) |
| `--format text\|json` | Report format |
| `--quiet` | Findings and errors only |
| `--verbose` | List every finding and skipped file |
| `--working-directory PATH` | Base for relative paths |

Cannot combine `--staged` with explicit paths. `--policy` with multiple directory arguments requires a single directory.
If any file cannot be read or scanned, `check` exits `2` even with `--fail-on none`; an incomplete scan never reports success.

### Stdin (raw text)

```bash
printf '%s' 'AWS_ACCESS_KEY_ID=AKIA…' | offsend check --stdin
printf '%s' '…' | offsend check --stdin --format json --fail-on none
printf '%s' '…' | offsend check --stdin --gate-secrets
```

| Flag | Description |
| --- | --- |
| `--stdin` | Read text from stdin (max **2 MiB**) |
| `--gate-secrets` | Print secret-gate JSON (`hasSecrets`, `findingTypes`); exit `1` when secrets found. Requires `--stdin`, no `--adapter` |
| `--no-secrets-only` | With `--gate-secrets`, include non-secret detectors (e.g. email) |

`--stdin --format json` returns the **risk report**. `--gate-secrets` returns the **gate view** for scripts.

### AI-editor hook mode (`--adapter`)

Used by installed hooks and for manual testing. Reads **editor hook JSON** from stdin.

```bash
printf '%s' '{"prompt":"…"}' | offsend check --adapter cursor --hook-policy soft-block --no-notify
offsend check --adapter claude --read-gate --no-notify   # file-read gate
```

| Flag | Default | Description |
| --- | --- | --- |
| `--adapter cursor\|claude\|windsurf\|codex` | — | Hook adapter; implies stdin JSON |
| `--hook-policy advise\|soft-block\|block` | `soft-block` | See [Hook policies](#hook-policies) |
| `--secrets-only` / `--no-secrets-only` | on | Secret-shaped findings only (excludes noisy `highEntropyString`) |
| `--notify` / `--no-notify` | on (Darwin) | macOS notification; **off** in installed wrappers |
| `--seal-copy` | off | Write sealed copy to private temp file + clipboard |
| `--debug-hook` | off | Append diagnostics to `hook-debug.log` (no secret values) |
| `--read-gate` | off | File-read gate for Cursor / Claude: sensitive paths + secret content scan |
| `--shell-gate` | off | Sensitive-path gate for Cursor / Claude shell hooks (`ask` on findings) |
| `--key-file PATH` | — | Seal key file for `--seal-copy` / `--hook-policy block` |
| `--key-name NAME` | — | Named key in `~/.offsend/keys/NAME.key` |

Installed wrappers run: `check --adapter … --hook-policy … --secrets-only --no-notify`.

**Fail-open:** infrastructure errors (bad JSON, oversized stdin, settings load, invalid `--hook-policy`) allow the prompt through so a broken hook does not block chat. stderr shows short codes (`invalid_json`, `stdin_too_large`, …); details go to `--debug-hook` only.

Prompt scanning does **not** honor inline `offsend:ignore` bypasses.

---

## `offsend init`

Create a starter [`.offsend.yml`](configuration.md) at the git repository root (or current directory if not in a repo).

```bash
offsend init
offsend init --template node
offsend init --template js,swift
offsend init --template python --merge-exclude
offsend init --list-templates
offsend init --force
```

| Flag | Description |
| --- | --- |
| `--path DIR` | Directory to initialize (default: current directory) |
| `--template NAME` | Exclude preset(s); repeatable or comma-separated. Aliases: `js`/`ts` → `node`, `ios` → `swift`. Always includes `common` |
| `--list-templates` | Print preset catalog and exit |
| `--merge-exclude` | Add template patterns to existing config (no overwrite) |
| `--force` | Overwrite existing file |

---

## `offsend edit`

Open `.offsend.yml` in `$VISUAL` or `$EDITOR` (macOS falls back to `open -t`).

```bash
offsend edit
offsend edit --path /path/to/repo
```

---

## `offsend hook`

Manage **git pre-commit** hooks and **AI-editor prompt hooks** (Cursor, Claude Code, Windsurf, Codex).

### `hook install`

**Default (no `--target`): full protection** — git pre-commit hook **plus** AI-editor hooks for detected editors (Cursor and Claude always; Windsurf/Codex when a repo-local or home config directory exists). If the git hook cannot be installed (e.g. a foreign pre-commit hook exists), it is skipped with a warning and the AI hooks still install.

```bash
offsend hook install                  # git hook + detected AI editors
offsend hook install --path /path/to/repo
offsend hook install --force          # also overwrite foreign hooks/wrappers
```

**Git only:**

```bash
offsend hook install --target git
offsend hook install --target git --fail-on block --policy
```

| Flag | Description |
| --- | --- |
| `--target git` | Git hook only |
| `--type pre-commit` | Hook type (only `pre-commit` today) |
| `--fail-on block\|warn\|none` | Exit policy for `offsend check --staged` |
| `--policy` | Include `--policy` in the hook command |
| `--force` | Overwrite a foreign pre-commit hook |
| `--cli-path PATH` | `offsend` binary used by the hook (default: install-time path, then `PATH`) |

**AI-editor hooks only:**

```bash
offsend hook install --target cursor
offsend hook install --target claude
offsend hook install --target windsurf
offsend hook install --target codex
offsend hook install --target all

offsend hook install --target cursor --hook-policy advise
offsend hook install --target claude --no-read-gate
```

| Flag | Description |
| --- | --- |
| `--target cursor\|claude\|windsurf\|codex\|all` | AI editor target |
| `--hook-policy advise\|soft-block\|block` | Override default policy (`soft-block`) |
| `--read-gate` / `--no-read-gate` | File-read path gates (**Cursor + Claude only**). **On by default**; `--no-read-gate` disables |
| `--shell-gate` | Shell-command gate (**Cursor + Claude only**). **Opt-in**; findings ask for confirmation instead of blocking |
| `--cli-path PATH` | CLI for wrapper scripts |
| `--force` | Overwrite a foreign git hook or AI wrapper; managed files refresh automatically |

Install **merges** into existing editor configs (does not remove foreign hooks). Writes:

- `.offsend/hooks/check-prompt.sh` — install-time CLI path first, then `command -v offsend`
- `.offsend/hooks/check-read.sh` — read gate (default on for Cursor/Claude; skipped with `--no-read-gate`)
- `.offsend/hooks/check-shell.sh` — shell gate (only with `--shell-gate`)
- managed entry in editor config (`_offsend` metadata)

Existing AI wrappers are updated only when they contain a valid Offsend managed marker in the script header. A foreign wrapper is preserved unless `--force` is explicit.

Commit `.offsend/hooks/` and the editor config to share with the team.

| Target | Config file | Default `--hook-policy` | Read gate |
| --- | --- | --- | --- |
| `cursor` | `.cursor/hooks.json` | `soft-block` | on by default |
| `claude` | `.claude/settings.json` | `soft-block` | on by default |
| `windsurf` | `.windsurf/hooks.json` | `soft-block` | not supported |
| `codex` | `.codex/hooks.json` | `soft-block` | not supported |

### `hook uninstall`

```bash
offsend hook uninstall            # remove every Offsend-managed hook (git + AI)
offsend hook uninstall --target git
offsend hook uninstall --target cursor
offsend hook uninstall --target all
offsend hook uninstall --force    # git: remove even if not Offsend-managed
```

| Flag | Description |
| --- | --- |
| `--target git\|cursor\|…\|all` | Target (default: every Offsend-managed hook) |
| `--type pre-commit` | Git hook type |
| `--force` | Git: remove non-managed hook file |

Without `--target`, missing hooks are skipped; a manually modified git hook is left in place with a warning (use `--target git --force`).

### `hook status`

```bash
offsend hook status               # git + all AI targets
offsend hook status --target git
offsend hook status --target cursor
offsend hook status --target all --format json
```

| Flag | Description |
| --- | --- |
| `--target git\|cursor\|…\|all` | Target (default: git plus all AI targets) |
| `--format text\|json` | Output format |
| `--type pre-commit` | Git hook type |

- No `--target`: shows the git hook and all four editors; exits `3` if the git hook is not installed or any AI hook is **broken**.
- Single AI target: exits `3` if not installed or **broken** (wrapper missing, tampered, or outdated).
- `--target all`: shows all four editors; exits `3` only if any target is **broken** (not installed is OK).

---

## AI editor hooks

Offsend checks prompts **before** they reach Cursor, Claude Code, Windsurf, or Codex. Editors cannot rewrite prompt text via hooks — Offsend **advises** or **soft-blocks** and recommends moving secrets to env / ignore files.

### Hook policies

| Policy | Behavior |
| --- | --- |
| `advise` | Prompt proceeds. Claude/Codex show `systemMessage`; Cursor relies on hook stderr / optional notification |
| `soft-block` | **Default for all editors.** Block once with remediation text; clean prompts pass through |
| `block` | Same UI block as `soft-block`, plus seal-copy to clipboard when a seal key is available |

`block` without a key still blocks in the editor; stderr hints `offsend keygen --default`.

### Read-gate (on by default)

The read gate protects Cursor `beforeReadFile` and Claude `PreToolUse` (`Read|Edit|Write`); it is installed by default for these targets (disable with `--no-read-gate`). It:

1. **Denies sensitive paths** — `.env`, `*.pem`, credentials-like names, and files under `.ssh`, `.aws`, `.kube`, `.docker`, `.gnupg`, `.azure`, `.fly`, …
2. **Scans file content for secrets** — uses the same secret detectors as the prompt gate (`--secrets-only` by default). Cursor supplies `content` in the hook JSON; Claude’s PreToolUse has no body, so Offsend reads a bounded UTF-8 prefix from disk (up to 50k characters). Binary / unreadable files skip the content step (path rules still apply).
3. **Claude Edit/Write** — same gate runs before edits so a model that already saw a secret cannot “proceed with the fix” via `Edit` after a later `Read` deny.

The prompt gate also scans file-like `@mentions` (for example `@index.js`) by reading a bounded prefix from disk, so attaching a secret file in the prompt can be blocked before the model turn starts.

On a secret hit the editor receives deny with a short remediation message (detector type names only — no secret values). Claude PreToolUse uses `hookSpecificOutput.permissionDecision: "deny"` (not the deprecated top-level `decision: "block"`). Hook command timeout defaults to 30s to avoid cold-start fail-open.

Cursor may not always enforce `beforeReadFile` deny (known IDE limitation; open tabs can bypass the hook). Prefer `offsend prepare` / `.cursorignore` for hard blocks; treat read-gate as defense-in-depth.

### Shell-gate (opt-in)

`offsend hook install --target cursor --shell-gate` adds a gate for agent shell commands (Cursor `beforeShellExecution`, Claude `PreToolUse` matcher `Bash`). The command line is tokenized and checked against the same sensitive-path heuristics as the read-gate (`cat .env`, `cp ~/.ssh/id_rsa …`, `--key-file=prod.key`). Findings return **`ask`** — the editor requests user confirmation instead of blocking, which keeps false positives cheap. No shell grammar parsing, no file contents read; treat it as defense-in-depth.

Note: Cursor currently enforces only `deny` reliably; `ask` may not pause the command in all versions (known IDE limitation).

### Security notes

- Advice uses **detector type names only** — never secret prefixes/suffixes.
- Notifications: fixed short template (`N sensitive items…`).
- Sealed temp files: mode `0600`, best-effort cleanup after 1 hour; UI messaging is clipboard-only.
- Stdin capped at **2 MiB** (`check`, `seal`, `unseal`).
- Cursor `attachments` paths checked by name/extension (files not opened).
- Project `.offsend.yml` detector disables / dictionaries apply; macOS app settings also affect detection.
- `hook-debug.log` rotates at ~512 KiB; home paths redacted in log fields.

### Verify

```bash
offsend doctor
offsend hook status --target all
printf '%s' '{"prompt":"AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"}' \
  | offsend check --adapter cursor --hook-policy advise --no-notify --debug-hook
```

---

## `offsend seal`

Replace detected sensitive values with reversible `{{TYPE:v1.…}}` tokens.

```bash
offsend seal notes.txt -o notes.sealed.txt
offsend seal notes.txt --key-file ~/.offsend/seal.key -o notes.sealed.txt
offsend seal notes.txt -o notes.sealed.txt --force
cat prompt.txt | offsend seal
```

| Argument / flag | Description |
| --- | --- |
| `[path]` | Input file (default: stdin, max **2 MiB**) |
| `--key-file PATH` | Key file (32 raw bytes or base64) |
| `--key-name NAME` | Named key in `~/.offsend/keys/NAME.key` |
| `-o`, `--output PATH` | Output file (default: stdout); refuses an existing path |
| `--force` | Atomically replace an existing output; requires `--output` |
| `--max-plaintext-bytes N` | Fail if any single value exceeds N UTF-8 bytes |
| `--quiet` | Suppress `sealed N` on stderr |
| `--working-directory PATH` | Base for relative input, output, and `--key-file` paths |

Key resolution order: `--key-file` → `--key-name` → `OFFSEND_SEAL_KEY` → `~/.offsend/seal.key`.

---

## `offsend unseal`

Restore plaintext from seal tokens.

```bash
offsend unseal notes.sealed.txt
offsend unseal notes.sealed.txt --key-file ~/.offsend/seal.key
cat notes.sealed.txt | offsend unseal
```

| Argument / flag | Description |
| --- | --- |
| `[path]` | Input file (default: stdin, max **2 MiB**) |
| `--key-file`, `--key-name` | Same as `seal` |
| `-o`, `--output PATH` | Output file; refuses an existing path |
| `--force` | Atomically replace an existing output; requires `--output` |
| `--working-directory PATH` | Base for relative input, output, and `--key-file` paths |

---

## Seal key storage

CLI seal keys live under `~/.offsend/`:

| Path | Purpose |
| --- | --- |
| `~/.offsend/seal.key` | Default personal key (auto-resolved by `seal`, `unseal`, `check --hook-policy block`) |
| `~/.offsend/keys/NAME.key` | Optional named keys (`--key-name NAME`) |

Install the default key once:

```bash
offsend keygen --default
```

Create an additional named key without touching the default:

```bash
offsend keygen --name work
offsend seal notes.txt --key-name work
```

`keygen` refuses to overwrite an existing target unless you pass `--force`.

---

## `offsend keygen`

Generate a fresh 32-byte AES-256 seal key.

```bash
offsend keygen
offsend keygen --default
offsend keygen --name work
offsend keygen -o ~/.offsend/seal.key
offsend keygen --default --force
offsend keygen --default --raw
```

| Flag | Description |
| --- | --- |
| *(no flags)* | Print base64 key to stdout |
| `--default` | Write to `~/.offsend/seal.key` (refuses overwrite unless `--force`) |
| `--name NAME` | Write to `~/.offsend/keys/NAME.key` |
| `-o`, `--output PATH` | Write to a custom path |
| `--force` | Overwrite an existing key file (destructive; previous key is lost) |
| `--raw` | Write 32 raw bytes (requires a file target) |
| `--working-directory PATH` | Base for relative `--output` |

Use only one target: stdout, `--default`, `--name`, or `--output`.

---

## `offsend report`

Emit an anonymized, aggregated JSON report of AI context hygiene (**no file paths or names**). Useful for telemetry or compliance summaries.

```bash
offsend report
offsend report ./my-project --out report.json
```

| Argument / flag | Description |
| --- | --- |
| `[path]` | Directory to inspect (default: current directory) |
| `--out PATH` | Write JSON to file instead of stdout |

---

## Typical workflows

### Repository hygiene

```bash
offsend show
offsend prepare --dry-run
offsend prepare
offsend init --template node
offsend check --staged
offsend hook install
```

### AI-editor protection

```bash
offsend hook install          # git hook + prompt/read gates for detected editors
offsend hook status
offsend doctor
```

### CI

```yaml
- uses: actions/checkout@v4
- uses: Offsend/ai-hygiene@v1
  with:
    fail-on: block
```

Or: `offsend check --staged --fail-on block`.

---

## Related

- [Configuration (`.offsend.yml`)](configuration.md)
- [README](../README.md) — install options, app vs CLI, FAQ
- [`.offsend.yml.example`](../.offsend.yml.example) — annotated starter
