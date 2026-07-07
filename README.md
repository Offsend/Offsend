<h1 align="center"><code>*}• Offsend</code></h1>

<p align="center">
  Prepare code, files, clipboard text, and git changes before you share them with AI tools.<br>
  Local-first privacy checks for ChatGPT, Claude, Cursor, Copilot, and CI.
</p>

<p align="center">
  <a href="https://github.com/Offsend/Offsend/actions/workflows/ci.yml"><img src="https://github.com/Offsend/Offsend/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Offsend/Offsend/releases"><img src="https://img.shields.io/github/v/release/Offsend/Offsend?label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/platform-macOS%2013%2B-000000?logo=apple&logoColor=white" alt="Platform"></a>
  <img src="https://img.shields.io/badge/Linux-CLI%20(x86_64%20%7C%20arm64)-FCC624?logo=linux&logoColor=black" alt="Linux CLI">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/local--first-yes-2ea44f" alt="Local-first">
  <a href="https://radar.offsend.io/participants/"><img src="https://radar.offsend.io/badge.svg" alt="AI Context Reviewed" height="20"></a>
</p>

<p align="center">
  <img src="assets/demo.gif" alt="Drop a file or folder into Prepare for AI">
</p>

---

Offsend is a local-first macOS app for developers who share code with AI tools.

It helps you catch secrets, client data, internal paths, and other sensitive details before they leave your Mac. Use it from the menu bar while you work, from the included CLI in a terminal, or from git hooks before every commit.

> No cloud account. No server-side scanning. No “trust us” privacy model.

## Why Offsend

AI coding tools are useful, but they make it easy to paste the wrong thing: an API key in a diff, a customer name in a document, a private endpoint in a config file, or a token from your clipboard.

Offsend adds a local review step without changing your workflow:

- **Safe Paste** scans clipboard text, masks sensitive values, and pastes the prepared version.
- **Prepare** lets you drop files or folders, review findings, and copy or save an AI-ready result.
- **Project checks** inspect ignore rules and sensitive paths before a repository is used with AI tools.
- **Git hooks** run Offsend before commits, with hook setup and status managed from the macOS GUI.
- **CLI checks are free** and scriptable for terminals, hooks, and CI.

---

## What You Can Do

### 1. Prepare a project

Check whether a folder is ready for AI coding tools: ignore files, sensitive paths, one-click fixes.

Works with `.cursorignore`, `.copilotignore`, `.claudeignore`, `.aiexclude`, and similar rules. Can watch folders in the background and notify you when something changes.

Directory checks use paths and ignore rules only — not file contents.

### 2. Prepare files

Drop a file in **Prepare**, review findings, mask or redact sensitive items, then copy or save an AI-ready version.

**Supported formats**

- **Plain text** — common extensions like `.txt`, `.md`, `.csv`, `.json`, `.log`, `.xml`, `.yaml`, plus any other text file (e.g. `.swift`, `.html`)
- **Documents** — `.pdf`, `.rtf`, `.doc`, `.docx`

### 3. Prepare clipboard text with Safe Paste

`⌘⇧V` — scan the clipboard, mask sensitive values, paste or copy the prepared text.

`⌘⇧R` — restore masked values when you need the originals back.

Mappings are encrypted on disk; the key lives in Keychain. Hotkeys are remappable in Settings.

### 4. Protect commits with hooks

The macOS app includes hook management in **Settings → Hooks**. Add a repository, install a pre-commit hook, and see its status without editing shell scripts by hand.

The hook runs the Offsend CLI against staged changes before each commit and blocks commits that contain sensitive data such as API keys, tokens, private keys, or similar patterns.

### 5. Use the free CLI

The app bundle already includes the `offsend` CLI helper, so the GUI can run local checks and manage hooks out of the box.

You can also install the standalone `offsend-cli` for free when you want `offsend` on `PATH` for terminal workflows, git hooks, CI, or scripts.

---

## Detection

Built-in detectors cover emails, phone numbers, IDs, amounts, URLs, IPs, API keys, tokens, private keys, and similar patterns. Turn individual detectors on or off in **Settings → Detection**.

You can also add **custom dictionaries** in **Settings → Detection** to flag your own client names, companies, projects, internal domains, sensitive terms, or custom regular-expression patterns. Custom dictionaries are available to everyone and also work in the CLI via `.offsend.yml`.

### Local AI detection

Offsend can also run local AI models alongside the built-in pattern detectors. This is useful for NER/PII cases that are harder to catch with regular expressions, such as names, addresses, organization names, and contextual personal data.

AI detection is optional and managed in the macOS app. Download or import a model in **Settings → AI**, select it, then enable **AI detection**. Supported sources include curated Hugging Face models, compatible Hugging Face model IDs or URLs, local folders, direct HTTPS model links, manifests, GGUF files, and local Ollama models.

Supported model formats include ONNX token classification, Core ML, Hugging Face Transformers assets, GGUF, and Ollama API models. Hugging Face access tokens for gated or private models are stored in Keychain. Model files and inference stay on your Mac; Offsend does not upload scanned content for AI detection.

---

## Privacy

Everything runs on your Mac — directory checks, monitoring, clipboard detection, file preparation, masking, and restore.

Offsend does not upload content for scanning and does not store prompts, clipboard payloads, file bodies, or detected values.

Security issues: see [SECURITY.md](SECURITY.md).

---

## Install

### macOS app

```bash
brew install --cask offsend/tap/offsend
```

Or download the latest `.dmg` from [Releases](../../releases).

The app gives you the full menu bar workflow: Safe Paste hotkeys, drag-and-drop file preparation, project checks, watched folders, settings, local AI model management, hook management UI, and the bundled CLI helper used by local checks and hooks.

To make the bundled CLI available as `offsend` in terminals, open **Settings → Hooks → CLI** and install the terminal command. Offsend creates `/usr/local/bin/offsend` as a symlink to the CLI inside `Offsend.app` and does not overwrite an existing Homebrew or third-party `offsend` command.

### Free CLI (macOS + Linux)

Use the standalone CLI for free when you need terminal, git hook, or CI checks without installing the full app.

**Install script (recommended)**

```bash
curl -fsSL https://install.offsend.io/cli | bash
```

Until `install.offsend.io` is wired up, use the script from the repository:

```bash
curl -fsSL https://raw.githubusercontent.com/Offsend/Offsend/main/Scripts/install.sh | bash
```

Pin a release with `OFFSEND_VERSION=0.0.6`, or install without root:

```bash
OFFSEND_INSTALL_DIR=$HOME/.local/bin OFFSEND_PREFIX=$HOME/.local/lib/offsend/cli \
  curl -fsSL https://install.offsend.io/cli | bash
```

**Homebrew**

macOS (Cask — signed binary + frameworks):

```bash
brew install --cask offsend/tap/offsend-cli
offsend doctor
```

Linux (Formula):

```bash
brew install offsend/tap/offsend-cli
offsend doctor
```

**Docker (Linux/macOS with Docker)**

```bash
docker build -f CLI/Dockerfile -t offsend/cli .
docker run --rm -v "$PWD:/work" -w /work offsend/cli check README.md
```

**Build from source**

Requirements: Swift 6.0+, git.

```bash
OFFSEND_CLI_VERSION=0.0.0 bash Scripts/build_linux_cli.sh   # Linux release build
swift build --product offsend -c release                     # any supported host
.build/release/offsend doctor
```

On Linux, config lives under `$XDG_CONFIG_HOME/offsend` (typically `~/.config/offsend`). On macOS CLI, settings use Application Support / Keychain like the app.

### Build from source (macOS app)

```bash
brew install tuist
./Scripts/bootstrap.sh
open Offsend.xcworkspace
```

Requirements: macOS 13+, Xcode 16, Tuist.

macOS may ask for Accessibility (to paste into the front app) and folder access (to audit and monitor directories).

---

## App vs CLI

| | **macOS app** | **CLI (macOS)** | **CLI (Linux)** |
| --- | --- | --- | --- |
| Best for | Daily interactive work | Free terminal, git hook, and CI checks | Free terminal, git hook, and CI checks |
| Safe Paste | Yes: scan, mask, paste, restore | No | No |
| File preparation | Drag-and-drop UI, review, copy/save | Path-based scans | Plain-text path scans only |
| Document formats | Plain text, PDF, RTF, Word | Plain text, PDF, RTF, Word | Plain text only |
| Project checks | UI checks, ignore files, watched folders | `offsend check`, `--staged`, `--policy`, `offsend show`, `offsend prepare` | Same |
| Git hooks | Install/manage in Settings → Hooks | `offsend hook install/status/uninstall` | Same |
| AI models | Download, import, select, and manage models | Not used by the CLI | Not used by the CLI |
| Settings storage | Keychain + Application Support | Keychain + Application Support | Plain JSON in `~/.config/offsend` |
| Automation | Background watcher and notifications | Scriptable text/json output | Scriptable text/json output |

The macOS app already includes the CLI helper at:

`Offsend.app/Contents/Helpers/offsend`

Install the command from **Settings → Hooks → CLI** if you want the app-bundled CLI available as `offsend` on `PATH`. Install the free `offsend-cli` cask separately for CI or standalone terminal-only setups.

---

## Git Hooks & CLI

Offsend ships a free command-line tool for local checks, git hooks, and CI. The main command is `offsend check`.

Scan files or folders:

```bash
offsend check README.md Sources/
```

Scan staged git changes before a commit:

```bash
offsend check --staged
```

Use JSON output in automation:

```bash
offsend check --staged --format json --quiet
```

By default the text output is a summary: findings are grouped per file and skipped files are reported as a count. Add `--verbose` to list every finding (with line numbers) and every skipped file individually.

### Show files exposed to AI tools

`offsend show` lists the sensitive files that would be sent to AI tools because no ignore file covers them — secrets, `.env` files, private keys, credentials, and similar — grouped by data type. It mirrors the macOS app's directory exposure audit and uses the same rules, ignore patterns, and custom template configured there. Like all directory checks, it reads ignore-file contents only, never the matched files themselves.

List exposed files in the current directory:

```bash
offsend show
```

Use JSON output in automation:

```bash
offsend show --format json
```

Options:

- `[path]` — directory to inspect. Defaults to the current directory.
- `--format` — output format, `text` (default) or `json`.

`offsend show` is read-only and informational: it exits `0` even when files are exposed, and `2` only if the directory is unavailable. When it surfaces exposed files, run `offsend prepare` to create the missing ignore files that cover them.

### Prepare AI ignore files

`offsend prepare` creates the AI ignore files a project is missing (`.cursorignore`, `.claudeignore`, `.aiexclude`, `.geminiignore`, and similar), so AI tools respect your privacy boundaries. It mirrors the macOS app's one-click directory fix and uses the same rules and custom ignore template configured there.

Create the missing ignore files in the current directory:

```bash
offsend prepare
```

Preview what would change without writing anything:

```bash
offsend prepare --dry-run
```

Also append missing sensitive-data patterns (such as `secrets.json` or `*.pem`) to ignore files that already exist:

```bash
offsend prepare --sync-patterns
```

Options:

- `[path]` — directory to prepare. Defaults to the current directory.
- `--dry-run` — show which files would be created or updated without writing them.
- `--sync-patterns` — also append missing sensitive-data patterns to ignore files that already exist. Without it, existing files are left untouched.
- `--format` — output format, `text` (default) or `json`.

Only missing files are created; existing ignore files are never overwritten, and informational suggestions (`.gitignore`, `AGENTS.md`, `.cursorindexingignore`) are left for you to add manually. Exit code is `0` on success and `2` if the directory is unavailable or a file could not be written.

### Install a pre-commit hook

Recommended: open **Settings → Hooks** in the macOS app, add a repository, and click **Install Hook**. The GUI also shows hook status and lets you remove hooks later.

From the terminal:

```bash
offsend hook install --path /path/to/your/repo
```

The hook runs `offsend check --staged` before each commit and blocks commits that contain sensitive data (API keys, tokens, private keys, and similar patterns).

### Project config (`.offsend.yml`)

Commit a [`.offsend.yml.example`](.offsend.yml.example) as `.offsend.yml` in your repo to tune check behavior:

```yaml
version: 1

check:
  fail_on: block
  policy: false
  exclude:
    - "*.lock"
    - "vendor/**"
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
```

Supported settings:

- `version` — config schema version. Use `1`; other versions are rejected.
- `check.fail_on` — exit policy for `offsend check`. `block` fails only on blocking findings such as critical secrets or failed policy checks. `warn` also fails on warning/mask findings. `none` reports findings but exits successfully.
- `check.policy` — when `true`, `offsend check` also runs workspace policy checks for ignore files and exposed sensitive paths. When `false`, it scans file contents only.
- `check.exclude` — repository-relative glob patterns skipped by file scanning. Plain file globs such as `*.lock` match file names, path globs such as `build/**` match directories recursively, and slash patterns are matched against repository-relative paths.
- `check.detectors.disable` — detector IDs to turn off for this project. Unknown IDs are ignored.
- `check.dictionaries` — extra custom-dictionary entries matched alongside the built-in detectors. Each entry has a `kind` (`client`, `company`, `project`, `sensitiveTerm`, `internalDomain`, or `regex`) and a `value`. For every kind except `regex`, `value` is matched literally (with word boundaries); for `regex`, `value` is used as a regular-expression pattern. Invalid patterns and unknown kinds are ignored. Entries merge with dictionaries configured in the app.
- `hooks.type` — git hook type to install. Currently supported: `pre-commit`.
- `hooks.fail_on` — exit policy used by installed hooks. If omitted, it falls back to `check.fail_on`, then `block`.
- `hooks.policy` — whether installed hooks include workspace policy checks. If omitted, it falls back to `check.policy`, then `false`. For faster commits that check only staged files, keep this `false`.

CLI flags override config values when they are provided explicitly. For example, `offsend check --policy` enables policy checks even if `check.policy` is `false`.

Supported `check.detectors.disable` IDs:

`email`, `phone`, `money`, `url`, `ipAddress`, `internalDomain`, `contractId`, `invoiceId`, `orderId`, `apiKeyGeneric`, `openAIAPIKey`, `awsAccessKeyId`, `githubToken`, `slackToken`, `stripeKey`, `jwt`, `privateKey`, `sshPrivateKey`, `databaseURLWithPassword`, `bearerToken`, `highEntropyString`, `creditCardLike`, `iban`, `customClient`, `customCompany`, `customProject`, `customSensitiveTerm`, `customInternalDomain`, `personName`, `streetAddress`, `governmentId`.

### CI snippet (macOS + Linux)

```yaml
- name: Install Offsend CLI
  run: curl -fsSL https://install.offsend.io/cli | bash

- name: Check staged changes for secrets
  run: offsend check --staged
```

Fallback before `install.offsend.io` is live:

```yaml
- run: curl -fsSL https://raw.githubusercontent.com/Offsend/Offsend/main/Scripts/install.sh | bash
```

Build from source in the same job (no GitHub release required):

```yaml
- uses: swift-actions/setup-swift@v2
  with:
    swift-version: "6.0.3"
- run: swift build --product offsend -c release
- run: .build/release/offsend check --staged
```

Other useful commands: `offsend check`, `offsend show`, `offsend prepare`, `offsend hook status`, `offsend hook uninstall`.

---

## Free vs Pro

The CLI is free for local checks, git hooks, and CI. Pro expands the interactive macOS app workflow with longer restore windows and unlimited watched folders.

| | **Free** | **Pro** |
| --- | --- | --- |
| Safe Paste & built-in detectors | Unlimited | Unlimited |
| Directory audit & one-click fixes | Full | Full |
| Free CLI for terminal, hooks & CI | Yes | Yes |
| Hook management UI | Yes | Yes |
| File size | Unlimited | Unlimited |
| Custom dictionaries (incl. regex) | Yes | Yes |
| Watched folders | 1 | Unlimited |
| Custom ignore templates | Editable | Editable |
| Mapping TTL | 1 hour | Up to 24 hours |

---

## Built with

Swift macOS app. Built mostly in Cursor; signing, permissions, privacy behavior, and shipping are reviewed by hand.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
