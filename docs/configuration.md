# Configuration

Offsend looks for a project config file named `.offsend.yml` at the repository root. Commit it so the same rules apply locally, in git hooks, and in CI — including the AI-context boundary: `ignore.patterns` is the source of truth that `offsend ignore --sync` materializes into `.cursorignore`, `.claudeignore`, and other AI ignore files.

Create a starter file:

```bash
offsend init                      # TTY prompts: stack, ignore.commit, hooks.publish; then sync + baseline check
offsend init --template node --no-ignore-commit --no-hooks-publish
offsend init --template js,swift
offsend init --template python --merge-exclude
offsend init --list-templates
offsend init --template node --no-check --no-sync
# or copy the example:
cp .offsend.yml.example .offsend.yml
```

`offsend init` expands exclude presets into a concrete `check.exclude` list (no `preset` field in the YAML). The `common` preset is always included. Template names are case-insensitive; aliases: `js`/`ts` → `node`, `ios` → `swift`. Without `--template`, a TTY prompts for the stack; non-TTY requires `--template` explicitly.

In a TTY, init also asks whether to keep AI ignore files out of git (`ignore.commit`) and whether AI editor hooks may be committed (`hooks.publish`). Flags (`--ignore-commit` / `--no-ignore-commit`, `--hooks-publish` / `--no-hooks-publish`) skip those prompts. After writing the file, init materializes AI ignore files (unless `--no-sync`) and runs a baseline `check .` (unless `--no-check`). Use `--merge-exclude` to add patterns to an existing file without overwriting `ignore` / `hooks.publish`.

Recommended follow-up: `offsend protect && offsend show && offsend hook install`.

CLI flags override config values when provided explicitly. For example, `offsend check --policy` enables policy checks even if `check.policy` is `false`.

---

## Example

```yaml
version: 1

check:
  fail_on: block
  policy: false
  exclude:
    - "*.lock"
    - ".DS_Store"
    - "Thumbs.db"
    - "Desktop.ini"
    - "**/dist/**"
    - "**/build/**"
    - "**/coverage/**"
    - "*.map"
    - "*.min.js"
    - "*.min.css"
    - ".eslintcache"
    - ".stylelintcache"
    - "**/node_modules/**"
  detectors:
    disable:
      - phone
  dictionaries:
    - kind: project
      value: "Project Apollo"
    - kind: regex
      value: "ACME-\\d{4,}"

ignore:
  commit: false
  # tools: [cursor, claude]   # optional; absent = all supported tools
  patterns: []

hooks:
  type: pre-commit
  fail_on: block
  policy: false
  publish: false

# Optional AI-context controls (MCP policy, etc.)
# context:
#   mcp:
#     mode: ask          # observe | ask | deny
#     allow: [github]    # non-empty allow = allowlist mode
#     high_risk: [filesystem, postgres]
```

A fuller annotated example lives in [`.offsend.yml.example`](../.offsend.yml.example).

---

## Settings reference

### `version`

Config schema version. Use `1`; other versions are rejected.

### `ignore.commit`

When `false` (default), ignore-file sync keeps AI ignore files (`.cursorignore`, `.claudeignore`, …) out of git by writing their paths into a managed block in `.gitignore`. Team rules still live in `ignore.patterns`. Set `true` only if the team wants those files tracked; the next `offsend ignore --sync` then removes the stale offsend entries from `.gitignore`.

### `ignore.tools`

Optional list of tool slugs narrowing which AI tools get managed ignore and rule files. When absent (default), Offsend creates files for every supported tool — you rarely control which editor a teammate opens the repo with, so the default is defense in depth.

Supported slugs: `cursor`, `claude`, `copilot`, `continue`, `windsurf`, `gemini`, `llm`, `aider`, `cline`, `roo`, `zed`, `cody`. Unknown slugs are reported by `offsend doctor` and ignored; if no valid slug remains, all tools are used.

```yaml
ignore:
  tools: [cursor, claude]
```

Files already created for other tools are not deleted — remove them manually if needed.

### `ignore.patterns`

Mandatory AI-ignore patterns for the repository. Source of truth for the managed block in editor ignore files (`.cursorignore`, `.claudeignore`, …).

- `offsend init` seeds this list with the default AI privacy patterns (`.env*`, `*.pem`, credentials files, …)
- `offsend ignore <pattern>` appends here, then runs sync
- `offsend ignore --local <pattern>` writes only to local ignore files (not shared)
- `offsend ignore --sync` materializes the managed block into every known AI ignore file
- User-authored lines outside the managed markers are preserved

### Managed editor privacy rules

`offsend protect` also creates an editor privacy rule per supported editor, rendered from one canonical text in the editor's native format:

- Cursor — `.cursor/rules/offsend_privacy.mdc` (`.mdc` with `alwaysApply: true`)
- Claude Code — `.claude/rules/offsend_privacy.md` (plain markdown, loaded every session)

These `offsend_privacy.*` files are fully owned by Offsend: manual edits are restored on the next `offsend protect` (and reported by `offsend doctor`). Put your own rules in separate files in the same directory — Offsend never touches them. As generated artifacts they follow `ignore.commit`: with `commit: false` (default) their exact paths join the managed `.gitignore` block next to the ignore files — never `.cursor/rules/` or other user-owned directories, so your own rule files remain committable as usual. A legacy `.cursor/rules/privacy.mdc` from older releases keeps satisfying the check and is never overwritten.

### `hooks.publish`

When `false` (default), `offsend hook install` keeps AI editor hook files local (updates `.git/info/exclude`) and warns that they will not be shared. When `true`, wrappers are written without a machine-specific `PREFERRED_BIN` so they are safer to commit.

### `check.fail_on`

Exit policy for `offsend check`:

| Value | Behavior |
| --- | --- |
| `block` | Fail only on blocking findings (critical secrets, failed policy checks) |
| `warn` | Also fail on warning / mask findings |
| `none` | Report findings but always exit successfully |

### `check.policy`

When `true`, `offsend check` also runs workspace policy checks for ignore files and exposed sensitive paths. When `false`, it scans file contents only.

### `check.exclude`

Repository-relative glob patterns skipped by file scanning:

- Plain file globs such as `*.lock` match file names anywhere in the tree
- Path globs such as `build/**` match that directory recursively from the repo root
- Nested globs such as `**/node_modules/**` or `**/*.egg-info/**` match at any depth
- During directory scans, matching directories are skipped entirely (not walked then filtered)

Use `offsend init --template …` to seed a useful exclude list for your stack. Presets expand into concrete patterns at init time (`offsend init --list-templates` prints the catalog):

| Template | Typical excludes |
| --- | --- |
| `common` (always) | `*.lock`, `.DS_Store`, `Thumbs.db`, `Desktop.ini`, `**/dist/**`, `**/build/**`, `**/coverage/**`, `*.map`, `*.min.js`, `*.min.css`, linter caches, `.offsend/hooks/**` (optional commented: `**/.cache/**`, `**/tmp/**`, `**/temp/**`) |
| `node` (aliases: `js`, `ts`) | `**/node_modules/**`, lockfiles (`package-lock.json`, `pnpm-lock.yaml`, …), bundler/Storybook caches, `**/.next/**`, `**/.turbo/**`, … |
| `python` | `**/.venv/**`, `**/__pycache__/**`, `**/*.egg-info/**`, `**/.ipynb_checkpoints/**`, `*.pyc`, … |
| `go` | `**/vendor/**`, `go.sum` |
| `rust` | `**/target/**` |
| `ruby` | `**/vendor/bundle/**`, `**/.bundle/**` |
| `java` | `**/.gradle/**`, `**/out/**`, `**/.idea/**`, `**/target/**`, `*.class`, `*.jar` |
| `android` | `**/.cxx/**`, `**/.externalNativeBuild/**`, `*.apk`, `*.aab`, `*.dex`, `*.class`, `*.jar` |
| `swift` (alias: `ios`) | `**/DerivedData/**`, `**/.build/**`, `Package.resolved`, `**/Info.plist`, `**/Pods/**`, `*.ipa`, `**/*.dSYM/**`, … |
| `tuist` | `**/Derived/**`, `**/Tuist/.build/**`, `**/Tuist/Dependencies/**`, `**/.tuist-bin/**`, `.package.resolved` |

Do not exclude secret-bearing files (for example `.env`, `*.pem`) — those should stay in the scan.
### `check.detectors.disable`

Detector IDs to turn off for this project. Unknown IDs are ignored.

Supported IDs:

`email`, `phone`, `money`, `url`, `ipAddress`, `internalDomain`, `contractId`, `invoiceId`, `orderId`, `apiKeyGeneric`, `openAIAPIKey`, `awsAccessKeyId`, `githubToken`, `slackToken`, `stripeKey`, `jwt`, `privateKey`, `sshPrivateKey`, `databaseURLWithPassword`, `bearerToken`, `highEntropyString`, `creditCardLike`, `iban`, `customClient`, `customCompany`, `customProject`, `customSensitiveTerm`, `customInternalDomain`, `personName`, `streetAddress`, `governmentId`

### `check.dictionaries`

Extra custom-dictionary entries matched alongside the built-in detectors. Each entry has:

| Field | Description |
| --- | --- |
| `kind` | `client`, `company`, `project`, `sensitiveTerm`, `internalDomain`, or `regex` |
| `value` | Match string. Literal (with word boundaries) for every kind except `regex`; for `regex`, used as a regular-expression pattern |

Invalid patterns and unknown kinds are ignored. Entries merge with dictionaries configured in the macOS app.

### AI-editor prompt hooks

Separate from git hooks. See [cli.md — AI editor hooks](cli.md#ai-editor-hooks) (including [what hooks cover / do not cover](cli.md#what-hooks-cover)) and [`offsend hook install --target …`](cli.md#hook-install).

### `hooks.type`

Git hook type to install. Currently supported: `pre-commit`.

### `hooks.fail_on`

Exit policy used by installed hooks. If omitted, falls back to `check.fail_on`, then `block`.

### `hooks.policy`

Whether installed hooks include workspace policy checks. If omitted, falls back to `check.policy`, then `false`. For faster commits that check only staged files, keep this `false`.

### `hooks.publish`

Whether AI editor hook files (`.cursor/hooks.json`, `.offsend/hooks/`, …) are intended to be committed. Default `false`: `offsend hook install` keeps them local via `.git/info/exclude`. When `true`, wrappers omit machine-specific absolute paths so they are safer to share.

### `context.mcp`

Optional MCP policy used by `offsend show`, `offsend doctor`, and the MCP-gate (`offsend hook install` / `check --mcp-gate`):

| Field | Description |
| --- | --- |
| `mode` | `observe` (stderr only), `ask` (confirm), or `deny` (block). Default when unset: `ask` for findings. With explicit `deny`, unrecognized hook input is also denied (fail-closed) |
| `allow` | Server name patterns permitted. A non-empty list switches to allowlist mode: servers not matching are flagged |
| `deny` | Server name patterns to block. `"*"` also enables allowlist mode |
| `high_risk` | Patterns flagged in `show` / `doctor` (defaults include `filesystem`, `postgres`, …) |

### `context.subagents`

| Field | Description |
| --- | --- |
| `mode` | `observe` or `deny` (`ask` is treated as deny on Cursor `subagentStart`) |
| `scan_task` | Secret-scan the subagent task prompt (default `true`) |

### `context.history`

| Field | Description |
| --- | --- |
| `audit` | When `false`, `offsend show` skips the agent-history section (default: audit) |
| `scrub_on_protect` | When `true`, `offsend protect` also runs history scrub (honors `--dry-run`) |

---

## Where settings live

| Surface | Storage |
| --- | --- |
| Project rules | `.offsend.yml` in the repo |
| macOS app | Keychain + Application Support |
| CLI on macOS | Same as the app (Application Support / Keychain) |
| CLI on Linux | Plain JSON under `$XDG_CONFIG_HOME/offsend` (typically `~/.config/offsend`) |

---

## Related

- [Docs index](README.md)
- [CLI reference](cli.md) — all commands and AI-editor hooks
- [FAQ](faq.md)
- [README](../README.md) — quick start and workflows
- [`.offsend.yml.example`](../.offsend.yml.example) — copy-paste starter
