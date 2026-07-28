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
| AI-editor gates (prompt, read, shell, MCP args/responses, Cursor subagent) | Local editor hooks invoking the installed CLI directly |
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
3. Prompt / read / semantic write / shell / MCP / subagent gates on supported editors
4. Git pre-commit + CI

Offsend does not execute repo-local `.offsend/hooks/*.sh` files. Local editor configs prefer the install-time CLI path and fall back to `offsend` on `PATH`; published configs use `PATH`. Legacy managed wrappers are migrated and removed by `offsend sync`.

### Workspace trust handoff

Workspace configuration can be executable infrastructure: editor hooks, task runners, Git helpers, virtual environments, and other host components may act on files an agent can write. Offsend is not a process sandbox and cannot contain those host actions.

Cursor/Claude installs use pre-tool hooks to deny direct agent Edit/Write operations against high-confidence executable trust surfaces: editor hook configs, `.vscode/tasks.json` / `launch.json`, any path inside a Git directory, global Git config, shell/direnv startup files, SSH directories, launch agents/daemons, Python startup hooks, and Offsend's own policy and trust snapshots. Rules match on path shape, so subdirectory, nested-repository, home-directory, symlinked, and case/Unicode variants of the same file classify identically. Direct shell path references are denied too. Editor settings that mix preferences with execution (`.vscode/settings.json`, `*.code-workspace`) are denied only when the content introduces an execution-sensitive key. Virtualenv interpreters are observe-only because blocking them has high false-positive risk.

Editor matchers follow each vendor's documented semantics: Claude matches plain names exactly (so every writing tool is named explicitly), and Cursor's file-tool set includes `Delete`, which is gated alongside writes. Because Cursor does not publish a `tool_input` schema for file tools, the gate classifies every path-shaped value in a payload rather than depending on one key name, and applies the strictest outcome when a call names several files. Unrecognized payloads ask rather than deny so an editor schema change cannot block every write; on Cursor, which accepts but does not enforce `ask` for `preToolUse`, those decisions become deny instead of silently passing.

The shell-gate also recognizes static Git invocations and denies mutations or per-command overrides of execution-sensitive keys, including hooks, aliases, credential/diff/merge/filter helpers, diff/merge tools, textconv and trailer commands, editors, pagers, includes, template directories, `protocol.*.allow`, and submodule update commands. Read-only queries and ordinary identity/format settings are allowed. This parser does not claim full shell semantics: dynamic construction, generated scripts, and custom binaries can hide equivalent operations.

All shell classifiers share one lexer and one command extractor, so quoting (`cat '.git'/config`), redirection (`printf x >.envrc`), launcher wrappers (`env`, `sudo`, `timeout`, `nice`, `xargs`, `stdbuf`, `nohup`), inline shell scripts (`bash -c '…'`, `env -S '…'`), and interpreter payloads (`python3 -c '…'`, `node -e '…'`) reach the same verdict as the direct form. Adjacent static string concatenations in interpreter payloads (`"c"+"ert"+".pem"`) are reconstructed before path classification, and committed `ignore.patterns` make generic protected paths shell-sensitive. Nested scripts are followed a bounded number of levels; beyond that the payload is treated as opaque. Quoted text passed as data — `printf '%s' "git config …"` — is still not an invocation. A command that trips several gates reports every finding at once instead of one per round-trip.

The shell-gate does not read stdout. Content gates decode-probe contiguous and commonly wrapped base64/hex runs when the agent later reads terminal artifacts or other buffers, so encoded secret dumps can still deny/seal. Probe-budget overflow denies/withholds instead of allowing an unscanned tail. Runtime encoding (`chr()`, `eval`, unresolved variables) and renamed copies without detectable content remain residual; keep secrets off disk as the primary control.

Recognized Docker, Podman, nerdctl, containerd, BuildKit, and macOS VM-manager (Colima, Lima, OrbStack) operations are classified by side effect. Getting a shell inside a Docker-backing VM is denied because those VMs mount the host home directory. Container execution/attachment, elevated options, daemon plugins, direct known Unix-socket access, and explicit daemon endpoints are denied because the host daemon operates outside the agent sandbox. Lower-risk mutations require confirmation and diagnostics are allowed. This does not mediate MCP-based daemon clients, custom protocols/binaries, dynamically generated commands, undiscovered sockets, or remote contexts hidden outside static argv.

Static environment mutations are classified before shell execution. Relative/workspace/temporary `PATH`, dynamic-loader variables (`DYLD_*`, `LD_*`), exported shell functions (`BASH_FUNC_*`), execution-sensitive `GIT_*`, and interpreter/shell startup injection variables (`PYTHON*`, `NODE_*`, `RUBY*`/`GEM_*`, `PERL5*`, `CLASSPATH`, Java tool options) are denied. Variables that merely name a helper program — `EDITOR`, `VISUAL`, `PAGER`, `MANPAGER`, `SHELL`, `LESSOPEN` — are judged by value: a plain program asks for confirmation, while a shell fragment or a program under a workspace-writable path is denied. Lower-risk system `PATH` and configuration-home overrides require confirmation. Process APIs, parent-process state, command substitution, generated scripts, and unknown launchers remain outside static command analysis.

Gates that carry hard denials — write, shell, MCP, subagent — are installed fail-closed on Cursor, so a hook process that crashes or times out blocks the operation instead of dropping the denial. The read-gate stays fail-open by design: it is friction against reading secrets, and a broken hook blocking every file read costs more than it protects.

Post-write hooks add a metadata-only provenance trail for classified trust surfaces changed through editor file tools. The user-local ledger is `0600`, rotates at 512 KiB, and stores relative paths and hashes—not file contents or absolute repository paths. Entries are hash-chained, and the log's length and tail hash are kept in a companion `0600` anchor file, so removing or rewriting an entry — including cutting the log at either end, which the chain alone cannot see — is reported rather than silently shortening the record. Both files are local: an attacker who rewrites the log and the anchor together defeats this. `offsend doctor` summarizes the last 30 days and warns when writes to denied surfaces reached disk. This does not attribute writes made through shell commands, external processes, cloud agents, or editors that skip the hook.

For Offsend's own runtime policy, `offsend policy trust` stores a SHA-256 snapshot outside the workspace after explicit interactive approval. If `.offsend.yml` later changes, disappears, or becomes invalid, editor hooks fail closed until the user reviews and trusts it again. Until a snapshot exists, gates apply only the policy fields that cannot make a gate more permissive than its built-in default, so removing the snapshot does not restore an agent's ability to loosen policy. `sync`, `protect`, and `hook install` never refresh trust automatically; agent-shell attempts to run `policy trust` or `policy forget` are denied.

The snapshot is deliberately byte-sensitive: comments and formatting changes also require re-trust. This favors an auditable trust boundary over convenience.

Known residual gaps (surfaced by `offsend doctor` through `hook-coverage-gaps`, `git-config-invocation-gate`, `privileged-daemons`, and `environment-invocation-gate`) include dynamic Git/daemon/environment operations hidden behind `eval`, process APIs, variables, generated scripts, MCP tools, custom binaries, remote contexts, undiscovered sockets, or already-poisoned parent environments; editor paths not mediated by a supported pre-tool hook; ungated Claude subagents; some Cursor open-tab paths; cloud agent sessions; and secrets already written to local transcripts — use `offsend history audit` / `scrub` for the last case. Use patched editor versions (Cursor 3.0 or newer for the workspace-hook issue described in CVE-2026-48124). Details: [docs/cli.md → What hooks cover](docs/cli.md#what-hooks-cover).

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
