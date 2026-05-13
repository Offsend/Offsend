# Offsend

Offsend is a native macOS menu bar utility that masks sensitive data before it reaches AI tools or workplace apps.

## Requirements

- macOS 13 Ventura or later
- Xcode 16 or compatible command line tools
- Tuist

## Setup

```bash
brew install tuist
tuist install
tuist generate
open Offsend.xcworkspace
```

## Developer Commands

```bash
tuist test
tuist build
```

To produce a DMG from an existing signed `.app`, set `APP_PATH` and optional `DMG_PATH`, then run `Scripts/build_dmg.sh`. The full Developer ID export, DMG, notarization, and optional Sparkle signing flow lives in `.github/workflows/release.yml`; see `.github/RELEASE_SETUP.md` for secrets and one-time setup.

## Security

Responsible disclosure: see `SECURITY.md` in the repository root.

The `docs/` directory is intentionally **gitignored** for local or internal notes; it is not part of the published tree.

## Privacy Model

- Clipboard text is read only after a user action: Safe Paste or Restore.
- Detection, risk scoring, masking, and restore are local.
- Placeholder mappings are encrypted locally with a Keychain-backed key.
- Local counters do not include prompt content, clipboard content, detected values, active app names, or window titles.
- Clipboard monitoring is optional (Settings / menu bar). When enabled, assessment uses the same local-only detection pipeline; nothing is sent to cloud services for masking or restore.

## Main Flows

- `Cmd + Shift + V`: scan clipboard, show risk popup when needed, mask and paste or copy a safe version.
- `Cmd + Shift + R`: restore placeholders from local encrypted mappings.
- Settings: configure detectors, custom dictionaries, mapping TTL, privacy controls, hotkeys, launch at login, and license placeholder state.

## Release Notes

Sparkle is wired as a dependency and `SUFeedURL` is present in `App/Resources/Info.plist`. Release signing, appcast signing, notarization credentials, and Developer ID identity must be supplied by the release environment.
