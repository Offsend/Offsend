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

Pin a release with `OFFSEND_VERSION=…`. The install script needs only `curl` plus the standard POSIX tools; it verifies the download against the SHA-256 digest GitHub records for the release asset. It calls the GitHub API twice, so a shared IP can hit the anonymous rate limit — pass a token when that happens:

```bash
GITHUB_TOKEN=<token> bash -c "$(curl -fsSL https://install.offsend.io/cli)"
```

On Linux, config lives under `$XDG_CONFIG_HOME/offsend` (typically `~/.config/offsend`). On macOS CLI, settings use Application Support / Keychain like the app.

The package is `offsend-cli`; the command is `offsend`. The macOS app also ships a bundled helper — see [macOS app](macos-app.md).

---

## Command overview

| Command | Purpose |
| --- | --- |
| [`offsend init`](#offsend-init) | Create `.offsend.yml` (wizard + ignore-file sync + optional baseline check) |
| [`offsend sync`](#offsend-sync) | Apply `.offsend.yml`: ignore files + hooks (+ sandbox configs if enabled) |
| [`offsend edit`](#offsend-edit) | Open `.offsend.yml` in `$EDITOR` |
| [`offsend protect`](#offsend-protect) | Hide exposed sensitive paths from AI (promote to `.offsend.yml` + sync) |
| [`offsend show`](#offsend-show) | List sensitive paths visible to AI tools (no file contents); `--report` for anonymized JSON |
| [`offsend ignore`](#offsend-ignore) | Add patterns to team policy (`.offsend.yml`) or locally (auto-materializes) |
| [`offsend check`](#offsend-check) | Scan files, staged changes, stdin, or editor hook JSON |
| [`offsend hook`](#offsend-hook) | Install / remove / status for git and AI-editor hooks |
| [`offsend policy`](#offsend-policy) | Explicitly trust/status/forget the runtime policy used by editor gates |
| [`offsend history`](#agent-history) | Audit / scrub secrets in local Cursor & Claude transcripts |
| [`offsend seal`](#offsend-seal) | Replace secrets with reversible seal tokens |
| [`offsend unseal`](#offsend-unseal) | Restore plaintext from seal tokens |
| [`offsend keygen`](#offsend-keygen) | Generate a 32-byte seal key |
| [`offsend doctor`](#offsend-doctor) | Verify CLI, git, settings, hooks, seal key, sandbox |

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

`sync` deliberately does **not** trust policy changes: an agent can run project commands and must not be able to approve its own weaker policy. After reviewing `.offsend.yml`, run `offsend policy trust` yourself in an interactive terminal.

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
- With [`sandbox.enabled: true`](configuration.md#sandbox), also writes each editor's sandbox config (`.cursor/sandbox.json`, Claude `sandbox` settings, `.offsend/nono/` profile when nono is on `PATH`) and prints the chosen mechanism. Offsend does not install nono (`brew install nono`). For nono it prints `offsend run …` (or the raw `nono run …`); use [`offsend run`](#offsend-run) to launch. Codex's `~/.codex/config.toml` is reported, not written.

---

## `offsend doctor`

Verify local setup: settings, CLI path, git, project config, Cursor security version, optional AI hooks, seal key.

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

Checks include `cursor-version` on macOS (warn below Cursor 3.0 because of CVE-2026-48124), `ignore-sync` / `rules-drift` (shared `.offsend.yml` vs materialized ignore and privacy rule files), `ai-hook-trust-root` (legacy repo-local executable wrappers), `ai-write-gate` / `ai-artifact-audit` / `ai-shell-gate` / `ai-mcp-gate` / `ai-mcp-response-gate` (warn when Cursor/Claude are installed without those gates), `shell-output-audit` (coverage of the post-hoc output audit, plus commands whose printed secrets still need rotating), `trust-surface-map` (editor/Git/shell startup configs and observe-only venv interpreters), `artifact-provenance` (last 30 days of post-write trust-surface metadata), `privileged-daemons` (common Docker/Podman/containerd/BuildKit endpoints and shell-gate coverage), `environment-invocation-gate` (PATH/loader/Git/interpreter environment coverage, and the fact that file reads are not prevented), `hook-coverage-gaps` (residual limits when AI hooks are installed: MCP responses on Cursor, Claude subagents, Cursor open tabs, cloud sessions), `seal-detector-gap` (seal / MCP-seal with credential detectors listed under `check.detectors.disable`, or `url` disabled under seal), `mcp-inventory` (configured MCP servers + policy), and `next-actions` (ranked hints: shared policy → sync / drift repair → protect → gates → history audit/scrub when transcripts exist → git hook). Legacy `ai-wrapper-*` checks remain during migration. By default `show` / doctor **count** transcript files; enable content scan with `context.history.scan_in_show: true` or `offsend show --scan-history` (then doctor can suggest `history scrub` on real findings). Otherwise run `history audit`. In a TTY, doctor may offer to run the first suggested command. JSON includes `suggestedActions`. See also [FAQ → covers / does not cover](faq.md#what-does-offsend-cover-vs-not-cover).

When a shell-gate is installed, `git-config-invocation-gate` confirms static execution-sensitive Git invocation checks are active and names the remaining dynamic-command attribution gaps.

With [`sandbox.enabled: true`](configuration.md#sandbox), doctor also reports `sandbox-<editor>` (mechanism + reach), `sandbox-coverage` (basename globs that cannot become sandbox paths), `sandbox-nono-pack-*` (registry pack for Claude/Codex), `sandbox-launch` (`offsend run …` / `nono run …` when needed), and `sandbox-policy` (**fail** on drift or hollow configs: Cursor `insecure_none`, Claude `allowUnsandboxedCommands` / `filesystem.disabled`, Codex `danger-full-access`). Same checks run in `offsend check --policy`.

---

## `offsend run`

Launch an AI editor (`cursor`, `claude`, or `codex`) using the sandbox decided by `.offsend.yml`.

```bash
offsend run claude
offsend run claude --sync
offsend run claude -- -p "hello"
offsend run cursor
offsend run codex
```

| Condition | Launch |
| --- | --- |
| `sandbox.enabled` not true | Bare `claude` / `codex`, or `open -a Cursor` |
| `sandbox.enabled` + nono on PATH (Claude/Codex) | `nono run --profile ./.offsend/nono/offsend-<editor>.json --allow-cwd -- <binary>` (requires `nono pull nolabs-ai/claude` or `…/codex`) |
| `sandbox.enabled` without nono (Claude) | Bare `claude` (native sandbox from sync) |
| Cursor | Always `open -a Cursor` (IDE cannot be wrapped by nono) |

`--sync` materializes sandbox config for that editor before launch (nono profile / `.cursor/sandbox.json` / Claude settings). Does **not** run `policy trust` — approve the policy separately with `offsend policy trust`.

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
| `--policy` | Also run workspace policy checks (ignore files, exposed paths, managed ignore drift, git-tracked `ignore.patterns`) |
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
offsend check --adapter claude --write-gate --no-notify  # executable-config write gate
```

| Flag | Default | Description |
| --- | --- | --- |
| `--adapter cursor\|claude\|windsurf\|codex` | — | Hook adapter; implies stdin JSON |
| `--hook-policy advise\|soft-block\|block` | `soft-block` | See [Hook policies](#hook-policies) |
| `--secrets-only` / `--no-secrets-only` | on | Secret-shaped findings only (excludes noisy `highEntropyString`) |
| `--notify` / `--no-notify` | on (Darwin) | macOS notification; **off** in installed editor-hook commands |
| `--seal-copy` | off | Write sealed copy to private temp file + clipboard |
| `--debug-hook` | off | Append diagnostics to `hook-debug.log` (no secret values) |
| `--read-gate` | off | File-read gate for Cursor / Claude: sensitive paths + secret content scan |
| `--write-gate` | off | Fail-closed agent-write gate for executable editor/Git configuration |
| `--artifact-audit` | off | Post-write metadata recorder for executable trust surfaces (installed-hook plumbing) |
| `--shell-gate` | — | Sensitive-path gate for Cursor / Claude shell hooks (`context.shell.mode`; default `deny`) |
| `--shell-audit` | — | Post-hoc audit of shell **output** for Cursor / Claude: log and notify on secrets a command printed. Reports only; cannot block |
| `--mcp-gate` | — | MCP tool-call gate for Cursor / Claude: `context.mcp` policy + path/secret scan in args |
| `--mcp-response-gate` | — | MCP tool-**response** gate: secret-scan the response per `context.mcp.responses` (`observe`/`warn`/`seal`). Cursor and Claude `PostToolUse` can rewrite MCP output in `seal` mode |
| `--subagent-gate` | — | Subagent spawn gate for Cursor: secret-scan task text |
| `--key-file PATH` | — | Seal key file for `--seal-copy` / `--hook-policy block` |
| `--key-name NAME` | — | Named key in `~/.offsend/keys/NAME.key` |

Installed editor hooks invoke the CLI directly: `offsend check --adapter … --hook-policy … --secrets-only --no-notify`.

**Fail-open:** infrastructure errors (bad JSON, settings load, invalid `--hook-policy`) normally allow the prompt through so a broken hook does not block chat. Safety exceptions fail closed: trusted-policy drift blocks all editor gates; oversized read-gate input is denied; oversized MCP responses are withheld; and unrecognized MCP input is denied when `context.mcp.mode` is explicitly `deny`; unrecognized subagent input is denied by default (only `context.subagents.mode: observe` fail-opens). stderr shows short codes (`invalid_json`, `policy_drift`, `stdin_too_large`, …); details go to `--debug-hook` only.

That covers errors Offsend can see. A hook process that crashes or times out never reports anything, so Cursor's own `failClosed` flag decides. Gates that carry hard denials set it — write, shell, MCP, subagent — and a crashed hook blocks the operation. The read-gate and the prompt gate leave it off: they are friction against reading secrets rather than a perimeter, and blocking every file read on a broken hook costs more than it protects.

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

## `offsend policy`

Editor gates read `.offsend.yml` from the workspace, which an agent can edit. Explicitly trust the reviewed policy into a user-local snapshot outside the repository:

```bash
offsend policy trust               # interactive confirmation required
offsend policy status
offsend policy forget              # drop the snapshot; gates fall back to the safe subset
```

`trust` and `forget` cannot run non-interactively, and the shell-gate denies agent attempts to invoke them. Once trusted, any byte-level change, deletion, or parse failure in `.offsend.yml` makes editor hooks fail closed until the user reviews and trusts the new policy. `sync`, `protect`, and `hook install` never refresh this snapshot automatically.

**Without a snapshot** the gates do not fall back to full live policy. They apply only the fields that cannot make a gate more permissive than its built-in default, so a rewritten policy can tighten gates but never loosen them. Ignored until trusted: `check.exclude`, `check.detectors.disable`, `context.mcp.mode` / `rules[].mode` below `ask`, `context.subagents.mode` below `deny`, and `context.subagents.scan_task: false`. Detector dictionaries, MCP allow/deny lists, stricter modes, and `context.read.on_secret: seal` still apply — seal denies the read either way and only changes what the agent gets instead. This is what makes deleting the snapshot pointless as an attack.

The snapshot contains the repository path, SHA-256 policy hash, and trust timestamp; it does not contain policy contents or secrets. It is stored under Offsend's user-local application data directory with `0600` permissions.

---

## `offsend hook`

Manage **git pre-commit** hooks and **AI-editor prompt hooks** (Cursor, Claude Code, Windsurf, Codex).

### `hook install`

**Default (no `--target`): full protection** — git pre-commit hook **plus** AI-editor hooks for detected editors (Cursor and Claude always; Windsurf/Codex when a repo-local or home config directory exists). If the git hook cannot be installed (e.g. a foreign pre-commit hook exists), it is skipped with a warning and the AI hooks still install.

```bash
offsend hook install                  # TTY: confirm plan, then git + detected AI editors
offsend hook install --yes            # skip confirmation
offsend hook install --path /path/to/repo
offsend hook install --force          # also overwrite a foreign git hook
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
offsend hook install --target claude --no-write-gate
offsend hook install --target cursor --no-shell-gate
offsend hook install --target cursor --no-mcp-gate
```

| Flag | Description |
| --- | --- |
| `--target cursor\|claude\|windsurf\|codex\|all` | AI editor target |
| `--hook-policy advise\|soft-block\|block` | Override default policy (`soft-block`) |
| `--read-gate` / `--no-read-gate` | File-read path gates (**Cursor + Claude only**). **On by default**; `--no-read-gate` disables |
| `--write-gate` / `--no-write-gate` | Semantic pre-write gate for executable workspace configuration (**Cursor + Claude only**). **On by default**; deny is fail-closed |
| `--shell-gate` / `--no-shell-gate` | Shell-command gate (**Cursor + Claude only**). **On by default**; sensitive-path / ask-class findings follow `context.shell.mode` (default **deny**); control-plane findings always deny. Cursor `beforeShellExecution` with `failClosed: true`. `--no-shell-gate` disables |
| `--shell-audit` / `--no-shell-audit` | Shell-**output** audit (**Cursor + Claude only**). **On by default**; Cursor `afterShellExecution`, Claude `PostToolUse` matcher `Bash`. Never fail-closed: it reports on a command that already ran and cannot block. `--no-shell-audit` disables |
| `--mcp-gate` / `--no-mcp-gate` | MCP tool-call gate (**Cursor + Claude only**). **On by default**; Cursor `beforeMCPExecution` with `failClosed: true`. `--no-mcp-gate` disables |
| `--mcp-response-gate` / `--no-mcp-response-gate` | MCP tool-**response** gate (**Cursor + Claude only**). **On by default**; Cursor `postToolUse` matcher `MCP:.*`, Claude `PostToolUse` matcher `mcp__.*`; both can rewrite output in `seal` mode. `--no-mcp-response-gate` disables |
| `--subagent-gate` / `--no-subagent-gate` | Subagent spawn gate (**Cursor only**). **On by default**; `subagentStart` with `failClosed: true`. `--no-subagent-gate` disables |
| `--cli-path PATH` | CLI executable referenced by local editor-hook commands |
| `--force` | Overwrite a foreign git hook; managed editor entries refresh automatically |

Gate flags also accept `--with-read-gate` / `--with-write-gate` / `--with-shell-gate` / `--with-shell-audit` / `--with-mcp-gate` / `--with-mcp-response-gate` / `--with-subagent-gate` as aliases.

Install **merges** into existing editor configs and does not remove foreign hooks. Managed entries invoke the installed Offsend CLI directly, so agent-writable repo-local shell wrappers are not part of the execution path. Local configs prefer the install-time CLI path and safely fall back to `offsend` from `PATH` after package-manager moves; published configs use `PATH` directly.

Re-running install or `offsend sync` replaces legacy `.offsend/hooks/*.sh` references and removes unused managed wrappers. Foreign files under `.offsend/hooks/` are never overwritten or deleted.

With `hooks.publish: true`, commit the editor config to share it with the team. Do not commit legacy `.offsend/hooks/`; every teammate needs the Offsend CLI on `PATH`.

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
- Single AI target: exits `3` if not installed or **broken** (for example, a referenced legacy wrapper is missing, tampered, or outdated).
- `--target all`: shows all four editors; exits `3` only if any target is **broken** (not installed is OK).

---

## AI editor hooks

Offsend checks prompts **before** they reach Cursor, Claude Code, Windsurf, or Codex. Editors cannot rewrite prompt text via hooks — Offsend **advises** or **soft-blocks** and recommends moving secrets to env / ignore files.

Treat editor hooks as **defense-in-depth**, not a hard perimeter. Prefer this stack:

1. **No plaintext secrets in the workspace** — env vars, a secret manager, or `offsend seal`
2. **AI ignore files** — `offsend protect` / `offsend ignore` (primary hard exclusion from indexing and context)
3. **Prompt + read/write gates** — friction on known editor paths (`@file`, Read, Edit/Write)
4. **Shell-gate** — friction when the agent runs shell (`cat` / `grep` / `sed` and similar); on by default for Cursor/Claude
5. **Git pre-commit + CI** — catch secrets if they leave via git

### What hooks cover

| Path into agent context | Gate | Notes |
| --- | --- | --- |
| Prompt text / pasted secrets | Prompt gate | Default on install |
| `@file` / file-like mentions in the prompt | Prompt gate | Bounded disk read of the mentioned path |
| Editor Read tools | Read-gate | Cursor `beforeReadFile`; Claude `PreToolUse` (`Read`) |
| Editor Edit / Write tools targeting executable configuration | Write-gate | Cursor `preToolUse` (`Write\|Edit`); Claude `PreToolUse` (`Edit\|Write`) |
| Agent shell (`Bash` / `beforeShellExecution`) | Shell-gate | On by default for Cursor/Claude; sensitive paths, safe PATH/HOME overrides, and lower-risk daemon mutations follow `context.shell.mode` (default **deny**); control-plane, environment injection, container execution, and direct privileged-socket operations hard-deny. Invalid / oversized hook input fails closed |
| Agent shell **output** (`afterShellExecution` / `PostToolUse Bash`) | Shell-output audit | On by default for Cursor/Claude. Reports only: neither editor accepts a replacement for terminal output, so secrets a command printed are logged and notified for rotation, not withheld |
| MCP tool calls | MCP-gate | On by default for Cursor/Claude; Cursor `beforeMCPExecution` (`failClosed: true`); Claude `PreToolUse` (`mcp__.*`). Policy + path/secret scan on **args**; see `context.mcp` in `.offsend.yml` |
| MCP tool responses | MCP-response-gate | On by default for Cursor/Claude; `PostToolUse` can **replace** the output — `context.mcp.responses: seal` swaps secrets for `{{…}}` tokens before model consumption |
| Subagent spawn (Cursor Task) | Subagent-gate | On by default for Cursor `subagentStart` + `preToolUse` (`Task`); secret-scan of the task prompt (`deny` on findings; no `ask`). Claude subagents are not gated — rely on AI ignore |
| Editor Grep (Cursor) | Grep-gate | On by default with read-gate; seal mode denies Grep (no rewrite API); otherwise single-file content deny |

### What hooks do not cover

These walk past a path-based file hook by design. Close them with ignore rules and by keeping secrets off disk — not by expecting the read-gate alone to catch them:

| Bypass | Why the hook misses it | What to use instead |
| --- | --- | --- |
| **Shell without shell-gate** | `cat` / `grep` / `sed` read the file outside the Read tool (older installs, or `--no-shell-gate`) | Re-run `offsend hook install --target cursor\|claude` (shell-gate is on by default) |
| **Shell reads that name no path** | `find … -exec cat`, a recursive `grep`, or any interpreter one-liner that walks the tree. The hook sees only command text — [stated non-goal](#what-the-shell-gate-does-not-do), asserted ALLOW in CI | [`sandbox.enabled: true`](configuration.md#sandbox) (egress denial), or Cursor's shell allowlist. Shell-output audit tells you what to rotate afterwards |
| **Indirect executable-config mutation** | Dynamic commands, generated scripts, MCP tools, or custom binaries may not expose the final path or invocation as static shell arguments | The shell-gate hard-denies recognized execution-sensitive `git config`, `git -c`, and `--config-env` calls. Dynamic Git and daemon clients remain residual gaps |
| **Privileged daemon through an indirect client** | MCP tools, generated scripts, custom binaries, remote contexts, or dynamically built endpoints can hide Docker/Podman/containerd access | Shell-gate denies recognized container execution and direct socket clients; remove unnecessary socket access and require manual review for daemon operations |
| **Environment poisoning outside static shell argv** | Process APIs, command substitution, generated scripts, parent-process state, or custom launchers can hide PATH/loader/helper overrides | Shell-gate denies recognized execution-sensitive assignments; write-gate protects common shell/direnv startup files; start agents from a clean environment |
| **MCP responses without active sealing** | `observe`/`warn` or an older install does not replace plaintext output; `seal` without a key safely withholds secret-bearing responses instead of passing them through | Set `context.mcp.responses: seal`, generate a seal key, and re-run hook install for Cursor/Claude |
| **MCP without mcp-gate** | Older installs, or `--no-mcp-gate` | Re-run `offsend hook install --target cursor\|claude` (mcp-gate is on by default) |
| **Subagents (Claude / ungated Cursor)** | Claude subagents may skip parent hooks; Cursor without `--subagent-gate` does not scan task text | `offsend hook install --target cursor` installs `subagentStart` + `preToolUse` (`Task`); project-level AI ignore; no plaintext secrets on disk |
| **Grep/search (Cursor)** | Cursor `postToolUse` can replace **MCP** output only — Grep match bodies cannot be sealed | With `context.read.on_secret: seal`, `--grep-gate` denies Grep and points the agent at Read. Without seal, single-file Grep with secrets is denied; workspace Grep remains a residual |
| **Local agent history already written** | Prior transcripts may already contain secrets | `offsend history audit` / `offsend history scrub --apply` |
| **Symlinks to sensitive targets** | A benign link name (e.g. `notes.txt` → `.env`) used to skip name heuristics | Read-gate and shell-gate (when the path exists) also check the symlink-resolved target |
| **Renamed copies** | A real copy under a new name is not a symlink, so path heuristics may miss it | Content scan on the gated read path may still catch secret-shaped values; ignore patterns + no plaintext remain the real control |
| **Open editor tabs (Cursor)** | Cursor may not always enforce `beforeReadFile` deny | `offsend protect` / `.cursorignore` for hard blocks |
| **Cloud agent sessions** | Remote/cloud agents do not run local editor hooks | Keep secrets out of the repo; CI `check --policy`; rotate if leaked |

`offsend doctor` surfaces residual gaps as `hook-coverage-gaps` when any AI-editor hook is installed (not a sandbox claim). An installed MCP response hook counts as protecting only when it uses a replacement-capable event, its CLI runtime is healthy, `context.mcp.responses: seal` is configured, and the default seal key exists. Status is **warn** when MCP/Claude/Cursor-specific gaps apply; **ok** (informational) when only the universal cloud-sessions residual remains.

### Hook policies

| Policy | Behavior |
| --- | --- |
| `advise` | Prompt proceeds. Claude/Codex show `systemMessage`; Cursor relies on hook stderr / optional notification |
| `soft-block` | **Default for all editors.** Block once with remediation text; clean prompts pass through |
| `block` | Same UI block as `soft-block`, plus seal-copy to clipboard when a seal key is available |

`block` without a key still blocks in the editor; stderr hints `offsend keygen --default`.

### Read-gate (on by default)

The read gate protects Cursor `beforeReadFile` and Claude `PreToolUse` (`Read`); it is installed by default for these targets (disable with `--no-read-gate`). It:

1. **Denies sensitive paths** — `.env`, `*.pem`, credentials-like names, and files under `.ssh`, `.aws`, `.kube`, `.docker`, `.gnupg`, `.azure`, `.fly`, …
2. **Scans complete file content for secrets** — uses the same secret detectors as the prompt gate (`--secrets-only` by default). Cursor supplies `content` in the hook JSON; Claude’s PreToolUse has no body, so Offsend reads the file from disk up to the 2 MiB safety limit. Larger files — and hook payloads over the 2 MiB stdin limit — are denied rather than partially scanned (fail-closed). Known limitation, accepted by design: binary (NUL-containing) and non-UTF-8 files under 2 MiB skip the content step — path rules still apply, but no secret scan runs on them.
3. **Claude Edit/Write** — same gate runs before edits so a model that already saw a secret cannot “proceed with the fix” via `Edit` after a later `Read` deny.

The prompt gate also scans file-like `@mentions` (for example `@index.js`) by reading a bounded prefix from disk, so attaching a secret file in the prompt can be blocked before the model turn starts. That is a **different pipe** from the read-gate: `@file` is checked at prompt submit and Read is checked when the tool runs.

### Semantic write gate

Installed by default for Cursor and Claude (disable with `--no-write-gate`). It denies agent Edit/Write operations targeting editor hook configs, `.vscode/tasks.json` / `launch.json`, anything inside a Git directory (config, hooks, `.git` pointers — at any depth, including nested repos and submodules), global Git config (`~/.gitconfig`, `~/.config/git/config`), common shell/direnv startup files (`.zshrc`, `.bashrc`, `.profile`, `.envrc`, Fish/direnv configs), SSH directories, launch agents/daemons, Python startup hooks (`*.pth` in `site-packages`, `sitecustomize.py`), and Offsend's own `.offsend.yml` and trust snapshots. These files are host execution trust surfaces, so unlike ordinary shell secret findings the decision is a hard deny; edit them manually outside the agent session.

Rules match on path shape rather than fixed repository-relative strings, so a config in a subdirectory or in `$HOME` is covered, and case or Unicode-form variants of the same file classify the same way.

Because this runs on every gated tool call, the Git directory behind a worktree or submodule is resolved by reading `.git` and its `commondir` instead of spawning `git rev-parse` — one subprocess costs more than the rest of the gate combined. A custom `core.hooksPath` is honored when the repository config sets it; a value that exists only in global or system config is not visible on this path, though `.git` itself stays denied either way.

`.vscode/settings.json` and `*.code-workspace` mix ordinary preferences with execution: they are denied only when the write introduces or changes an execution-sensitive key (interpreter/tool paths, terminal profiles, task commands), and asked for confirmation when the content cannot be inspected. An edit that swaps a value in place carries neither the key nor the surrounding file, so the gate reads the settings file to see which setting the replaced text belongs to; when that file cannot be read, only the payload is judged. `python*` / `activate*` under a `bin/` directory and `pyvenv.cfg` are observe-only and not blocked. `offsend doctor` reports missing coverage as `ai-write-gate` and summarizes discovered locations as `trust-surface-map`.

Matchers follow each editor's documented semantics. Claude treats a matcher of plain names as an **exact** list, so `Edit|Write` would not fire for `MultiEdit` or `NotebookEdit`; the installed matcher is `Edit|MultiEdit|NotebookEdit|Write`. Cursor's tool set is `Shell`, `Read`, `Write`, `Grep`, `Delete`, `Task`; Offsend installs separate `preToolUse` matchers for `Write|Edit|Delete` (write-gate), `Task` (subagent-gate), and `Grep` (grep-gate). Deleting a hook config or Git file disables protection as effectively as rewriting it.

Cursor does not publish a `tool_input` schema for its file tools. Rather than depend on a key name, the gate reads the documented keys first and otherwise classifies every path-shaped value in the payload, so an unfamiliar or renamed field cannot turn the gate into a no-op. When a call names several files, the strictest outcome applies. Edit lists (`edits: [{old_string, new_string}]`, used by Claude `MultiEdit` and Cursor `afterFileEdit`) contribute their replacement text to content inspection.

Unrecognized pre-write payloads — an editor schema change, or input above the size limit — return `ask`. Cursor accepts `ask` in the `preToolUse` schema but does not enforce it, so on Cursor those decisions render as `deny`; leaving them as `ask` would silently allow the write. An **empty** payload gets its own message, because Cursor delivers empty stdin to `preToolUse` in remote workspaces; if you hit that, update Cursor or re-install with `--no-write-gate`.

Supported installs also add a best-effort post-write provenance hook (Cursor `afterFileEdit`, Claude `PostToolUse` matcher `Edit|Write`). It records only timestamp, repository identifier, relative path, path/content hashes, artifact category, editor, tool, and outcome in a user-local `0600` JSONL ledger; file contents and absolute repository paths are never stored. Each entry carries the SHA-256 of the line before it, so deleting or rewriting history breaks the chain and `doctor` reports it instead of silently showing a shortened list. Cutting the log at either end leaves the surviving lines chained to one another, so the log's length and tail hash are also kept in a companion `0600` anchor file and checked against it. Both files are local, not externally anchored: this catches selective edits, not a rewrite of the log and the anchor together. The ledger rotates at 512 KiB, and `doctor` summarizes the last 30 days. An entry for a surface the write-gate denies means the write reached disk despite or outside pre-write enforcement and should be reviewed. Post-write attribution does not observe shell commands or external processes.

On a secret hit the editor receives deny with a short remediation message (detector type names only — no secret values). Claude PreToolUse uses `hookSpecificOutput.permissionDecision: "deny"` (not the deprecated top-level `decision: "block"`). Hook command timeout defaults to 30s to avoid cold-start fail-open.

Cursor may not always enforce `beforeReadFile` deny (known IDE limitation; open tabs can bypass the hook). Prefer `offsend protect` / `.cursorignore` for hard blocks; treat read-gate as defense-in-depth.

**Seal mode (`context.read.on_secret: seal`)** — instead of a dead-end deny, the gate writes a **sealed copy** (findings replaced with `{{TYPE:v1.…}}` tokens, temp file with `0600` permissions) and tells the agent its path (`agent_message` for Cursor; part of `permissionDecisionReason` for Claude). The agent keeps working on the sealed copy; plaintext never enters model context; the user restores outputs with `offsend unseal`. Requires a seal key (`offsend keygen --default`) — without one, the gate falls back to a plain deny. Each token uses a fresh random AES-GCM nonce; existing `v1` tokens remain readable. Sealed copies are created without following symlinks and are content-scanned like every other file; directory membership alone is never trusted. The shell-gate blocks (default) or asks (`context.shell.mode: ask`) before the agent itself runs `offsend unseal`. Agent-facing seal/MCP-seal scans ignore `check.detectors.disable`, so concrete detector and custom-dictionary findings cannot remain plaintext; fuzzy `highEntropyString` stays excluded. `offsend doctor` reports the difference as `seal-detector-gap`; ordinary `offsend check` still honors the disable list. Honest boundary: this keeps plaintext out of transcripts/context but is not a sandbox against a local agent with key access. Unrecognized read-gate hook JSON is denied (fail-closed). Renamed copies without detectable content, open editor tabs, and cloud agent sessions remain residual gaps — keep secrets off disk as the primary control.

### Shell-gate (on by default)

Installed by default for Cursor and Claude (disable with `--no-shell-gate`). Gates agent shell commands (Cursor `beforeShellExecution`, Claude `PreToolUse` matcher `Bash`). Without it, `cat` / `grep` / `sed` on a sensitive file bypass the read-gate entirely.

There are exactly two kinds of findings, and knowing which is which tells you whether `mode` applies:

1. **Control-plane mutation → always denied**, regardless of `mode`. These are the surfaces that decide what runs next: trusted-policy approval and `offsend unseal`, direct executable-config paths, static execution-sensitive Git settings (`core.hooksPath`, `alias.*`, credential/diff/merge/filter helpers, `difftool.*.cmd` / `mergetool.*.cmd`, `diff.*.textconv`, `init.templateDir`, `protocol.*.allow`, editors/pagers, includes, `git -c` / `--config-env`), privileged daemons, and execution-sensitive environment overrides. The list is closed by what the host trusts, not by what an attacker might try next.
2. **A named sensitive path → `context.shell.mode`**, default **`deny`**. Same path heuristics as the read-gate (`cat .env`, `cp ~/.ssh/id_rsa …`, `--key-file=prod.key`), plus paths matching committed `ignore.patterns`, including protected directories such as `fixtures/`.

Ordinary Git settings and read-only `git config --get` remain allowed. Unrecognized or oversized shell-gate hook input is denied (fail-closed). When one command trips several checks, all findings are reported together rather than one per attempt.

With [`sandbox.enabled: true`](configuration.md#sandbox) there is one more finding of the second kind: a command the editor itself reports as running **outside** a sandbox follows `mode`. Cursor states this per command, and commands needing access outside the workspace run unsandboxed — so a policy that asks for a sandbox is not silently downgraded when the run mode does not provide one. When the editor reports nothing, the gate stays silent: unknown is not the same as unsandboxed.

Every check shares one lexer and one command extractor, so the wrapped forms of a command are recognized like the direct one: quoting (`cat '.git'/config`), redirection (`printf x >.envrc`), launchers (`env`, `sudo`, `timeout`, `nice`, `xargs`, `stdbuf`, `nohup`, `setsid`), inline shell scripts (`bash -c '…'`, `bash -lc '…'`, `env -S '…'`), interpreter payloads (`python3 -c '…'`, `node -e '…'`, `ruby -e '…'`), heredoc bodies (`python3 <<'PY' … PY`), and `$(…)` command-substitution bodies. Adjacent static string concatenations inside interpreter payloads (`Path("c"+"ert"+".pem")`) are joined before the path sweep; ordinary quoted data is not rewritten. Nested scripts are followed a few levels deep and then treated as opaque. Text merely passed as data (`printf '%s' "git config …"`) is not treated as an invocation. All of this serves one purpose: widening where a **path name** can be spotted. None of it judges behavior.

#### What the shell-gate does not do

The hook sees the text of a command and nothing else. What that command will read is undecidable from its text, so the gate does not attempt it:

- **Reading files by enumeration is not prevented.** `find . -type f -exec cat {} +`, `grep -rn 'sk-' .`, `tar cf - . | base64`, and any interpreter one-liner that walks the tree are **allowed** — none of them names a sensitive path. `Scripts/ci_cli_e2e.sh` asserts that they stay allowed, so re-adding a blocklist of filesystem API names breaks CI on purpose: such a list grows with attacker ingenuity and gives a false sense of a closed door while producing false positives on `json.load(open(…))`.
- **Command output cannot be redacted.** Cursor's `afterShellExecution` and Claude's `PostToolUse` receive terminal output but accept no replacement for it. Secrets a command prints are recorded for rotation by the [shell-output audit](#shell-output-audit-on-by-default); they are not withheld from the agent.
- **Dynamic construction hides the operation.** `eval`, unresolved `$var`, encoded payloads, MCP tools, custom binaries, and environment-array injection are outside static argv recognition. `offsend doctor` reports this boundary as `git-config-invocation-gate` and `environment-invocation-gate`.

If you need reading or exfiltration actually prevented rather than reported, use [`sandbox.enabled: true`](configuration.md#sandbox) (kernel egress denial) or Cursor's own shell command allowlist. Encoded exfil that comes back through a file is still handled on the **read-gate** content path: contiguous and commonly wrapped blobs are decoded and re-scanned before deny/seal, with candidate-count and decoded-byte budgets that fail closed on overflow.

The same gate recognizes Docker, Podman, nerdctl, containerd (`ctr`), BuildKit (`buildctl`), and the VM managers behind Docker on macOS (Colima, Lima, OrbStack) — `colima ssh`, `limactl shell`, and `orb run` are denied because those VMs mount the host home directory. Container launch/attach operations (`run`, `create`, `exec`, `start`, Compose `up`, etc.), elevated flags/plugins, direct known socket access, and explicit daemon endpoints are hard-denied because execution happens outside the agent sandbox. Builds and lower-risk daemon mutations return `ask`; diagnostics such as `docker ps`, `version`, and `inspect` are allowed. `doctor` reports common local endpoints as `privileged-daemons`. Dynamic clients and remote contexts that are not visible in static argv remain outside coverage.

Execution-sensitive environment overrides are classified before command-specific checks. Workspace/relative/temporary `PATH`, all `DYLD_*` / `LD_*`, exported shell functions (`BASH_FUNC_*`), executable Git variables (`GIT_SSH_COMMAND`, `GIT_EXEC_PATH`, `GIT_CONFIG_*`, etc.), and startup injection variables (`BASH_ENV`, `ZDOTDIR`, `NODE_OPTIONS`, `PYTHONPATH`, `RUBYLIB`, `PERL5LIB`, `CLASSPATH`, and similar) hard-deny. Variables that name a helper program (`EDITOR`, `VISUAL`, `PAGER`, `MANPAGER`, `SHELL`, `LESSOPEN`) are judged by value: `EDITOR=vim` returns `ask`, while `EDITOR='sh -c payload'` or a program under a workspace-writable path is denied. System-only `PATH` and non-workspace `HOME`/`XDG_CONFIG_HOME` changes return `ask`; safe Git metadata such as `GIT_AUTHOR_NAME` remains allowed. This only covers static assignments, `env`, `export`, `setenv`, and `launchctl setenv` visible in the hook command.

`offsend doctor` and `offsend hook status` warn when Cursor/Claude hooks are installed without a shell-gate (common for older installs). Re-run `offsend hook install --target cursor` (or `claude`) to add it.

Note on `ask`: Cursor accepts `permission: "ask"` from `beforeShellExecution` but does not act on it — the command runs and the reason is shown as a warning after the fact. Claude does pause. That asymmetry is why `context.shell.mode` defaults to `deny`; on Cursor, choosing `ask` means choosing allow-and-warn.

### Shell-output audit (on by default)

Installed by default for Cursor and Claude (disable with `--no-shell-audit`). Runs the secret detectors over what a shell command printed (Cursor `afterShellExecution`, Claude `PostToolUse` matcher `Bash`), records findings in a user-local `0600` log (`shell-output-audit.log`), and notifies you.

This is **a rotation signal and an audit trail, not prevention.** It runs after the command, and neither editor lets a shell hook rewrite terminal output, so by the time it fires the value is already in the agent's context. The only honest promise is that you learn which credential to rotate. The hook always exits 0 and never returns a permission decision, so a finding cannot be mistaken for a block or for a broken hook.

The log records the timestamp, the command, the detector type names, and whether the editor reported the command as sandboxed. Secret **values** are never written — including when the secret is in the command itself (`curl -H "Authorization: …"`), which is redacted to `OFFSEND_REDACTED_<type>` before the line is appended. Output beyond 256 KiB is not scanned, and the notification says so. The log rotates at 256 KiB, and `doctor` reports coverage plus commands still awaiting rotation as `shell-output-audit`.

### MCP-gate (on by default)

Installed by default for Cursor and Claude (disable with `--no-mcp-gate`). Gates MCP tool **calls** (Cursor `beforeMCPExecution` with `failClosed: true`, Claude `PreToolUse` matcher `mcp__.*`):

1. **Server policy** — optional `context.mcp.allow` / `deny` in `.offsend.yml`. A non-empty `allow` list (or `deny: ["*"]`) switches to allowlist mode: servers not matching `allow` are flagged
2. **Per-tool rules** — optional `context.mcp.rules` overrides `mode` / `responses` for matching `server`/`tool` globs, and optional `fields` (`seal`/`drop`/`pass` on JSON paths) when sealing responses. Mode/responses: most specific match wins; fields from all matches merge (more specific wins per path). `offsend show` lists rules + recent MCP findings from a local activity log (server/tool/outcome only); `doctor` warns on high-risk servers without rules. Recipe: [configuration.md → MCP rules recipe](configuration.md#mcp-rules-recipe)
3. **Sensitive paths in tool args** — same path heuristics as the shell-gate
4. **Secret-shaped values in tool args** — same detectors as the prompt gate (`--secrets-only` by default)

Enforcement mode (`context.mcp.mode`): `observe` (allow + stderr), `ask` (default when unset), or `deny`. `offsend show` lists configured MCP servers; `offsend doctor` warns when MCP is present without a policy or when the gate is missing.

Fail-open vs fail-closed: infrastructure errors (unreadable settings, invalid config) fail **open** so a broken install never blocks the editor. With an explicit `context.mcp.mode: deny`, unrecognized MCP hook input — including payloads over the 2 MiB stdin limit — is **denied**. The subagent-gate fails closed on unrecognized / oversized input by default; only `context.subagents.mode: observe` fail-opens there.

This gate scans **arguments** only; responses are handled by the MCP-response-gate below.

### MCP-response-gate (on by default)

Installed by default for Cursor and Claude (disable with `--no-mcp-response-gate`). Scans MCP tool **responses** after execution using Cursor `postToolUse` (`MCP:.*`) or Claude `PostToolUse` (`mcp__.*`). Mode via `context.mcp.responses`:

| Mode | Claude | Cursor |
| --- | --- | --- |
| `observe` (default) | stderr + debug log | stderr + debug log |
| `warn` | Also warns the agent via `additionalContext` (“do not echo/store/reuse these values”) | Warns via `additional_context` |
| `seal` | Replaces `updatedToolOutput` with the sealed output as a **string** (the documented field type; only detected values become tokens) | Replaces `updated_mcp_tool_output` with a sealed version, preserving the JSON object shape |

Responses are scanned in full up to the 2 MiB hook-input limit. Larger responses are replaced with a safe withholding message instead of being partially scanned or passed through. In `seal` mode a response whose secrets **fail to seal** (for example a single value over the plaintext size cap), or cannot be sealed because no key is available, is withheld the same way — never downgraded to a warning. Generate the key with `offsend keygen --default`.

Cursor caveat: `warn` relies on `additional_context`, which Cursor builds before 3.9.8 did not deliver to the model — on those builds `warn` is effectively `observe`. For real protection on Cursor use `responses: seal` with a seal key; `offsend doctor` warns about this combination.

### Subagent-gate (on by default for Cursor)

Installed by default for Cursor (`subagentStart` and `preToolUse` matcher `Task`, both `failClosed: true`). Scans the subagent **task** text for secret-shaped values before spawn (top-level `task` / `prompt` / `description`, or nested `tool_input`). Findings **deny** (Cursor does not support `ask` for this event). Unrecognized / oversized input fails closed unless `context.subagents.mode` is `observe`. Mode via `context.subagents.mode` (`observe` / `deny`; `ask` is treated as deny). Claude Code is not covered — subagents may use a separate hook config.

### Grep-gate (on by default for Cursor with read-gate)

Installed with the read-gate for Cursor (`preToolUse` matcher `Grep`, `failClosed: true`). Cursor cannot seal Grep results (`updated_mcp_tool_output` is MCP-only), so under `context.read.on_secret: seal` the gate **denies Grep** and tells the agent to use Read (which seals). Without seal, a Grep that targets a single file still content-scans and denies on secret hits; workspace-wide Grep without a file path remains a residual (see [What hooks do not cover](#what-hooks-do-not-cover)).

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
- Sealed temp files: private `0700` directory, exclusive no-symlink creation with mode `0600`, best-effort cleanup after 1 hour; UI messaging is clipboard-only.
- Stdin capped at **2 MiB** (`check`, `seal`, `unseal`).
- Cursor `attachments` paths checked by name/extension (files not opened).
- Project `.offsend.yml` detector disables / dictionaries apply; macOS app settings also affect detection.
- `hook-debug.log` uses mode `0600`, refuses symlink targets, rotates at ~512 KiB, and redacts home paths in log fields.
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

With `--policy`, `fail-on: block` fails on critical secrets, exposed required paths / missing ignore files, **managed ignore drift** (local AI ignore files missing patterns from `.offsend.yml`), and **git-tracked paths covered by `ignore.patterns`** (secrets on the default branch remain fetchable even when local AI gates deny them). Fix drift with `offsend sync`; remove tracked secrets with `git rm --cached <path>` and keep them out of the default branch; change the shared rules in `.offsend.yml`, not only in one editor’s ignore file.

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
- [`.offsend.yml.full`](../.offsend.yml.full) — full parameter catalog
