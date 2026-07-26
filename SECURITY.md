# Security Policy

Offsend defines and enforces an AI context boundary on your machine: what coding agents may read, what to scan for secrets, and how to keep credentials out of model context.

Detection, masking, sealing, directory audits, ignore-file sync, git/AI-editor hooks, and agent-history audit/scrub run **locally**. Offsend does not upload scanned file contents, prompts, clipboard payloads, findings, or detected values for those features.

No cloud account is required for the app or CLI. No "trust us" with your source for analysis.

What follows is the technical version of that promise.

## Scope

This policy covers:

| Surface | Role |
| --- | --- |
| **CLI** (macOS / Linux) | Project boundary (`.offsend.yml`), content scan, hooks, seal/unseal, history |
| **macOS app** | Safe Paste, file/document prep, project audits, watched folders, local AI models |
| **GitHub Action** | CI checks against the same local rules (runner-side; no Offsend cloud scan of your private tree) |

Related products with different trust boundaries:

- **[Check](https://check.offsend.io)** — online scan of a **public** GitHub repo you explicitly choose
- **[Browser extension](https://offsend.io/extension)** — masks secrets in web chat UIs; see that product’s privacy notes

## Local Processing

| Capability | Where it runs |
| --- | --- |
| Secret / PII detection, risk scoring, masking | Local (app + CLI) |
| Safe Paste / Restore | Local (macOS app) |
| Path audits (`show` / `protect`) and ignore sync | Local — paths and ignore rules; `show` does not read exposed file contents |
| Content scan (`check`, pre-commit, CI) | Local / CI runner |
| AI-editor gates (prompt, read, shell, MCP args/responses, Cursor subagent) | Local hook wrappers calling the CLI |
| Seal / unseal (`{{TYPE:v1.…}}` tokens) | Local AES-GCM with a personal key |
| Agent history audit / scrub | Local Cursor / Claude transcripts on disk |
| Optional NER/PII models (macOS app) | On-device |

## Network

Separate from scanning and sealing, the macOS app may use HTTPS for:

- **License** flows (pricing, activation; see `LicenseCore`)
- **Updates** via Sparkle (`SUFeedURL` in `App/Resources/Info.plist`)
- **Optional product analytics** (TelemetryDeck) when the user opts in under Settings → Privacy — event names and coarse metadata only (e.g. risk level, counts); never clipboard text, prompts, file contents, or detected values

Those requests do not carry clipboard text, masked/sealed content, or scanned file payloads.

The CLI does not require network access for day-to-day protect / check / hook / seal workflows. Check and license purchase are opt-in product surfaces, not part of the local scan pipeline.

## Encryption & Keys

**Safe Paste mappings (macOS app)** — placeholder mappings are encoded as JSON, encrypted with AES-GCM, and protected by a Keychain-backed 256-bit key.

**Seal tokens (CLI / hooks)** — each sealed value uses AES-GCM with a fresh random nonce. Keys are personal and machine-local:

| Path | Purpose |
| --- | --- |
| `~/.offsend/seal.key` | Default key (`offsend keygen --default`) |
| `~/.offsend/keys/NAME.key` | Optional named keys |

Do not commit seal keys. Without a key, `context.mcp.responses: seal` and related seal paths **withhold** secret-bearing output rather than pass plaintext through.

Honest boundary: seal keeps plaintext out of model context and transcripts; it is not a sandbox against a local agent that can read your seal key.

## Secret Handling

Secret / credential detectors are treated as critical risk. In the macOS app, critical secrets default to a safe-version flow and do not expose a normal Paste Original action.

In the CLI and hooks, advice and notifications use **detector type names only** — never secret prefixes, suffixes, or values. `hook-debug.log` (when enabled) uses mode `0600`, refuses symlink targets, and redacts home paths in log fields.

## AI-editor Hooks

Hooks are **defense-in-depth**, not a hard perimeter or agent sandbox. Prefer:

1. No plaintext secrets in the workspace
2. Shared AI ignore rules in `.offsend.yml` (`offsend protect` / `sync`)
3. Prompt / read / shell / MCP / subagent gates on supported editors
4. Git pre-commit + CI

Known residual gaps (also surfaced by `offsend doctor` as `hook-coverage-gaps`) include ungated Claude subagents, some Cursor open-tab paths, cloud agent sessions, and secrets already written to local transcripts — use `offsend history audit` / `scrub` for the last case. Details: [docs/cli.md → What hooks cover](docs/cli.md#what-hooks-cover).

## Permissions (macOS app)

- **Accessibility** — used only to simulate paste into the active app. Without it, the app falls back to Mask & Copy.
- **Folder access** — used to audit and monitor directories the user selects.

## Logging

The app and CLI avoid logging clipboard content, prompt bodies, detected values, masked/sealed plaintext, and mappings. Debug logging must use synthetic data only. Local MCP activity logs record server/tool/outcome codes — not tool payloads.

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
