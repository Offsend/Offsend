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
No. Ignore files are the primary exclusion layer; hooks are defense-in-depth on supported operations; content scanning is a final check. It does not replace the editor’s own permission model.

### What does Offsend cover vs not cover?

| Covers | Does not cover |
| --- | --- |
| Shared AI context boundary in `.offsend.yml` (committed with the repo) | Network / process sandbox or “agent escape” containment |
| Materialized AI ignore files + drift detection | Org-wide policy across every repository |
| Content scan for secrets/credentials (`check`, hooks, CI) | Zero-day discovery, privilege escalation, lateral movement in infra |
| Prompt / read / shell / MCP **args** / Cursor subagent gates | Ungated Claude subagents, cloud agent sessions |
| MCP **response** sealing on Cursor/Claude (`context.mcp.responses: seal`); seal-for-agents read copies | Responses without active sealing (`observe`/`warn`, older hook install); missing keys safely withhold secret-bearing responses but stop that tool result |
| Local agent-history audit / scrub after a leak | Replacing the editor’s own permission model |

Credentials in agent context are leverage for further tool use (read, shell, MCP), not only a privacy leak. Prefer `offsend protect` + ignore files first; hooks are defense-in-depth. Details: [what hooks cover / do not cover](cli.md#what-hooks-cover).

**Does `offsend show` read file contents?**  
No for path exposure — paths and ignore rules only. Optional sections may report MCP inventory, transcript *counts*, and ignore drift. Content scanning of paths is `offsend check`; of agent history is `offsend history audit` or `offsend show --scan-history` / `context.history.scan_in_show`.

**Which platforms?**  
App: macOS 13+. CLI: macOS and Linux (x86_64 / arm64). Action: Linux and macOS runners.

**Which AI tools?**  
Coding assistants: Claude Code, Codex, Cursor, Windsurf (CLI prompt hooks + ignore files). Extension chats: ChatGPT, Claude, Gemini, Grok, Perplexity, DeepSeek. Multi-tool support exists so one committed policy can be enforced wherever a teammate opens the repo — not because switching editors is the main goal.

**Can Offsend check prompts before they reach an AI editor?**  
Yes. After clone or init, `offsend sync` installs git + detected AI-editor hooks. For a specific editor: `offsend hook install --target cursor` (or `claude`, `windsurf`, `codex`, `all`). Default install also enables read, shell, MCP, and (Cursor) subagent gates.

**Are AI-editor hooks a hard block on every way to read a file?**  
No. They are defense-in-depth on known editor paths (prompt, `@file`, Read/Edit/Write, shell, MCP tool **args** + **responses**, Cursor subagent tasks). Prefer `offsend protect` / AI ignore files first so secrets never enter context. With `context.mcp.responses: seal`, responses are sealed when a key is available; without a key, secret-bearing responses are withheld instead of passed through. Other gaps remain: Claude subagents, cloud sessions, and secrets already written to local transcripts (`offsend history audit` / `scrub`). See [what hooks cover / do not cover](cli.md#what-hooks-cover).

**Can the agent keep working when a read is denied because of secrets?**  
Yes, with seal-for-agents: set `context.read.on_secret: seal` (plus a seal key via `offsend keygen --default`). The read-gate still denies the original file but hands the agent a sealed copy where secrets are `{{TYPE:v1.…}}` tokens. The user restores agent outputs with `offsend unseal`; the shell-gate asks before the agent runs `unseal` itself.

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
