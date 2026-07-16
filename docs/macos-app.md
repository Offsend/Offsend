# macOS app

Interactive workflow on Mac: Safe Paste, drag-and-drop file preparation, project audits, watched folders, local AI detection, and hook management UI.

<p align="center">
  <img src="../assets/prepare_file.gif" alt="Drop a file or folder into Prepare for AI" width="100%">
</p>

## Install

```bash
brew install --cask offsend/tap/offsend
```

Or download the latest `.dmg` from [Releases](https://github.com/Offsend/Offsend/releases).

The app also ships a bundled `offsend` helper (`Offsend.app/Contents/Helpers/offsend`). Put it on `PATH` from **Settings → Hooks → CLI** — it will not overwrite an existing Homebrew `offsend`.

**Build from source** — macOS 13+, Xcode 16, Tuist:

```bash
brew install tuist
./Scripts/bootstrap.sh
open Offsend.xcworkspace
```

macOS may ask for Accessibility (to paste into the front app) and folder access (to audit and monitor directories).

## What you can do

**Prepare a project** — audit ignore files and sensitive paths, one-click fixes, optional watched folders. Paths and ignore rules only — not file contents. Works with `.cursorignore`, `.copilotignore`, `.claudeignore`, `.aiexclude`, and similar.

<p align="center">
  <img src="../assets/prepare_projects.gif" alt="Prepare a project: audit ignore files and sensitive paths" width="100%">
</p>

**Prepare files** — drop a file, review findings, mask or redact, then copy or save. Plain text plus `.pdf`, `.rtf`, `.doc`, `.docx`.

<p align="center">
  <img src="../assets/prepare_file.gif" alt="Prepare files: drop a file, review findings, mask for AI" width="100%">
</p>

**Safe Paste** — `⌘⇧V` scans and pastes a masked clipboard; `⌘⇧R` restores originals. Mappings are encrypted on disk; the key lives in Keychain.

<p align="center">
  <img src="../assets/safe_paste.gif" alt="Safe Paste: scan clipboard, mask secrets, paste" width="100%">
</p>

**Git hooks** — **Settings → Hooks** to install and manage pre-commit checks. From the terminal: [`offsend hook install`](cli.md#hook-install) (git) or [`--target cursor|claude|…`](cli.md#ai-editor-hooks) for AI-editor hooks.

**Detection & local AI** — toggle built-in detectors and custom dictionaries in **Settings → Detection** (also via [`.offsend.yml`](configuration.md)). Optional NER/PII models in **Settings → AI** stay on your Mac.

## App vs CLI

| | **CLI (macOS / Linux)** | **macOS app** |
| --- | --- | --- |
| Best for | Terminal, hooks, CI | Daily interactive work |
| Safe Paste | No | Yes |
| File preparation | Path-based scans | Drag-and-drop UI, review, copy/save |
| Documents | Plain text (+ PDF/RTF/Word on macOS CLI) | Plain text, PDF, RTF, Word |
| Project checks | `show`, `prepare`, `check --policy` | UI checks, watched folders |
| Git hooks | `offsend hook …` | Settings → Hooks |
| AI prompt hooks | `hook install --target …` ([docs](cli.md#ai-editor-hooks)) | — |
| AI models | Not used by the CLI | Download / import / manage |
| Automation | Scriptable text / JSON | Background watcher + notifications |

## Free vs Pro

The core protection workflow is free. Pro adds unlimited watched folders and longer restore windows.

| | **Free** | **Pro** |
| --- | --- | --- |
| Safe Paste & built-in detectors | Unlimited | Unlimited |
| Directory audit & one-click fixes | Full | Full |
| CLI for terminal, hooks & CI | Yes | Yes |
| Hook management UI | Yes | Yes |
| Custom dictionaries (incl. regex) | Yes | Yes |
| Watched folders | 1 | Unlimited |
| Mapping TTL | 1 hour | Up to 24 hours |

## Related

- [README](../README.md) — product overview and quick start
- [CLI reference](cli.md)
- [FAQ](faq.md)
