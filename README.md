<h1 align="center"><code>*}• Offsend</code></h1>

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)

Monitor project folders before AI tools see them.
Clean sensitive clipboard text before you paste it somewhere you cannot take it back.

Offsend is a local-first macOS menu bar app for people who work with projects, documents, internal data, support logs, customer conversations, invoices, contracts, codebases, AI tools, Slack, email, and all the tiny pieces of text that should not accidentally leave your machine.

The main idea is simple: keep an eye on the folders you care about, warn you when ignore rules are missing or sensitive paths are exposed, and give you a safer way to paste clipboard content when needed.

No cloud account. No server-side scanning. No “trust us”.
Offsend runs on your Mac.

![Check Directory: drop a folder, review status, turn on background watch](assets/demo.gif)

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

Offsend is not trying to be a giant security platform.
It is a small Mac utility that helps catch obvious leaks before they become expensive ones.

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

Free plan: one watched folder.
Pro: unlimited watched folders.

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

Important detail: Offsend checks paths and ignore rules. It does not need to read your file contents for directory audits, and it does not upload anything.

---

### Safe Clipboard / Safe Paste

Use Safe Paste when you want to send text somewhere, but not the sensitive parts.

With `⌘⇧V`, Offsend checks the clipboard, masks detected values, then pastes or copies the safer version.

With `⌘⇧R`, you can restore masked values when you actually need the original text back.

Mappings are encrypted on disk, with the key stored in Keychain.

Hotkeys are remappable in Settings.

---

## What Offsend can detect in clipboard text

Offsend can look for common personal, business, infrastructure, and secret-like patterns, including:

### Personal and contact data

- `email`
- `phone`

### Money, links, and network data

- `money`
- `url`
- `ipAddress`
- `internalDomain`

### Business identifiers

- `contractId`
- `invoiceId`
- `orderId`

### Finance-like data

- `creditCardLike`
- `iban`

### API keys, tokens, and credentials

- `openAIAPIKey`
- `awsAccessKeyId`
- `githubToken`
- `slackToken`
- `stripeKey`
- `jwt`
- `privateKey`
- `sshPrivateKey`
- `databaseURLWithPassword`
- `bearerToken`
- `apiKeyGeneric`
- `highEntropyString`

### Custom sensitive terms

- `customClient`
- `customCompany`
- `customProject`
- `customSensitiveTerm`
- `customInternalDomain`

So Offsend is not only about developers and source code.
It is also useful for people who work with customer data, internal operations, sales, finance, support, documents, logs, contracts, invoices, and project folders that should stay clean before AI tools touch them.

---

## When it is useful

- You want to open a project in an AI coding tool, but first need to know whether sensitive files are ignored.
- You manage several project folders and want background monitoring instead of manual checks.
- You paste logs, tickets, snippets, invoices, contracts, or customer messages into ChatGPT, Claude, Slack, email, or internal tools.
- You want emails, phones, URLs, internal domains, IDs, tokens, and keys masked before text leaves your clipboard.
- You need a local safety layer that helps you catch leaks without sending the data to another service.

---

## Privacy

Offsend is local-first by design.

Directory checks, monitoring, clipboard detection, masking, and restore run on your Mac.

Clipboard data is touched when you use Safe Paste / Restore, unless you explicitly enable optional clipboard monitoring in Settings.

Offsend does not store prompt text, clipboard payloads, or detected secret values.
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
