<h1 align="center"><code>*}• Offsend</code></h1>

<p align="center">
  Prepare projects, files, and clipboard text before you share them with AI tools.<br>
  Local checks on your Mac — mask keys, client data, and internal paths when needed.
</p>

<p align="center">
  <a href="https://github.com/Offsend/Offsend/actions/workflows/ci.yml"><img src="https://github.com/Offsend/Offsend/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Offsend/Offsend/releases"><img src="https://img.shields.io/github/v/release/Offsend/Offsend?label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/platform-macOS%2013%2B-000000?logo=apple&logoColor=white" alt="Platform"></a>
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/local--first-yes-2ea44f" alt="Local-first">
</p>

<p align="center">
  <img src="assets/demo.gif" alt="Drop a file or folder into Prepare for AI">
</p>

---

Offsend is a local-first macOS menu bar app and CLI. It helps you get **projects**, **files**, **clipboard text**, and **git changes** AI-ready before ChatGPT, Claude, Cursor, or another tool sees them.

> No cloud account. No server-side scanning. No “trust us”.

---

## What Offsend does

### 1. Prepare a project

Check whether a folder is ready for AI coding tools — ignore files, sensitive paths, one-click fixes.

Works with `.cursorignore`, `.copilotignore`, `.claudeignore`, `.aiexclude`, and similar rules. Can watch folders in the background and notify you when something changes.

Directory checks use paths and ignore rules only — not file contents.

### 2. Prepare a file

Drop a file in **Prepare**, review findings, mask or redact sensitive items, then copy or save an AI-ready version.

**Supported formats**

- **Plain text** — common extensions like `.txt`, `.md`, `.csv`, `.json`, `.log`, `.xml`, `.yaml`, plus any other text file (e.g. `.swift`, `.html`)
- **Documents** — `.pdf`, `.rtf`, `.doc`, `.docx`

### 3. Prepare clipboard text (Safe Paste)

`⌘⇧V` — scan the clipboard, mask sensitive values, paste or copy the prepared text.

`⌘⇧R` — restore masked values when you need the originals back.

Mappings are encrypted on disk; the key lives in Keychain. Hotkeys are remappable in Settings.

---

## Detection & plans

Built-in detectors cover emails, phone numbers, IDs, amounts, URLs, IPs, API keys, tokens, private keys, and similar patterns. Turn individual detectors on or off in **Settings → Detection**.

### Local AI detection

Offsend can also run local AI models alongside the built-in pattern detectors. This is useful for NER/PII cases that are harder to catch with regular expressions, such as names, addresses, organization names, and contextual personal data.

AI detection is optional and managed in the macOS app. Download or import a model in **Settings → AI**, select it, then enable **AI detection**. Supported sources include curated Hugging Face models, compatible Hugging Face model IDs or URLs, local folders, direct HTTPS model links, manifests, GGUF files, and local Ollama models.

Supported model formats include ONNX token classification, Core ML, Hugging Face Transformers assets, GGUF, and Ollama API models. Hugging Face access tokens for gated or private models are stored in Keychain. Model files and inference stay on your Mac; Offsend does not upload scanned content for AI detection.

| | **Free** | **Pro** |
| --- | --- | --- |
| Safe Paste & built-in detectors | Unlimited | Unlimited |
| Directory audit & one-click fixes | Full | Full |
| Watched folders | 1 | Unlimited |
| Custom ignore templates | Default | Editable |
| File size | 15 MB | 50 MB |
| Custom dictionaries | — | Yes |
| Mapping TTL | 1 hour | Up to 24 hours |

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

The app gives you the menu bar workflow: Safe Paste hotkeys, drag-and-drop file preparation, project checks, watched folders, settings, local AI model management, and hook management UI.

### CLI only

Use the standalone CLI when you need terminal, git hook, or CI checks without installing the full app:

```bash
brew install offsend/tap/offsend-cli
offsend doctor
```

### Build from source

```bash
brew install tuist
./Scripts/bootstrap.sh
open Offsend.xcworkspace
```

Requirements: macOS 13+, Xcode 16, Tuist.

macOS may ask for Accessibility (to paste into the front app) and folder access (to audit and monitor directories).

---

## App vs CLI

| | **macOS app** | **CLI** |
| --- | --- | --- |
| Best for | Daily interactive work | Terminal, git hooks, CI |
| Safe Paste | Yes: scan, mask, paste, restore | No |
| File preparation | Drag-and-drop UI, review, copy/save | Path-based scans |
| Project checks | UI checks, ignore files, watched folders | `offsend check`, `--staged`, `--policy` |
| Git hooks | Install/manage in Settings → Hooks | `offsend hook install/status/uninstall` |
| AI models | Download, import, select, and manage models | Not used by the CLI |
| Automation | Background watcher and notifications | Scriptable text/json output |

The app bundle also includes the CLI helper at:

`Offsend.app/Contents/Helpers/offsend`

Install `offsend-cli` separately if you want `offsend` available on `PATH` for shells, hooks, and CI.

---

## Git Hooks & CLI

Offsend ships a command-line tool for local checks, git hooks, and CI. The main command is `offsend check`.

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

### Install a pre-commit hook

From the app: **Settings → Hooks** — add a repository and click **Install Hook**.

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
  exclude:
    - "*.lock"
    - "vendor/**"

hooks:
  type: pre-commit
  fail_on: block
```

### CI snippet

```yaml
- name: Install Offsend CLI
  run: brew install offsend/tap/offsend-cli

- name: Check staged changes for secrets
  run: offsend check --staged
```

Other useful commands: `offsend check`, `offsend hook status`, `offsend hook uninstall`.

---

## Built with

Swift macOS app. Built mostly in Cursor; signing, permissions, privacy behavior, and shipping are reviewed by hand.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
