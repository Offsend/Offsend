<h1 align="center"><code>*}• Offsend</code></h1>

<p align="center">
  Monitor project folders before AI tools see them.<br>
  Clean sensitive clipboard text before you paste it somewhere you cannot take it back.
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
  <img src="assets/demo.gif" alt="Check Directory: drop a folder, review status, turn on background watch">
</p>

---

Offsend is a local-first macOS menu bar app for people who work with projects, documents, internal data, support logs, customer conversations, invoices, contracts, codebases, AI tools, Slack, email, and all the tiny pieces of text that should not accidentally leave your machine.

The main idea is simple: keep an eye on the folders you care about, warn you when ignore rules are missing or sensitive paths are exposed, and give you a safer way to paste clipboard content when needed.

> No cloud account. No server-side scanning. No “trust us”.

---

## Why Offsend exists

AI tools are useful, but they also make it very easy to overshare.

You open a project in Cursor.
You paste a support log into ChatGPT.
You send a customer snippet in Slack.
You copy an invoice, contract, API response, database URL, internal domain, or stack trace.

Most of the time, nothing bad happens.
But the one time you paste a key, customer identifier, private URL, card-like number, token, or internal project name, you wish there had been a quiet safety layer in the middle.

That is Offsend.

It watches the boring-but-important stuff:

- are the right AI ignore files present?
- are sensitive project paths ignored?
- did a risky file appear after the first check?
- does this clipboard text contain something that should be masked before I paste it?
- does this invoice, contract, or PDF need a masked copy before I upload it to an AI tool?

Offsend is not trying to be a giant security platform.
It is a small Mac utility that helps catch obvious leaks before they become expensive ones.

That covers a lot of everyday work:

- you open a project in an AI coding tool and want to know sensitive files are ignored first;
- you manage several folders and want background monitoring instead of checking each one by hand;
- you paste logs, tickets, invoices, contracts, or customer messages into ChatGPT, Claude, Slack, or email — and want tokens, keys, and identifiers masked before they leave your clipboard;
- you want a local safety layer that catches leaks without sending the data to another service.

---

## What it does

### Project monitoring

Add the folders you care about and let Offsend keep an eye on them.

It can monitor projects in the background and re-check them when relevant files change. If the status gets worse, Offsend can notify you.

Useful when:

- a new `.env` file appears;
- someone adds keys, certs, private configs, or local secrets;
- ignore files are missing or incomplete;
- a folder that was safe yesterday is no longer safe today;
- you work across multiple projects and do not want to inspect each one manually.

> **Free plan**: one watched folder.
> **Pro**: unlimited watched folders.

---

### Check Directory

Drop a folder, choose it manually, or paste a path.

Offsend audits the project setup and shows a clear status:

- `PASS` — looks good;
- `WARNING` — something needs attention;
- `FAIL` — risky paths are exposed or required ignore files are missing.

It checks for missing AI ignore files and sensitive paths that exist on disk but are not ignored.

Offsend works with common AI coding tools and ignore files such as:

- Cursor / `.cursorignore`
- GitHub Copilot / `.copilotignore`
- Claude Code
- Windsurf
- `.aiexclude`
- and similar project-level ignore rules

> **Important detail**: Offsend checks paths and ignore rules. It does not need to read your file contents for directory audits, and it does not upload anything.

---

### Safe Clipboard / Safe Paste

Use Safe Paste when you want to send text somewhere, but not the sensitive parts.

With `⌘⇧V`, Offsend checks the clipboard, masks detected values, then pastes or copies the safer version.

With `⌘⇧R`, you can restore masked values when you actually need the original text back.

> Mappings are encrypted on disk, with the key stored in Keychain.
> Hotkeys are remappable in Settings.

---

### Sanitize Document

Open **Sanitize Document** from the menu bar or Settings when you need to clean a whole file before you paste, upload, or share it.

Drop a file or choose one manually. Offsend extracts text locally, scans it with the same detectors as Safe Paste, shows a risk summary, and lets you choose which sensitive items to mask. Then copy the safe text or save a masked copy.

Supported formats include common text files (`.txt`, `.md`, `.csv`, `.json`, `.log`, `.yaml`, and similar) and PDF.

> **Free plan**: documents up to 15 MB.
> **Pro**: up to 50 MB.

> Detection, masking, and restore run on your Mac. Offsend does not upload files for scanning.

---

## What Offsend can detect in clipboard text

Safe Paste and Sanitize Document use the same built-in detectors. Safe Paste scans clipboard text before you paste somewhere you cannot take it back. Built-in detectors cover four groups:

| Group | What it catches |
| --- | --- |
| **Personal** | emails, phone numbers |
| **Business & finance** | contract, invoice, and order IDs; amounts; card-like numbers; IBANs |
| **Links & network** | URLs, IP addresses, internal domains |
| **Secrets & credentials** | OpenAI, AWS, GitHub, Slack, and Stripe keys; JWTs; private keys; database URLs with passwords; bearer tokens; high-entropy strings |

**Pro:** custom dictionaries for client names, company names, project codenames, internal domains, and other terms you define.

Offsend is not only about developers and source code. It is also useful for customer data, support logs, finance, contracts, and any text that should stay clean before AI tools touch it.

> Turn individual detectors on or off in **Settings → Detection**.

---

## Privacy

Offsend is local-first by design.

Directory checks, monitoring, clipboard detection, document sanitization, masking, and restore run on your Mac.

Clipboard data is touched when you use Safe Paste / Restore, unless you explicitly enable optional clipboard monitoring in Settings.

Document sanitization reads file content only when you open Sanitize Document and choose a file. Nothing is uploaded for scanning.

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

**DocumentCore** (`Core/DocumentCore`) powers Sanitize Document: it reads files locally, extracts plain text (including PDF), runs detection and risk scoring, and produces masked output through a small pipeline (`DocumentProcessingPipeline`). Extractors are pluggable; the app wires in the same `DetectionCore`, `RiskScoringCore`, and `MaskingCore` engines used for Safe Paste.

Most of the work happened in Cursor, with AI helping on UI, wiring, tests, and repetitive implementation details. The parts that matter — signing, permissions, privacy behavior, and what actually ships — are reviewed by hand.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
