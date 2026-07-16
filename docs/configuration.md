# Configuration

Offsend looks for a project config file named `.offsend.yml` at the repository root. Commit it so the same rules apply locally, in git hooks, and in CI.

Create a starter file:

```bash
offsend init                      # TTY prompts for template; then baseline check
offsend init --template node
offsend init --template js,swift
offsend init --template python --merge-exclude
offsend init --list-templates
offsend init --template node --no-check
# or copy the example:
cp .offsend.yml.example .offsend.yml
```

`offsend init` expands exclude presets into a concrete `check.exclude` list (no `preset` field in the YAML). The `common` preset is always included. Template names are case-insensitive; aliases: `js`/`ts` → `node`, `ios` → `swift`. Without `--template`, a TTY prompts for the stack; non-TTY requires `--template` explicitly. After writing the file, init runs a baseline `check .` unless `--no-check` is set. Use `--merge-exclude` to add patterns to an existing file without overwriting the rest.

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

hooks:
  type: pre-commit
  fail_on: block
  policy: false

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
| `common` (always) | `*.lock`, `.DS_Store`, `Thumbs.db`, `Desktop.ini`, `**/dist/**`, `**/build/**`, `**/coverage/**`, `*.map`, `*.min.js`, `*.min.css`, linter caches (optional commented: `**/.cache/**`, `**/tmp/**`, `**/temp/**`) |
| `node` (aliases: `js`, `ts`) | `**/node_modules/**`, lockfiles (`package-lock.json`, `pnpm-lock.yaml`, …), bundler/Storybook caches, `**/.next/**`, `**/.turbo/**`, … |
| `python` | `**/.venv/**`, `**/__pycache__/**`, `**/*.egg-info/**`, `**/.ipynb_checkpoints/**`, `*.pyc`, … |
| `go` | `**/vendor/**`, `go.sum` |
| `rust` | `**/target/**` |
| `ruby` | `**/vendor/bundle/**`, `**/.bundle/**` |
| `java` | `**/.gradle/**`, `**/out/**`, `**/.idea/**`, `**/target/**`, `*.class`, `*.jar` |
| `android` | `**/.cxx/**`, `**/.externalNativeBuild/**`, `*.apk`, `*.aab`, `*.dex`, `*.class`, `*.jar` |
| `swift` (alias: `ios`) | `**/DerivedData/**`, `**/.build/**`, `Package.resolved`, `**/Pods/**`, `*.ipa`, `**/*.dSYM/**`, … |
| `tuist` | `**/Derived/**`, `**/Tuist/.build/**`, `**/Tuist/Dependencies/**`, `**/.tuist-bin/**` |

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
