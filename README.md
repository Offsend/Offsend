<div align="center">

# ```*}• Offsend```

**Paste into ChatGPT, Slack, and internal tools without leaking secrets.**  
**Keep an eye on `.cursorignore` and friends in the repos you work in.**

macOS menu bar app. Masks sensitive clipboard text before paste, audits project folders for AI ignore rules, and can watch folders in the background and ping you when something looks off.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)

</div>

<p align="center">
  <img src="assets/demo.gif" alt="Check Directory: drop a folder, review status, turn on background watch" width="720">
</p>

---

## What it does

**Safe Paste** (`⌘⇧V`) — checks the clipboard, masks tokens, emails, keys, and similar, then pastes or copies the safe text. **Restore** (`⌘⇧R`) puts the originals back when you need them. Mappings stay encrypted on disk; the key is in Keychain.

**Check Directory** — pick a project folder (drop, Choose Folder, or paste a path). You get PASS / WARNING / FAIL, a list of missing ignore files, and sensitive paths that exist on disk but are not ignored. File contents are not read and nothing is uploaded.

**Directory monitoring** — add folders in Settings (or turn on *Watch in background* from the check window). Offsend re-audits when ignore files or relevant paths change. Optional notification if status gets worse. Free: one watched folder; Pro: no limit.

Hotkeys are remappable in Settings.

---

## When it’s useful

- Pasting logs or stack traces into ChatGPT, Claude, or Copilot without shipping API keys.
- Slack or email: share a snippet without raw customer IDs or internal hostnames.
- New repo in Cursor: quick check that `.cursorignore` (and the rest) exist before you rely on the agent.
- Someone committed `secrets.env` but did not update ignores — background watch catches it.
- A few repos on one machine — status in the menu bar instead of opening each project by hand.

---

## Check Directory (detail)

Works with Cursor, Copilot, Claude Code, Windsurf, and the usual ignore filenames (`.cursorignore`, `.copilotignore`, `.aiexclude`, …).

**Free** — Cursor-required files + common sensitive patterns (`.env*`, keys, certs, …).

**Pro** — more tools in the audit, recommended rules, **Fix it** to create or patch ignore files in one go.

A pattern like `.env*` only shows up as a problem if that kind of file actually exists and is not covered by your ignores. Empty trees are not nagged for rules you do not need yet.

---

## Privacy

Masking, restore, and directory checks run on the Mac only. Clipboard is touched on Safe Paste / Restore unless you enable optional clipboard monitoring in Settings. Counters in the app do not store prompt text, clipboard payload, or detected values. Directory audit uses paths and ignore rules, not file bodies.

Report security issues via [`SECURITY.md`](SECURITY.md).

---

## Install

Download from [Releases](https://github.com/Offsend/Offsend/releases), or build from source:

```bash
brew install tuist
./Scripts/bootstrap.sh
open Offsend.xcworkspace
```

Needs macOS 13+, Xcode 16, Tuist. macOS will ask for Accessibility (paste into the front app) and folder access for audits and watch.

---

## Built with

Swift macOS app. Most of the work happened in [Cursor](https://cursor.com/) — **Composer 2.5** for day-to-day UI and wiring, **Claude Opus 4.7–4.8** for bigger chunks and tests. Signing, permissions, and what ships are reviewed by hand.

---

## License

Apache 2.0 — see [`LICENSE`](LICENSE).
