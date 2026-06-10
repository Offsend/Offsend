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

Offsend is a local-first macOS menu bar app. It helps you get **projects**, **files**, and **clipboard text** AI-ready before ChatGPT, Claude, Cursor, or another tool sees them.

> No cloud account. No server-side scanning. No “trust us”.

---

## What Offsend does

### 1. Prepare a project

Check whether a folder is ready for AI coding tools — ignore files, sensitive paths, one-click fixes.

Works with `.cursorignore`, `.copilotignore`, `.claudeignore`, `.aiexclude`, and similar rules. Can watch folders in the background and notify you when something changes.

Directory checks use paths and ignore rules only — not file contents.

### 2. Prepare a file

Drop a file in **Prepare**, review findings, mask or redact sensitive items, then copy or save an AI-ready version.

**Supported formats** *(more coming)*

- **Text** — `.txt`, `.md`, `.markdown`, `.csv`, `.json`, `.log`, `.xml`, `.yaml`, `.yml`
- **Documents** — `.pdf`, `.rtf`

### 3. Prepare clipboard text (Safe Paste)

`⌘⇧V` — scan the clipboard, mask sensitive values, paste or copy the prepared text.

`⌘⇧R` — restore masked values when you need the originals back.

Mappings are encrypted on disk; the key lives in Keychain. Hotkeys are remappable in Settings.

---

## Detection & plans

Built-in detectors cover emails, phone numbers, IDs, amounts, URLs, IPs, API keys, tokens, private keys, and similar patterns. Turn individual detectors on or off in **Settings → Detection**.

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

Download the latest build from [Releases](../../releases), or build from source:

```bash
brew install tuist
./Scripts/bootstrap.sh
open Offsend.xcworkspace
```

Requirements: macOS 13+, Xcode 16, Tuist.

macOS may ask for Accessibility (to paste into the front app) and folder access (to audit and monitor directories).

---

## Built with

Swift macOS app. Built mostly in Cursor; signing, permissions, privacy behavior, and shipping are reviewed by hand.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
