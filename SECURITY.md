# Security Policy

Offsend prepares project, document, and clipboard data for use with AI tools entirely on your Mac. It does not send your clipboard or project files anywhere for detection, masking, or directory audits.

No cloud account. No server-side scanning. No "trust us".

What follows is the technical version of that promise.

## Local Processing

Detection, masking, restore, and risk scoring run locally in the macOS app. No prompt content or clipboard content is sent to remote services for those features.

## Network

Separate from the masking pipeline, the app may use HTTPS for **license** flows (pricing, activation; see `LicenseCore`) and **updates** via Sparkle (`SUFeedURL` in `App/Resources/Info.plist`). Those requests do not carry clipboard text or masked content from Safe Paste / Restore.

## Secret Handling

Secret detectors are treated as critical risk. Critical secrets default to a safe-version flow and do not expose a normal Paste Original action.

## Mapping Encryption

Placeholder mappings are encoded as JSON, encrypted with AES-GCM, and protected by a Keychain-backed 256-bit key.

## Permissions

Accessibility permission is used only to simulate paste into the active app. Without the permission, the app falls back to Mask & Copy.

## Logging

The app avoids logging clipboard content, detected values, masked text, and mappings. Debug logging must use synthetic data only.

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

If you believe you found a vulnerability in Offsend, please contact:

**support@offsend.io**

Please include:

- a short description of the issue
- steps to reproduce
- affected version or commit
- screenshots or logs if useful
- potential impact

I will try to acknowledge reports within 72 hours.

## Supported Versions

Offsend is early-stage software. Security fixes are applied to the latest public release only.

Please update to the latest version before reporting an issue.
