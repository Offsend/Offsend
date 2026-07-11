<h1 align="center"><code>*}• Offsend</code></h1>

<p align="center">
  See and fix what AI tools can read.<br>
  Local-first privacy checks for terminals, CI, and macOS — before ChatGPT, Claude, Cursor, Copilot, or Gemini see your context.
</p>

<p align="center">
  <a href="https://github.com/Offsend/Offsend/actions/workflows/ci.yml"><img src="https://github.com/Offsend/Offsend/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Offsend/Offsend/releases"><img src="https://img.shields.io/github/v/release/Offsend/Offsend?label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/Linux-CLI%20(x86_64%20%7C%20arm64)-FCC624?logo=linux&logoColor=black" alt="Linux CLI">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/platform-macOS%2013%2B-000000?logo=apple&logoColor=white" alt="Platform"></a>
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/local--first-yes-2ea44f" alt="Local-first">
  <a href="https://radar.offsend.io/participants/"><img src="https://radar.offsend.io/badge.svg" alt="AI Context Reviewed" height="20"></a>
</p>

---

`.gitignore` protects Git. It does not define what AI tools should ignore.

Offsend helps you catch secrets, client data, internal paths, and other sensitive details before they become AI context — in the terminal, in CI, or from the macOS menu bar.

> No cloud account. No server-side scanning of your local files or prompts. No “trust us” privacy model.

## Why Offsend

AI coding tools need context. Sometimes that context includes things you never intended to share:

- `.env` files and API keys
- certificates and private keys
- internal configs and logs
- customer names and IDs

Offsend adds a local review step without changing how you work.

**What you can do**

- Scan projects for AI-context risks
- Show what AI tools can read
- Generate AI ignore files (`.cursorignore`, `.claudeignore`, …)
- Check staged changes and block risky commits
- Prepare files and clipboard text before sharing with AI
- Protect browser prompts before you hit send

---

## Pick your workflow

| Tool | Purpose | Link |
| --- | --- | --- |
| **CLI** | Terminal, git hooks, and CI on **Linux & macOS** (free) | [Install below](#cli) |
| **macOS app** | Safe Paste, drag-and-drop prep, watched folders | [Desktop](#macos-app) |
| **Check** | Free online scan of a public GitHub repo | [check.offsend.io](https://check.offsend.io) |
| **GitHub Action** | Same CLI checks on every PR / push | [ai-hygiene](https://offsend.io/github-action) |
| **Browser Extension** | Mask secrets in ChatGPT, Claude, Gemini, … | [Extension](https://offsend.io/extension) |
| **Radar** | Research AI-context exposure across public repos | [radar.offsend.io](https://radar.offsend.io) |

---

## CLI

Free for local checks, git hooks, and CI. Runs on **macOS and Linux** (x86_64 and arm64).

### Install

```bash
curl -fsSL https://install.offsend.io/cli | bash
offsend doctor
```

Until `install.offsend.io` is wired up, use the script from the repository:

```bash
curl -fsSL https://raw.githubusercontent.com/Offsend/Offsend/main/Scripts/install.sh | bash
```

**Homebrew**

```bash
# macOS (signed binary + frameworks)
brew install --cask offsend/tap/offsend-cli

# Linux
brew install offsend/tap/offsend-cli

offsend doctor
```

Pin a release with `OFFSEND_VERSION=0.0.6`, or install without root:

```bash
OFFSEND_INSTALL_DIR=$HOME/.local/bin OFFSEND_PREFIX=$HOME/.local/lib/offsend/cli \
  curl -fsSL https://install.offsend.io/cli | bash
```

**Docker**

```bash
docker build -f CLI/Dockerfile -t offsend/cli .
docker run --rm -v "$PWD:/work" -w /work offsend/cli check README.md
```

**Build from source** — Swift 6.0+, git:

```bash
OFFSEND_CLI_VERSION=0.0.0 bash Scripts/build_linux_cli.sh   # Linux release build
swift build --product offsend -c release                     # any supported host
.build/release/offsend doctor
```

<p align="center">
  <img src="assets/cli.png" alt="Offsend CLI in the terminal" width="720">
</p>

### Try it in under a minute

```bash
cd your-repo
offsend show
```

Example outcome:

```text
✓ 18 files visible to AI tools

⚠ .env
⚠ certs/private.pem
⚠ .npmrc

Run:
  offsend prepare
```

Then fix ignore gaps and protect commits:

```bash
offsend prepare
offsend hook install
offsend check --staged
```

### Typical workflow

```text
Clone repository
        ↓
offsend show          → what can AI tools read?
        ↓
offsend prepare       → create missing AI ignore files
        ↓
offsend hook install  → block secrets before commit
        ↓
Continue working
```

### Main use cases

**1. See what AI tools can read**

`offsend show` lists sensitive files that would be sent to AI tools because no ignore file covers them — secrets, `.env`, private keys, credentials — grouped by data type. It reads ignore-file contents and paths only, never the matched files themselves.

```bash
offsend show
offsend show --format json
```

Exits `0` even when files are exposed (`2` only if the directory is unavailable). When it surfaces exposed files, run `offsend prepare`.

**2. Generate AI ignore files**

`offsend prepare` creates missing ignore files (`.cursorignore`, `.claudeignore`, `.aiexclude`, `.geminiignore`, and similar). Existing files are never overwritten.

```bash
offsend prepare
offsend prepare --dry-run
offsend prepare --sync-patterns   # also append missing sensitive-data patterns
```

**3. Scan files and staged changes**

```bash
offsend check README.md Sources/
offsend check --staged
offsend check --staged --format json --quiet
```

By default the text output is a summary. Add `--verbose` to list every finding and skipped file.

**4. Protect commits with a hook**

```bash
offsend hook install --path /path/to/your/repo
offsend hook status
offsend hook uninstall
```

The hook runs `offsend check --staged` and blocks commits that contain API keys, tokens, private keys, and similar patterns.

**5. CI**

```yaml
- name: Install Offsend CLI
  run: curl -fsSL https://install.offsend.io/cli | bash

- name: Check for secrets
  run: offsend check --staged
```

Or use the packaged action:

```yaml
- uses: actions/checkout@v4
- uses: Offsend/ai-hygiene@v1
  with:
    fail-on: block
```

### Commands

| Command | Description |
| --- | --- |
| `offsend show` | Show what AI tools can read |
| `offsend prepare` | Generate missing AI ignore files |
| `offsend check` | Scan files or staged changes |
| `offsend hook install` | Install a pre-commit hook |
| `offsend doctor` | Verify installation |
| `offsend init` | Create a starter `.offsend.yml` |

Also available: `offsend seal` / `unseal` (reversible masking tokens), `offsend report`, `offsend keygen`.

### Configuration

Tune detectors, exclusions, and hook policy with a committed `.offsend.yml`:

```bash
offsend init
```

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

hooks:
  type: pre-commit
  fail_on: block
  policy: false
```

Full settings reference, detector IDs, and dictionary kinds: **[docs/configuration.md](docs/configuration.md)**.

---

## macOS App

Interactive workflow for daily work on Mac: Safe Paste, drag-and-drop file preparation, project audits, watched folders, local AI detection, and hook management UI.

<p align="center">
  <img src="assets/demo.gif" alt="Drop a file or folder into Prepare for AI">
</p>

<p align="center">
  <img src="assets/clipboard.png" alt="Safe Paste" width="360">
  &nbsp;
  <img src="assets/projects.png" alt="Project checks" width="360">
</p>

### Install

```bash
brew install --cask offsend/tap/offsend
```

Or download the latest `.dmg` from [Releases](../../releases).

The app bundle includes the CLI helper at `Offsend.app/Contents/Helpers/offsend`. To put it on `PATH` as `offsend`, open **Settings → Hooks → CLI** (does not overwrite an existing Homebrew `offsend`).

**Build from source** — macOS 13+, Xcode 16, Tuist:

```bash
brew install tuist
./Scripts/bootstrap.sh
open Offsend.xcworkspace
```

macOS may ask for Accessibility (to paste into the front app) and folder access (to audit and monitor directories).

### What you can do

**1. Prepare a project**

Check whether a folder is ready for AI coding tools: ignore files, sensitive paths, one-click fixes. Works with `.cursorignore`, `.copilotignore`, `.claudeignore`, `.aiexclude`, and similar rules. Can watch folders in the background and notify you when something changes.

Directory checks use paths and ignore rules only — not file contents.

**2. Prepare files**

Drop a file in **Prepare**, review findings, mask or redact sensitive items, then copy or save an AI-ready version.

Supported formats:

- **Plain text** — `.txt`, `.md`, `.csv`, `.json`, `.log`, `.xml`, `.yaml`, plus other text files (e.g. `.swift`, `.html`)
- **Documents** — `.pdf`, `.rtf`, `.doc`, `.docx`

**3. Safe Paste**

- `⌘⇧V` — scan the clipboard, mask sensitive values, paste or copy the prepared text
- `⌘⇧R` — restore masked values when you need the originals

Mappings are encrypted on disk; the key lives in Keychain. Hotkeys are remappable in Settings.

**4. Git hooks from the UI**

**Settings → Hooks** — add a repository, install a pre-commit hook, and see status without editing shell scripts by hand.

**5. Detection & local AI**

Built-in detectors cover emails, phones, IDs, amounts, URLs, IPs, API keys, tokens, private keys, and similar patterns. Toggle them in **Settings → Detection**. Add **custom dictionaries** (client names, companies, regex patterns) — also available to the CLI via `.offsend.yml`.

Optional local AI models (NER/PII) live in **Settings → AI**. Model files and inference stay on your Mac; Offsend does not upload scanned content for AI detection.

### App vs CLI

| | **CLI (macOS / Linux)** | **macOS app** |
| --- | --- | --- |
| Best for | Terminal, hooks, CI | Daily interactive work |
| Safe Paste | No | Yes |
| File preparation | Path-based scans | Drag-and-drop UI, review, copy/save |
| Documents | Plain text (+ PDF/RTF/Word on macOS CLI) | Plain text, PDF, RTF, Word |
| Project checks | `show`, `prepare`, `check --policy` | UI checks, watched folders |
| Git hooks | `offsend hook …` | Settings → Hooks |
| AI models | Not used by the CLI | Download / import / manage |
| Automation | Scriptable text / JSON | Background watcher + notifications |

### Free vs Pro

The CLI is free. Pro expands the interactive macOS app workflow.

| | **Free** | **Pro** |
| --- | --- | --- |
| Safe Paste & built-in detectors | Unlimited | Unlimited |
| Directory audit & one-click fixes | Full | Full |
| CLI for terminal, hooks & CI | Yes | Yes |
| Hook management UI | Yes | Yes |
| Custom dictionaries (incl. regex) | Yes | Yes |
| Watched folders | 1 | Unlimited |
| Mapping TTL | 1 hour | Up to 24 hours |

---

## More of the Offsend toolkit

Same idea on every surface: see what AI can read, then fix it.

### [Check](https://check.offsend.io) — scan a GitHub repo online

Paste a public GitHub URL. Get exposed secrets, risky configs, and missing AI ignore rules — no signup. Full file paths stay hidden in the report. Start here if you want value before installing anything.

### [GitHub Action](https://offsend.io/github-action) — CI gate

[`Offsend/ai-hygiene`](https://github.com/Offsend/ai-hygiene) installs the CLI and runs `offsend check` on pull requests and pushes. Tune with the same `.offsend.yml` as local runs.

### [Browser Extension](https://offsend.io/extension) — protect prompts

Chrome / Firefox extension that scans ChatGPT, Claude, Gemini, Grok, Perplexity, and DeepSeek prompts locally before send. Mask with placeholders like `{{API_KEY_1}}`, or warn / block. No prompt content uploaded for scanning.

### [Radar](https://radar.offsend.io) — exposure research

Tracks AI-context risk signals across public repositories without reading file contents or publishing exact paths. Useful for understanding how common exposed `.env`, keys, and credentials are in the wild.

---

## Privacy

Everything in the CLI, desktop app, and browser extension runs locally on your machine.

Offsend does not upload content for scanning and does not store prompts, clipboard payloads, file bodies, or detected values.

Security issues: see [SECURITY.md](SECURITY.md).

---

## FAQ

**Does Offsend upload my code?**  
No. Local tools read paths, ignore rules, and (for content scans) files on your machine. Nothing is sent to Offsend for scanning. Check only analyzes a GitHub repo you choose to scan online.

**Is the CLI free?**  
Yes — terminal, git hooks, and CI. Pro is optional for the macOS app (longer restore windows, unlimited watched folders).

**How is this different from a secret scanner?**  
Secret scanners focus on credentials in git history. Offsend also asks what AI tools can *see*: missing AI ignore files, exposed sensitive paths, clipboard/prompt leaks, and file prep before you paste into an assistant.

**Does it replace `.gitignore`?**  
No. `.gitignore` controls Git. Offsend helps with AI ignore files (`.cursorignore`, `.claudeignore`, …) and content checks before share or commit.

**Which AI tools are supported?**  
Any tool that respects common AI ignore files, plus browser chats covered by the extension (ChatGPT, Claude, Gemini, and others). The CLI and app are tool-agnostic.

---

## Docs

- [Configuration (`.offsend.yml`)](docs/configuration.md)
- [Security](SECURITY.md)

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
