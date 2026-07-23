# CLI reference

The `offsend` command runs locally on **macOS and Linux** (x86_64 / arm64). Product overview: [README](../README.md).

Project rules live in [`.offsend.yml`](configuration.md) at the repository root — including the team AI-ignore patterns (`ignore.patterns`) that `offsend sync` materializes into every AI ignore file (and installs hooks). CLI flags override config when passed explicitly.

---

## Install

```bash
curl -fsSL https://install.offsend.io/cli | bash
offsend doctor
```

```bash
# Homebrew — macOS (cask) / Linux (formula)
brew install --cask offsend/tap/offsend-cli   # macOS
brew install offsend/tap/offsend-cli          # Linux

# No root
OFFSEND_INSTALL_DIR=$HOME/.local/bin OFFSEND_PREFIX=$HOME/.local/lib/offsend/cli \
  curl -fsSL https://install.offsend.io/cli | bash

# Docker
docker build -f CLI/Dockerfile -t offsend/cli .
docker run --rm -v "$PWD:/work" -w /work offsend/cli check README.md

# From source (Swift 6.0+)
swift build --product offsend -c release
.build/release/offsend doctor
```

Pin a release with `OFFSEND_VERSION=…`. On Linux, config lives under `$XDG_CONFIG_HOME/offsend` (typically `~/.config/offsend`). On macOS CLI, settings use Application Support / Keychain like the app.

The package is `offsend-cli`; the command is `offsend`. The macOS app also ships a bundled helper — see [macOS app](macos-app.md).

---

## Command overview

| Command | Purpose |
| --- | --- |
| [`offsend init`](#offsend-init) | Create `.offsend.yml` (wizard + ignore-file sync + optional baseline check) |
| [`offsend sync`](#offsend-sync) | Apply `.offsend.yml`: materialize AI ignore files + install hooks (post-clone) |
| [`offsend edit`](#offsend-edit) | Open `.offsend.yml` in `$EDITOR` |
| [`offsend protect`](#offsend-protect) | Hide exposed sensitive paths from AI (promote to `.offsend.yml` + sync) |
| [`offsend show`](#offsend-show) | List sensitive paths visible to AI tools (no file contents); `--report` for anonymized JSON |
| [`offsend ignore`](#offsend-ignore) | Add patterns to team policy (`.offsend.yml`) or locally (auto-materializes) |
| [`offsend check`](#offsend-check) | Scan files, staged changes, stdin, or editor hook JSON |
| [`offsend hook`](#offsend-hook) | Install / remove / status for git and AI-editor hooks |
| [`offsend history`](#agent-history) | Audit / scrub secrets in local Cursor & Claude transcripts |
| [`offsend seal`](#offsend-seal) | Replace secrets with reversible seal tokens |
| [`offsend unseal`](#offsend-unseal) | Restore plaintext from seal tokens |
| [`offsend keygen`](#offsend-keygen) | Generate a 32-byte seal key |
| [`offsend doctor`](#offsend-doctor) | Verify CLI, git, settings, hooks, seal key |

---

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | Findings (`offsend check` with `--fail-on block` or `warn`) |
| `2` | Error (invalid args, I/O, doctor unhealthy, …) |
| `3` | Hook not installed or broken (`offsend hook status`) |

---

## `offsend sync`

Apply an existing `.offsend.yml`: materialize `ignore.patterns` into every AI ignore file, then install the git pre-commit hook plus AI-editor hooks for detected editors. Idempotent — safe to re-run after clone or config edits. Requires `.offsend.yml` (run `offsend init` first).

```bash
offsend sync
offsend sync --path /path/to/repo
offsend sync --no-hooks          # ignore files only
offsend sync --dry-run           # preview ignore-file changes; hooks are not installed
offsend sync --format json
```

| Flag | Description |
| --- | --- |
| `--path DIR` | Project directory (default: current directory) |
| `--no-hooks` | Only materialize AI ignore files; skip git and AI-editor hook install |
| `--dry-run` | Show what ignore-file sync would change without writing; hooks are not installed |
| `--format text\|json` | Output format (default: `text`) |

Behavior notes:

- If ignore sync reports errors, hooks are skipped and the command exits `2`.
- A foreign (non-Offsend) git pre-commit hook is skipped with a warning; AI-editor hooks still install. AI-hook failures exit `2`.
- When `hooks.publish` is `false` (default), installed editor hook configs are added to the local git exclude so they stay untracked.
- Ignore materialization writes a managed block (`# >>> offsend managed` … `# <<< offsend managed`) into each AI ignore file; user lines outside the block are preserved. When `ignore.commit` is `false` (default), also updates `.gitignore` so those files stay untracked; when it is `true`, stale offsend entries are removed from `.gitignore`.
- Prefer `sync` after clone or after editing `.offsend.yml` by hand. For ignore files only (no hooks), use `--no-hooks`. Fine-grained hook control remains on [`hook install`](#hook-install).

---

## `offsend doctor`

Verify local setup: settings, CLI path, git, project config, optional AI hooks, seal key.

```bash
offsend doctor
offsend doctor --format json
offsend doctor --no-follow
```

| Flag | Description |
| --- | --- |
| `--format text\|json` | Output format (default: `text`) |
| `--no-follow` | Skip interactive “run next step?” prompt (default outside TTY) |

Exits `2` when any check has status `fail`. AI hooks and seal key warnings are informational (`warn`).

Checks include `ignore-sync` / `rules-drift` (shared `.offsend.yml` vs materialized ignore and privacy rule files), `ai-wrapper-prompt` / `ai-wrapper-read` / `ai-wrapper-shell` / `ai-wrapper-mcp` / `ai-wrapper-mcp-out` (managed marker + version) when those wrappers exist, `ai-shell-gate` / `ai-mcp-gate` / `ai-mcp-response-gate` (warn) when Cursor/Claude are installed without those gates, `hook-coverage-gaps` (residual limits when AI hooks are installed: MCP responses on Cursor, Claude subagents, Cursor open tabs, cloud sessions), `mcp-inventory` (configured MCP servers + policy), and `next-actions` (ranked hints: shared policy → sync / drift repair → protect → gates → history audit/scrub when transcripts exist → git hook). By default `show` / doctor **count** transcript files; enable content scan with `context.history.scan_in_show: true` or `offsend show --scan-history` (then doctor can suggest `history scrub` on real findings). Otherwise run `history audit`. In a TTY, doctor may offer to run the first suggested command. JSON includes `suggestedActions`. See also [FAQ → covers / does not cover](faq.md#what-does-offsend-cover-vs-not-cover).

---

## `offsend show`

Read-only audit: which sensitive **paths** AI tools can see (ignore rules only — **does not read file contents** of those paths). Also reports configured MCP servers, a local agent-history summary when present (file counts by default; content scan with `--scan-history` or `context.history.scan_in_show`), and **managed ignore drift** when local AI ignore files are behind `.offsend.yml` (fix with `offsend sync`).

```bash
offsend show
offsend show ./my-project
offsend show --format json
offsend show --scan-history                # content-scan local agent transcripts
offsend show --report                      # anonymized JSON, no paths
offsend show ./my-project --report --out report.json
```

| Argument / flag | Description |
| --- | --- |
| `[path]` | Directory to inspect (default: current directory) |
| `--format text\|json` | Output format (not combinable with `--report`, which is always JSON) |
| `--scan-history` | Content-scan local Cursor/Claude transcripts for secret-shaped findings (same detectors as `history audit`; slower). Or set `context.history.scan_in_show: true` |
| `--report` | Emit an anonymized, aggregated JSON report of AI context hygiene (**no file paths or names**) — for telemetry or compliance summaries |
| `--out PATH` | With `--report`: write JSON to file instead of stdout |

Exits `0` when paths are exposed (informational). Exits `2` on errors (e.g. unreadable directory).

See also: [`context.mcp` / `context.history`](configuration.md#contextmcp), [`offsend history`](#agent-history).

---

## `offsend protect`

Close gaps from the same path audit as `show`: add **required** exposures to `ignore.patterns` in `.offsend.yml`, then materialize AI ignore files (`.cursorignore`, `.claudeignore`, `.aiexclude`, …). Creates missing ignore files as needed.

```bash
offsend protect
offsend protect --dry-run
offsend protect --include-recommended
offsend protect ./my-project --format json
```

| Argument / flag | Description |
| --- | --- |
| `[path]` | Project directory (default: current directory) |
| `--dry-run` | Preview without writing |
| `--include-recommended` | Also ignore recommended exposures (SSH, AWS paths, …) |
| `--format text\|json` | Output format |

Prefer this after `offsend init`. Verify with `offsend show`, then run `offsend sync` to install hooks. Low-level alternative: `ignore`. For applying an existing config after a clone (no new patterns), use `sync` alone.

Exits `2` on write errors.

---

## `offsend ignore`

Add paths or globs to the **team** AI-ignore policy in `.offsend.yml` (`ignore.patterns`), then materialize them into AI ignore files. Commit `.offsend.yml` to share rules with the team.

```bash
offsend ignore secrets/prod.json          # → .offsend.yml + materialize
offsend ignore secrets/ '*.pem'
offsend ignore --local config/prod.json   # local ignore files only (not published)
offsend ignore config/prod.json --dry-run
offsend ignore '*.tfstate' --format json
offsend ignore --merge-defaults           # upgrade: merge built-in privacy patterns
offsend ignore --merge-defaults --dry-run

# after editing .offsend.yml by hand (e.g. via offsend edit):
offsend sync                              # re-materialize + hooks
offsend sync --no-hooks                   # ignore files only
```

| Argument / flag | Description |
| --- | --- |
| `<pattern...>` | Paths or gitignore-style globs to add (required unless `--merge-defaults`) |
| `--merge-defaults` | Merge current built-in AI privacy defaults into `ignore.patterns` (CLI upgrade path); do not pass patterns |
| `--local` | Write only to AI ignore files on this machine; do **not** update `.offsend.yml` |
| `--path DIR` | Project directory (default: current directory) |
| `--dry-run` | Preview without writing |
| `--format text|json` | Output format |

With `--local`, the CLI prints a warning that the rule will not be shared. To publish later, re-run without `--local`. `--merge-defaults` cannot be combined with `--local` or pattern arguments. It is a **union**: built-in defaults you deliberately removed from `ignore.patterns` are re-added — preview with `--dry-run` and review the `.offsend.yml` diff before committing.

Adding patterns already materializes ignore files. After editing `.offsend.yml` by hand, or when doctor / show / check report managed ignore drift (shared policy ahead of local ignore files), run [`offsend sync`](#offsend-sync) (or `sync --no-hooks` for ignore files only). Inside a git repository, files are always materialized at the repository root, regardless of the current directory.

Requires an existing `.offsend.yml` (run `offsend init` first) unless `--local` is used. Scanner exclusions remain under `check.exclude`. See also [Upgrading Offsend CLI](configuration.md#upgrading-offsend-cli-existing-offsendyml).

Exits `2` on write errors, paths outside the project, or missing project config (non-local).

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
printf '%s' 'AWS_ACCESS_KEY_ID=<redacted>' | offsend check --stdin
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

Used by installed hooks and for manual testing. Reads **editor hook JSON** from stdin. These flags are hidden from `check --help` (hook plumbing, not day-to-day use) but remain fully functional.

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
| `--shell-gate` | — | Sensitive-path gate for Cursor / Claude shell hooks (`ask` on findings); used by installed wrappers |
| `--mcp-gate` | — | MCP tool-call gate for Cursor / Claude: `context.mcp` policy + path/secret scan in args |
| `--mcp-response-gate` | — | MCP tool-**response** gate: secret-scan the response per `context.mcp.responses` (`observe`/`warn`/`seal`). Claude `PostToolUse` can rewrite the output (`seal`); Cursor `afterMCPExecution` is observe-only |
| `--subagent-gate` | — | Subagent spawn gate for Cursor: secret-scan task text |
| `--key-file PATH` | — | Seal key file for `--seal-copy` / `--hook-policy block` |
| `--key-name NAME` | — | Named key in `~/.offsend/keys/NAME.key` |

Installed wrappers run: `check --adapter … --hook-policy … --secrets-only --no-notify`.

**Fail-open:** infrastructure errors (bad JSON, oversized stdin, settings load, invalid `--hook-policy`) allow the prompt through so a broken hook does not block chat. stderr shows short codes (`invalid_json`, `stdin_too_large`, …); details go to `--debug-hook` only.

Prompt scanning does **not** honor inline `offsend:ignore` bypasses.

---

## `offsend init`

Create a starter [`.offsend.yml`](configuration.md) at the git repository root (or current directory if not in a repo). In a TTY, prompts for stack template(s), whether to keep AI ignore files out of git (`ignore.commit`), and whether AI editor hooks may be committed (`hooks.publish`). Then **materializes AI ignore files** (ignore-file half of `offsend sync`; does not install hooks) and runs a **baseline `check .`** (advise-only; does not fail `init`).

```bash
offsend init                      # TTY: prompts; then ignore-file sync + baseline check
offsend init --template node --no-ignore-commit --no-hooks-publish
offsend init --template js,swift
offsend init --template python --merge-exclude
offsend init --template node --strict-credentials
offsend init --list-templates
offsend init --force
offsend init --template node --no-check --no-sync
```

| Flag | Description |
| --- | --- |
| `--path DIR` | Directory to initialize (default: current directory) |
| `--template NAME` | Exclude preset(s); repeatable or comma-separated. Aliases: `js`/`ts` → `node`, `ios` → `swift`. Always includes `common`. **Required in non-TTY**; in a TTY, omit to be prompted (Enter = common only) |
| `--ignore-commit` / `--no-ignore-commit` | Set `ignore.commit` (default outside TTY: false) |
| `--hooks-publish` / `--no-hooks-publish` | Set `hooks.publish` (default outside TTY: false) |
| `--list-templates` | Print preset catalog and exit |
| `--merge-exclude` | Add template patterns to existing config (does not change `ignore` / `hooks.publish`) |
| `--strict-credentials` | Set `check.policy` / `hooks.policy` true and add a tighter `context` block (MCP ask, subagent deny, history audit). Editor soft-block unchanged — optional `hook install --hook-policy block`. See [configuration](configuration.md#strict-credentials-mode) |
| `--force` | Overwrite existing file |
| `--no-check` | Skip the baseline content scan |
| `--no-sync` | Skip materializing AI ignore files after writing the config |

Next steps printed: prefer `offsend protect` then `offsend sync`, or `offsend show` to verify the AI boundary.

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
offsend hook install                  # TTY: confirm plan, then git + detected AI editors
offsend hook install --yes            # skip confirmation
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
| `--yes` | Skip TTY confirmation for the default (no `--target`) install plan |
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
offsend hook install --target cursor --no-shell-gate
offsend hook install --target cursor --no-mcp-gate
```

| Flag | Description |
| --- | --- |
| `--target cursor\|claude\|windsurf\|codex\|all` | AI editor target |
| `--hook-policy advise\|soft-block\|block` | Override default policy (`soft-block`) |
| `--read-gate` / `--no-read-gate` | File-read path gates (**Cursor + Claude only**). **On by default**; `--no-read-gate` disables |
| `--shell-gate` / `--no-shell-gate` | Shell-command gate (**Cursor + Claude only**). **On by default**; findings ask for confirmation instead of blocking. `--no-shell-gate` disables |
| `--mcp-gate` / `--no-mcp-gate` | MCP tool-call gate (**Cursor + Claude only**). **On by default**; Cursor `beforeMCPExecution` with `failClosed: true`. `--no-mcp-gate` disables |
| `--mcp-response-gate` / `--no-mcp-response-gate` | MCP tool-**response** gate (**Cursor + Claude only**). **On by default**; Cursor `afterMCPExecution` (observe-only, fail-open), Claude `PostToolUse` matcher `mcp__.*` (can rewrite output in `seal` mode). `--no-mcp-response-gate` disables |
| `--subagent-gate` / `--no-subagent-gate` | Subagent spawn gate (**Cursor only**). **On by default**; `subagentStart` with `failClosed: true`. `--no-subagent-gate` disables |
| `--cli-path PATH` | CLI for wrapper scripts |
| `--force` | Overwrite a foreign git hook or AI wrapper; managed files refresh automatically |

Gate flags also accept `--with-read-gate` / `--with-shell-gate` / `--with-mcp-gate` / `--with-mcp-response-gate` / `--with-subagent-gate` as aliases.

Install **merges** into existing editor configs (does not remove foreign hooks). Writes:

- `.offsend/hooks/check-prompt.sh` — install-time CLI path first, then `command -v offsend`
- `.offsend/hooks/check-read.sh` — read gate (default on for Cursor/Claude; skipped with `--no-read-gate`)
- `.offsend/hooks/check-shell.sh` — shell gate (default on for Cursor/Claude; skipped with `--no-shell-gate`)
- `.offsend/hooks/check-mcp.sh` — MCP gate (default on for Cursor/Claude; skipped with `--no-mcp-gate`)
- `.offsend/hooks/check-mcp-out.sh` — MCP response gate (default on for Cursor/Claude; skipped with `--no-mcp-response-gate`)
- `.offsend/hooks/check-subagent.sh` — subagent gate (default on for Cursor; skipped with `--no-subagent-gate`)
- managed entry in editor config (`_offsend` metadata)

Existing AI wrappers are updated only when they contain a valid Offsend managed marker in the script header. A foreign wrapper is preserved unless `--force` is explicit.

Commit `.offsend/hooks/` and the editor config to share with the team.

| Target | Config file | Default `--hook-policy` | Read / shell / MCP gates |
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

Treat editor hooks as **defense-in-depth**, not a hard perimeter. Prefer this stack:

1. **No plaintext secrets in the workspace** — env vars, a secret manager, or `offsend seal`
2. **AI ignore files** — `offsend protect` / `offsend ignore` (primary hard exclusion from indexing and context)
3. **Prompt + read gates** — friction on known editor paths (`@file`, Read/Edit/Write)
4. **Shell-gate** — friction when the agent runs shell (`cat` / `grep` / `sed` and similar); on by default for Cursor/Claude
5. **Git pre-commit + CI** — catch secrets if they leave via git

### What hooks cover

| Path into agent context | Gate | Notes |
| --- | --- | --- |
| Prompt text / pasted secrets | Prompt gate | Default on install |
| `@file` / file-like mentions in the prompt | Prompt gate | Bounded disk read of the mentioned path |
| Editor Read / Edit / Write tools | Read-gate | Cursor `beforeReadFile`; Claude `PreToolUse` (`Read\|Edit\|Write`) |
| Agent shell (`Bash` / `beforeShellExecution`) | Shell-gate | On by default for Cursor/Claude; returns `ask`, not hard deny |
| MCP tool calls | MCP-gate | On by default for Cursor/Claude; Cursor `beforeMCPExecution` (`failClosed: true`); Claude `PreToolUse` (`mcp__.*`). Policy + path/secret scan on **args**; see `context.mcp` in `.offsend.yml` |
| MCP tool responses | MCP-response-gate | On by default for Cursor/Claude; Claude `PostToolUse` (`mcp__.*`) can **replace** the output — `context.mcp.responses: seal` swaps secrets for `{{…}}` tokens; Cursor `afterMCPExecution` is observe-only (stderr + debug log) |
| Subagent spawn (Cursor Task) | Subagent-gate | On by default for Cursor `subagentStart`; secret-scan of the task prompt (`deny` on findings; no `ask`). Claude subagents are not gated — rely on AI ignore |

### What hooks do not cover

These walk past a path-based file hook by design. Close them with ignore rules and by keeping secrets off disk — not by expecting the read-gate alone to catch them:

| Bypass | Why the hook misses it | What to use instead |
| --- | --- | --- |
| **Shell without shell-gate** | `cat` / `grep` / `sed` read the file outside the Read tool (older installs, or `--no-shell-gate`) | Re-run `offsend hook install --target cursor\|claude` (shell-gate is on by default) |
| **MCP tool responses** | MCP-gate scans call **arguments**. The response gate closes this for Claude (`PostToolUse` can seal/replace output); Cursor `afterMCPExecution` is observe-only — the payload still reaches the agent | `context.mcp.responses: seal` + seal key for Claude; restrict MCP servers (`context.mcp` allow/deny); keep secrets off disk; AI ignore |
| **MCP without mcp-gate** | Older installs, or `--no-mcp-gate` | Re-run `offsend hook install --target cursor\|claude` (mcp-gate is on by default) |
| **Subagents (Claude / ungated Cursor)** | Claude subagents may skip parent hooks; Cursor without `--subagent-gate` does not scan task text | `offsend hook install --target cursor` (subagent-gate on by default); project-level AI ignore; no plaintext secrets on disk |
| **Local agent history already written** | Prior transcripts may already contain secrets | `offsend history audit` / `offsend history scrub --apply` |
| **Symlinks to sensitive targets** | A benign link name (e.g. `notes.txt` → `.env`) used to skip name heuristics | Read-gate and shell-gate (when the path exists) also check the symlink-resolved target |
| **Renamed copies** | A real copy under a new name is not a symlink, so path heuristics may miss it | Content scan on the gated read path may still catch secret-shaped values; ignore patterns + no plaintext remain the real control |
| **Open editor tabs (Cursor)** | Cursor may not always enforce `beforeReadFile` deny | `offsend protect` / `.cursorignore` for hard blocks |
| **Cloud agent sessions** | Remote/cloud agents do not run local editor hooks | Keep secrets out of the repo; CI `check --policy`; rotate if leaked |

`offsend doctor` surfaces residual gaps as `hook-coverage-gaps` when any AI-editor hook is installed (not a sandbox claim). Status is **warn** when MCP/Claude/Cursor-specific gaps apply; **ok** (informational) when only the universal cloud-sessions residual remains.

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

The prompt gate also scans file-like `@mentions` (for example `@index.js`) by reading a bounded prefix from disk, so attaching a secret file in the prompt can be blocked before the model turn starts. That is a **different pipe** from the read-gate: `@file` is checked at prompt submit; Read/Edit/Write are checked when those tools run.

On a secret hit the editor receives deny with a short remediation message (detector type names only — no secret values). Claude PreToolUse uses `hookSpecificOutput.permissionDecision: "deny"` (not the deprecated top-level `decision: "block"`). Hook command timeout defaults to 30s to avoid cold-start fail-open.

Cursor may not always enforce `beforeReadFile` deny (known IDE limitation; open tabs can bypass the hook). Prefer `offsend protect` / `.cursorignore` for hard blocks; treat read-gate as defense-in-depth.

**Seal mode (`context.read.on_secret: seal`)** — instead of a dead-end deny, the gate writes a **sealed copy** (secrets replaced with `{{TYPE:v1.…}}` tokens, temp file with `0600` permissions) and tells the agent its path (`agent_message` for Cursor; part of `permissionDecisionReason` for Claude). The agent keeps working on the sealed copy; plaintext never enters model context; the user restores outputs with `offsend unseal`. Requires a seal key (`offsend keygen --default`) — without one, the gate falls back to a plain deny. Sealed copies are auto-allowed by the read-gate and are clean under `offsend check`. The shell-gate asks for confirmation before the agent itself runs `offsend unseal`. Honest boundary: this keeps plaintext out of transcripts/context but is not a sandbox against a local agent with key access.

### Shell-gate (on by default)

Installed by default for Cursor and Claude (disable with `--no-shell-gate`). Gates agent shell commands (Cursor `beforeShellExecution`, Claude `PreToolUse` matcher `Bash`). Without it, `cat` / `grep` / `sed` on a sensitive file bypass the read-gate entirely.

The command line is tokenized and checked against the same sensitive-path heuristics as the read-gate (`cat .env`, `cp ~/.ssh/id_rsa …`, `--key-file=prod.key`). Findings return **`ask`** — the editor requests user confirmation instead of blocking, which keeps false positives cheap. This is useful friction, not an airtight shell sandbox: no shell grammar parsing, no file contents read, and no hard deny.

`offsend doctor` and `offsend hook status` warn when Cursor/Claude hooks are installed without a shell-gate (common for older installs). Re-run `offsend hook install --target cursor` (or `claude`) to add it.

Note: Cursor currently enforces only `deny` reliably; `ask` may not pause the command in all versions (known IDE limitation).

### MCP-gate (on by default)

Installed by default for Cursor and Claude (disable with `--no-mcp-gate`). Gates MCP tool **calls** (Cursor `beforeMCPExecution` with `failClosed: true`, Claude `PreToolUse` matcher `mcp__.*`):

1. **Server policy** — optional `context.mcp.allow` / `deny` in `.offsend.yml`. A non-empty `allow` list (or `deny: ["*"]`) switches to allowlist mode: servers not matching `allow` are flagged
2. **Sensitive paths in tool args** — same path heuristics as the shell-gate
3. **Secret-shaped values in tool args** — same detectors as the prompt gate (`--secrets-only` by default)

Enforcement mode (`context.mcp.mode`): `observe` (allow + stderr), `ask` (default when unset), or `deny`. `offsend show` lists configured MCP servers; `offsend doctor` warns when MCP is present without a policy or when the gate is missing.

Fail-open vs fail-closed: infrastructure errors (unreadable settings, invalid config) fail **open** so a broken install never blocks the editor. With an explicit `context.mcp.mode: deny` (or `context.subagents.mode: deny` for the subagent gate), unrecognized hook input is **denied** instead — you asked to block, so Offsend fails closed there.

This gate scans **arguments** only; responses are handled by the MCP-response-gate below.

### MCP-response-gate (on by default)

Installed by default for Cursor and Claude (disable with `--no-mcp-response-gate`). Scans MCP tool **responses** for secret-shaped values after the tool runs (Cursor `afterMCPExecution`, Claude `PostToolUse` matcher `mcp__.*`). Mode via `context.mcp.responses`:

| Mode | Claude | Cursor |
| --- | --- | --- |
| `observe` (default) | stderr + debug log | stderr + debug log |
| `warn` | Also warns the agent via `additionalContext` (“do not echo/store/reuse these values”) | Same as observe |
| `seal` | **Replaces the tool output** (`hookSpecificOutput.updatedToolOutput`) with a sealed version — secrets become `{{TYPE:v1.…}}` tokens before the model sees them. Needs a seal key; falls back to `warn` without one or when the response exceeds the ~50k scan budget | Same as observe |

The asymmetry is an editor limitation: Cursor `afterMCPExecution` receives the result but cannot rewrite it, so on Cursor the payload still reaches the agent (findings surface via stderr / debug log; doctor reports the residual gap). The gate is fail-open — a broken hook never blocks the editor.

### Subagent-gate (on by default for Cursor)

Installed by default for Cursor (`subagentStart`, `failClosed: true`). Scans the subagent **task** text for secret-shaped values before spawn. Findings **deny** (Cursor does not support `ask` for this event). Mode via `context.subagents.mode` (`observe` / `deny`; `ask` is treated as deny). Claude Code is not covered — subagents may use a separate hook config.

### Agent history

Local Cursor/Claude transcripts can retain secrets from earlier turns:

```bash
offsend history audit                 # project-scoped Cursor transcripts (+ matching Claude)
offsend history audit --all           # every project under ~/.cursor and ~/.claude
offsend history audit --format json   # machine-readable (no spinner on stdout)
offsend history scrub                 # dry-run redactions
offsend history scrub --apply         # write OFFSEND_REDACTED_<type> placeholders
offsend history scrub --format json
```

| Flag | Description |
| --- | --- |
| `--path DIR` | Project directory used to scope transcripts (default: cwd) |
| `--all` | Every project under `~/.cursor` and `~/.claude` |
| `--format text\|json` | Output format (`json` disables the progress spinner) |
| `--apply` (scrub only) | Write redactions to disk; without it, dry-run |

Exit codes for `history audit`: `0` clean, `1` secret-shaped findings, `2` errors.

**Audit JSON** (`schemaVersion: 1`): `filesScanned`, `filesWithFindings`, `hasFindings`, `findings[]` (`path`, `source`, `secretTypes`, `findingCount`), `errors[]`. Paths are local filesystem paths — keep output on-machine; do not upload to CI logs.

**Scrub JSON** (`schemaVersion: 1`): `dryRun`, `filesTouched[]`, `redactionCount`, `hasFindings`, `findings[]`, `errors[]`.

Example local script gate:

```bash
offsend history audit --format json | jq -e '.hasFindings == false'
```

`offsend show` lists transcript file counts by default; `offsend show --scan-history` (or `context.history.scan_in_show: true`) content-scans them. `offsend doctor` warns when transcripts exist (or when a scan finds secrets) and tips `history audit` / `history scrub` when that is the first next action. Set `context.history.scrub_on_protect: true` to scrub during `offsend protect`.

Scrub limits: files larger than 2 MB are scanned (bounded prefix) but skipped by scrub — redact those manually. Close active agent sessions before `--apply`; files that change mid-scrub are skipped and reported.

### Security notes

- Advice uses **detector type names only** — never secret prefixes/suffixes.
- Notifications: fixed short template (`N sensitive items…`).
- Sealed temp files: mode `0600`, best-effort cleanup after 1 hour; UI messaging is clipboard-only.
- Stdin capped at **2 MiB** (`check`, `seal`, `unseal`).
- Cursor `attachments` paths checked by name/extension (files not opened).
- Project `.offsend.yml` detector disables / dictionaries apply; macOS app settings also affect detection.
- `hook-debug.log` rotates at ~512 KiB; home paths redacted in log fields.
- Hooks are an additional check — not a replacement for permissions, AI ignore files, or keeping secrets out of the workspace. See [What hooks do not cover](#what-hooks-do-not-cover).

### Verify

```bash
offsend doctor
offsend hook status --target all
printf '%s' '{"prompt":"AWS_ACCESS_KEY_ID=<example-access-key-id>"}' \
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

## Typical workflows

### Repository hygiene (ignore-first)

```bash
# new project
offsend doctor
offsend init --template node          # .offsend.yml + first ignore sync + baseline check
offsend protect                       # promote exposed paths to .offsend.yml
offsend sync                          # re-materialize ignore files + install hooks
offsend show                          # verify AI boundary OK

# cloned a repo that already has .offsend.yml
offsend sync                          # materialize AI ignore files + install hooks
```

### AI-editor protection

```bash
offsend protect                       # or: ignore …
offsend sync                          # ignore files + hooks
offsend show
offsend hook status --target all
offsend history audit                 # secrets already in local transcripts
offsend doctor
```

### CI

Fail PRs when secrets appear or the AI ignore boundary drifts from the committed policy:

```yaml
- uses: actions/checkout@v4
- uses: Offsend/ai-hygiene@v1
  with:
    fail-on: block
```

Or install the CLI and run:

```bash
offsend check --staged --policy --fail-on block
```

With `--policy`, `fail-on: block` fails on critical secrets, exposed required paths / missing ignore files, and **managed ignore drift** (local AI ignore files missing patterns from `.offsend.yml`). Fix drift with `offsend sync`; change the shared rules in `.offsend.yml`, not only in one editor’s ignore file.

Team walkthrough: [team.md](team.md).

---

## Related

- [Docs index](README.md)
- [Team setup](team.md)
- [Configuration (`.offsend.yml`)](configuration.md)
- [macOS app](macos-app.md)
- [FAQ](faq.md)
- [README](../README.md) — product overview and quick start
- [`.offsend.yml.example`](../.offsend.yml.example) — annotated starter
