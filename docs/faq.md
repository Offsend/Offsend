# FAQ

**Does Offsend upload my code?**  
No. App and CLI scan locally. [Check](https://check.offsend.io) only analyzes a GitHub repo you choose online.

**Is the CLI free?**  
Yes — terminal, git hooks, AI-editor hooks, scripts, and CI.

**Does Offsend replace `.gitignore`?**  
No. `.gitignore` controls Git; Offsend controls AI context. Rules live in `.offsend.yml`, and `offsend sync` maintains the AI ignore files (`.cursorignore`, `.claudeignore`, …) from it. When `ignore.commit` is `false` (default), sync also adds those AI ignore paths to `.gitignore` so they stay untracked. Commit `.offsend.yml` so the team shares one boundary — see [team setup](team.md).

**Do I edit `.cursorignore` / `.claudeignore` by hand?**  
You can — lines outside the offsend managed block are preserved. Prefer `offsend ignore <pattern>` or editing `ignore.patterns` in `.offsend.yml` (seeded with AI privacy defaults at `init`), then `offsend sync`, so the rule is shared across every tool. If ignore files drift from `.offsend.yml`, `offsend doctor`, `offsend show`, and `offsend check --policy` report it; CI with `fail-on: block` fails on that drift.

**I upgraded Offsend and CI started failing on paths that used to pass — what now?**  
Built-in detectors can grow across releases; your committed `ignore.patterns` does not auto-merge new defaults. Prefer `offsend ignore --merge-defaults`, then commit `.offsend.yml`. Or `offsend show` → `protect` → `sync` for paths currently on disk. Details: [configuration → Upgrading](configuration.md#upgrading-offsend-cli-existing-offsendyml).

**Is Offsend a secret scanner?**  
Partly. It also checks AI-context boundaries: what AI tools can read, whether ignore rules exist or have drifted, MCP exposure, and local agent history.

**What are the default enforcement modes?**  
Adoption-friendly locally, strict for secrets and CI:

| Surface | Default behavior |
| --- | --- |
| `offsend init` baseline `check` | Advise-only (does not fail init) |
| Path / ignore policy locally | Warn via `doctor` / `show`; sync to fix |
| Critical secrets / credentials in `check` | Blocking findings |
| CI (`fail-on: block`) | Fails on blocking secrets, failed policy checks, and managed ignore drift |
| AI-editor hooks | Default soft-block; teams can choose advise or block |

Teams tune the shared baseline with `offsend init --template …` and `check.detectors.disable` — not by maintaining separate ignore files per engineer. See [configuration](configuration.md).

**Is Offsend a sandbox or agent permission system?**  
No — and yes, optionally. Ignore files and hooks are the primary layers; they are not kernel enforcement. For reads/egress that hooks cannot decide from command text, set [`sandbox.enabled: true`](configuration.md#sandbox): `offsend sync` materializes each editor's own sandbox (or a [nono](https://nono.sh) profile when installed), and `doctor` / `check --policy` verify drift. Offsend **writes and checks** that config; it does not wrap a running agent. Install nono yourself (`brew install nono`) when you want it for Claude Code / Codex.

**Can an agent weaken `.offsend.yml` after hooks are installed?**
Not in the direction that matters. Without a trusted snapshot, hooks read the live workspace policy but honor only the fields that tighten a gate — `check.exclude`, `detectors.disable`, and enforcement modes below the built-in default are ignored until you approve them. After reviewing the file, run `offsend policy trust` yourself in an interactive terminal. Offsend stores only its hash outside the workspace; later edits, deletion, or invalid YAML make editor gates fail closed until you review and trust again. `sync` never approves policy changes, and agent-shell attempts to run `policy trust` / `forget` or to write `.offsend.yml` are denied.

### What does Offsend cover vs not cover?

| Covers | Does not cover |
| --- | --- |
| Shared AI context boundary in `.offsend.yml` (committed with the repo) | Replacing the editor’s own permission UI / allowlists |
| Materialized AI ignore files + drift detection | Org-wide policy across every repository |
| Content scan for secrets/credentials (`check`, hooks, CI) | Zero-day discovery, privilege escalation, lateral movement in infra |
| Prompt / read / shell / MCP **args** / Cursor subagent + Grep gates | Ungated Claude subagents; Cursor Grep without seal; cloud agent sessions |
| Optional OS sandbox config (`sandbox.enabled`) — generate + verify; `offsend run` launches via nono when configured | Cursor IDE process wrap; Windsurf sandbox; silent `policy trust` |
| User-approved policy snapshot outside the workspace | Containing arbitrary IDE tasks, Git helpers, venv discovery, or host automation outside static shell argv |
| MCP **response** sealing on Cursor/Claude (`context.mcp.responses: seal`); seal-for-agents read copies | Responses without active sealing (`observe`/`warn`, older hook install); missing keys safely withhold secret-bearing responses but stop that tool result |
| Local agent-history audit / scrub after a leak | Undoing secrets already sent to a remote/cloud agent |

Credentials in agent context are leverage for further tool use (read, shell, MCP), not only a privacy leak. Prefer `offsend protect` + ignore files first; hooks are defense-in-depth; sandbox when you need kernel egress denial. Details: [what hooks cover / do not cover](cli.md#what-hooks-cover), [sandbox](configuration.md#sandbox).

**Does `offsend show` read file contents?**  
No for path exposure — paths and ignore rules only. Optional sections may report MCP inventory, transcript *counts*, and ignore drift. Content scanning of paths is `offsend check`; of agent history is `offsend history audit` or `offsend show --scan-history` / `context.history.scan_in_show`.

**Which platforms?**  
App: macOS 13+. CLI: macOS and Linux (x86_64 / arm64). Action: Linux and macOS runners.

**Which AI tools?**  
Coding assistants: Claude Code, Codex, Cursor, Windsurf (CLI prompt hooks + ignore files). Extension chats: ChatGPT, Claude, Gemini, Grok, Perplexity, DeepSeek. Multi-tool support exists so one committed policy can be enforced wherever a teammate opens the repo — not because switching editors is the main goal.

**Can Offsend check prompts before they reach an AI editor?**  
Yes. After clone or init, `offsend sync` installs git + detected AI-editor hooks. For a specific editor: `offsend hook install --target cursor` (or `claude`, `windsurf`, `codex`, `all`). Default install also enables read, shell, MCP, (Cursor) subagent, and (Cursor) Grep gates.

**Can the agent keep working when a read is denied because of secrets?**  
Yes, with seal-for-agents: set `context.read.on_secret: seal` (plus a seal key via `offsend keygen --default`). The read-gate still denies the original file but hands the agent a sealed copy where findings are `{{TYPE:v1.…}}` tokens. The user restores agent outputs with `offsend unseal`; the shell-gate blocks (default `context.shell.mode: deny`) or asks (`mode: ask`) before the agent runs `unseal` itself. Seal / MCP-seal scans ignore `check.detectors.disable` so enabled detector classes and custom dictionaries cannot silently remain plaintext; fuzzy `highEntropyString` remains excluded. `doctor` reports this policy difference as `seal-detector-gap`. Large, wrapped, and multiple base64/hex blobs in files the agent reads (including terminal transcripts) are decode-probed; scan-budget overflow denies/withholds instead of allowing an unscanned tail.

**Are AI-editor hooks a hard block on every way to read a file?**
No. They are defense-in-depth on known editor paths (prompt, `@file`, Read/Edit/Write, shell, MCP tool **args** + **responses**, Cursor subagent tasks, Cursor Grep under seal). Prefer `offsend protect` / AI ignore files first. For enumeration/egress that hooks cannot decide from command text, use [`sandbox.enabled`](configuration.md#sandbox). Other gaps remain: Claude subagents, cloud sessions, renamed copies without secret-shaped content, and secrets already in local transcripts (`offsend history audit` / `scrub`). See [what hooks cover / do not cover](cli.md#what-hooks-cover).

**Secrets already landed in local agent transcripts — what then?**  
```bash
offsend history audit
offsend history scrub --apply
offsend protect && offsend sync
```
Close active agent sessions before `--apply`. Details: [cli.md → Agent history](cli.md#agent-history).

**Where is the full CLI documentation?**  
[cli.md](cli.md) (commands, flags, exit codes). Project config: [configuration.md](configuration.md). Team onboarding: [team.md](team.md).

## Privacy (detail)

- File and clipboard scanning runs locally.
- Project audits inspect paths and ignore rules locally.
- Offsend does not upload scanned file contents, prompts, clipboard payloads, findings, or detected values.
- Restore mappings are encrypted on disk; the key is stored in Keychain (macOS).
- Optional local AI models run on your Mac.
- No cloud account is required.

Vulnerability reports: [SECURITY.md](../SECURITY.md).
