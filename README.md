<div align="center">

# ```*}• Offsend```

**Paste into ChatGPT, Slack, and internal tools — without leaking secrets.**

A native **macOS** menu bar app that sits between your clipboard and the target app: it detects sensitive data, scores risk, masks values with placeholders, and lets you **locally** restore originals when it is safe to do so.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)](https://swift.org/)
[![Tuist](https://img.shields.io/badge/project-Tuist-6236FF?logo=tuist&logoColor=white)](https://tuist.io/)

[Features](#features) · [Quick start](#quick-start) · [Privacy](#privacy) · [Development](#development) · [Security](#security)

</div>

---

## Why Offsend

You copy a log, ticket, or code snippet that contains tokens, emails, or internal IDs — then paste into an AI assistant or a workplace app. **Offsend** masks that content before it lands there. Detection, risk scoring, masking, and encrypted **placeholder ↔ original** mappings run **on your Mac**; nothing is sent to the cloud for those steps.

| For users | For developers |
|-----------|----------------|
| Global shortcuts, menu bar entry, tunable detectors | Modular core: detection, risk, masking, storage |
| Clear, local-first privacy model | Tuist, Swift strict concurrency, unit-tested core |
| Optional clipboard monitoring with the same local pipeline | CI, release automation, Sparkle for updates |

---

## Features

- **Safe Paste** — scan the clipboard, show a risk sheet when needed, mask, then paste or copy a safe version.
- **Restore** — bring back originals from **locally encrypted** mappings (Keychain-backed key).
- **Settings** — detectors, custom dictionaries, mapping TTL, hotkeys, login item, optional clipboard watch, licensing.
- **Native stack** — Swift, shared UI in `AppUIKit`, no heavyweight runtime around the clipboard.

### Default shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧V` | Safe Paste: assess → mask → paste or safe copy |
| `⌘⇧R` | Restore placeholders from local mappings |

You can remap these in Settings.

---

## Quick start

**From source** (for contributors and power users):

1. Install the [development requirements](#requirements).
2. Run `tuist generate` and open `Offsend.xcworkspace` in Xcode.
3. Build the **Offsend** scheme (`⌘B`) and run (`⌘R`).

Grant macOS permissions as prompted (**Accessibility** is used to simulate paste into the front app; without it, the app falls back to mask-and-copy).

When prebuilt releases are published, install the `.app` or DMG from the repository **Releases** page.

---

## Privacy

- Clipboard text is read **only after an explicit user action** (Safe Paste / Restore), unless optional monitoring is enabled in Settings.
- Detection, risk scoring, masking, and restore are **local**.
- Placeholder mappings are encrypted on disk with a **Keychain**-backed key.
- Local counters do **not** include prompt text, clipboard contents, detected values, app names, or window titles.
- Optional clipboard monitoring uses the same **local** pipeline; nothing is sent to remote services for masking or restore.

For vulnerability reporting and secret-handling notes, see [`SECURITY.md`](SECURITY.md).

---

## Development

### Requirements

- **macOS 13** Ventura or later  
- **Xcode 16** (or compatible Command Line Tools)  
- **[Tuist](https://tuist.io/)**

### Generate and open in Xcode

```bash
brew install tuist
./Scripts/bootstrap.sh
open Offsend.xcworkspace
```

Equivalent manual steps: `tuist install && tuist generate`.

### Common commands

```bash
tuist test
tuist build
./Scripts/lint.sh
```

### DMG from a signed `.app`

Set `APP_PATH` and optionally `DMG_PATH`, then:

```bash
./Scripts/build_dmg.sh
```

Developer ID signing, notarization, Sparkle appcast, and GitHub Actions are orchestrated in [`.github/workflows/release.yml`](.github/workflows/release.yml). Configure secrets and signing identities in your CI environment.

### Repository layout

| Path | Purpose |
|------|---------|
| `App/` | App entry, coordinators, settings, onboarding |
| `AppUIKit/` | Shared UI components and theming |
| `Core/` | `DetectionCore`, `MaskingCore`, `RiskScoringCore`, `StorageCore`, `LicenseCore` |
| `Services/` | Clipboard, paste simulation, hotkeys, permissions, local analytics |
| `Tuist/` | Tuist project helpers |
| `Scripts/` | Bootstrap, lint, DMG helper scripts |

Third-party dependencies: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), [SQLite.swift](https://github.com/stephencelis/SQLite.swift), [Sparkle](https://github.com/sparkle-project/Sparkle).

The `docs/` directory is intentionally **gitignored** for local or internal notes and is not part of the published tree.

---

## Security

Please follow responsible disclosure in [`SECURITY.md`](SECURITY.md).

---

## App updates

**Sparkle** is integrated; `SUFeedURL` lives in `App/Resources/Info.plist`. Shipping auto-updates requires release signing, a hosted appcast, and notarization credentials in your release environment.

---

## License

Apache License 2.0 — see [`LICENSE`](LICENSE).
