<h1 align="center"><code>*}• Offsend</code></h1>

<p align="center">
  Prepare projects, documents, and text before you share them with AI tools.<br>
  Review locally on your Mac — mask keys, client data, and internal paths when needed.
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
  <img src="assets/demo.gif" alt="Prepare: drop a file or folder, review findings, export an AI-ready copy">
</p>

---

Offsend is a local-first macOS menu bar app for people who work with projects, documents, support logs, customer conversations, invoices, contracts, codebases, and AI tools every day — and want a quick local check before something leaves their Mac.

The main idea is simple: get folders, files, and clipboard snippets **AI-ready** on your Mac before ChatGPT, Claude, Cursor, or another tool sees them.

> No cloud account. No server-side scanning. No “trust us”.

---

## The problem

AI tools are useful, but they make it easy to overshare by accident.

You open a project in Cursor.
You upload a PDF to ChatGPT.
You paste a support log into Claude.
You copy an invoice, contract, API response, database URL, internal domain, or stack trace.

Most of the time, nothing bad happens.
But when a key, customer identifier, private URL, card-like number, token, or internal project name slips through, you wish there had been a quiet step in the middle.

That is Offsend.

---

## What Offsend does

One app, three ways to prepare something for AI:

### 1. Prepare a project folder

Add the folders you care about and let Offsend check whether they are ready for AI coding tools.

Drop a folder, choose it manually, or paste a path. Offsend audits ignore files and sensitive paths, then shows a clear status:

- `PASS` — looks good;
- `WARNING` — something needs attention;
- `FAIL` — risky paths are exposed or required ignore files are missing.

It works with common AI coding tools and ignore files such as:

- Cursor / `.cursorignore`
- GitHub Copilot / `.copilotignore`
- Claude Code
- Windsurf
- `.aiexclude`
- and similar project-level ignore rules

Offsend can also monitor projects in the background and re-check them when relevant files change. If the status gets worse, Offsend can notify you.

Useful when:

- a new `.env` file appears;
- someone adds keys, certs, private configs, or local secrets;
- ignore files are missing or incomplete;
- a folder that was AI-ready yesterday is no longer ready today;
- you work across multiple projects and do not want to inspect each one manually.

> **Free plan**: full audit for every AI tool and sensitive path; one-click fixes for `.cursorignore` and `.claudeignore`; one watched folder.
> **Pro**: one-click fixes for every tool and pattern; unlimited watched folders; custom ignore templates.

> **Important detail**: directory checks use paths and ignore rules. Offsend does not need to read your file contents for folder audits, and it does not upload anything.

---

### 2. Prepare a document

Open **Prepare** from the menu bar or Settings when you need to review a whole file before you paste, upload, or share it.

Drop a file or choose one manually. Offsend extracts text locally, scans it with the same detectors as Safe Paste, shows what was found, and lets you choose which sensitive items to mask or redact. Then copy the prepared text or save a prepared copy.

Supported formats include common text files (`.txt`, `.md`, `.csv`, `.json`, `.log`, `.yaml`, and similar) and PDF.

> **Free plan**: documents up to 15 MB.
> **Pro**: up to 50 MB.

> Detection, masking, and restore run on your Mac. Offsend does not upload files for scanning.

---

### 3. Prepare clipboard text (Safe Paste)

Use Safe Paste when you want to send text somewhere, but not the sensitive parts.

With `⌘⇧V`, Offsend checks the clipboard, masks detected values, then pastes or copies the prepared version.

With `⌘⇧R`, you can restore masked values when you actually need the original text back.

> Mappings are encrypted on disk, with the key stored in Keychain.
> Hotkeys are remappable in Settings.

---

## What Offsend can flag

Safe Paste and document preparation use the same built-in detectors. Safe Paste scans clipboard text before you paste somewhere you cannot take it back. Built-in detectors cover four groups:

| Group | What it catches |
| --- | --- |
| **Personal** | emails, phone numbers |
| **Business & finance** | contract, invoice, and order IDs; amounts; card-like numbers; IBANs |
| **Links & network** | URLs, IP addresses, internal domains |
| **Secrets & credentials** | OpenAI, AWS, GitHub, Slack, and Stripe keys; JWTs; private keys; database URLs with passwords; bearer tokens; high-entropy strings |

**Pro:** custom dictionaries for client names, company names, project codenames, internal domains, and other terms you define; mapping TTL up to 24 hours.

### Plans at a glance

| | **Free** | **Pro** |
| --- | --- | --- |
| Safe Paste & built-in detectors | Unlimited | Unlimited |
| Directory audit (all tools & patterns) | Full detection | Full detection |
| One-click project fixes | `.cursorignore`, `.claudeignore` | All tools & patterns |
| Watched folders | 1 | Unlimited |
| Document size | 15 MB | 50 MB |
| Custom dictionaries | — | Yes |
| Mapping TTL | 1 hour | Up to 24 hours |

Offsend is not only about developers and source code. It is also useful for customer data, support logs, finance, contracts, and any text that should be cleaned before AI tools touch it.

> Turn individual detectors on or off in **Settings → Detection**.

---

## Privacy

Offsend is local-first by design.

Directory checks, monitoring, clipboard detection, document preparation, masking, and restore run on your Mac.

Clipboard data is touched when you use Safe Paste / Restore, unless you explicitly enable optional clipboard monitoring in Settings.

Document preparation reads file content only when you open Prepare and choose a file. Nothing is uploaded for scanning.

Offsend does not store prompt text, clipboard payloads, document bodies, or detected secret values.
Directory audits use paths and ignore rules, not file bodies.

Security issues: see [SECURITY.md](SECURITY.md).

---

## Install

Download the latest build from [Releases](../../releases), or build from source:

```bash
brew install tuist
./Scripts/bootstrap.sh
open Offsend.xcworkspace
```

Requirements:

- macOS 13+
- Xcode 16
- Tuist

macOS may ask for Accessibility permission so Offsend can paste into the front app, and folder access so it can audit and monitor selected directories.

---

## Built with

Offsend is a Swift macOS app.

Most of the work happened in Cursor, with AI helping on UI, wiring, tests, and repetitive implementation details. The parts that matter — signing, permissions, privacy behavior, and what actually ships — are reviewed by hand.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
