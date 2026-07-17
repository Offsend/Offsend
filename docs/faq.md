# FAQ

**Does Offsend upload my code?**  
No. App and CLI scan locally. [Check](https://check.offsend.io) only analyzes a GitHub repo you choose online.

**Is the CLI free?**  
Yes — terminal, git hooks, AI-editor hooks, scripts, and CI.

**Does Offsend replace `.gitignore`?**  
No. `.gitignore` controls Git. Offsend controls AI context: rules live in `.offsend.yml`, and `offsend sync` maintains the AI ignore files (`.cursorignore`, `.claudeignore`, …) from it.

**Do I edit `.cursorignore` / `.claudeignore` by hand?**  
You can — lines outside the offsend managed block are preserved. But the recommended flow is `offsend protect` or `offsend ignore <pattern>`, so the rule lands in `.offsend.yml` once and syncs to every tool.

**Is Offsend a secret scanner?**  
Partly. It also checks AI-context boundaries: what AI tools can read, whether ignore rules exist, MCP exposure, and local agent history.

**Does `offsend show` read file contents?**  
No for path exposure — paths and ignore rules only. Optional sections may report MCP inventory and transcript *counts*; content scanning is `offsend check` / `offsend history audit`.

**Which platforms?**  
App: macOS 13+. CLI: macOS and Linux (x86_64 / arm64). Action: Linux and macOS runners.

**Which AI tools?**  
Coding assistants: Claude Code, Codex, Cursor, Windsurf (CLI prompt hooks + ignore files). Extension chats: ChatGPT, Claude, Gemini, Grok, Perplexity, DeepSeek.

**Can Offsend check prompts before they reach an AI editor?**  
Yes. Install [AI-editor hooks](cli.md#ai-editor-hooks) with `offsend hook install --target cursor` (or `claude`, `windsurf`, `codex`, `all`). Default install also enables read, shell, MCP, and (Cursor) subagent gates.

**Are AI-editor hooks a hard block on every way to read a file?**  
No. They are defense-in-depth on known editor paths (prompt, `@file`, Read/Edit/Write, shell, MCP tool **args**, Cursor subagent tasks). Prefer `offsend protect` / AI ignore files first so secrets never enter context. Gaps remain: MCP **response** payloads, Claude subagents, cloud sessions, and secrets already written to local transcripts (`offsend history audit` / `scrub`). See [what hooks cover / do not cover](cli.md#what-hooks-cover).

**Where is the full CLI documentation?**  
[cli.md](cli.md) (commands, flags, exit codes). Project config: [configuration.md](configuration.md).

## Privacy (detail)

- File and clipboard scanning runs locally.
- Project audits inspect paths and ignore rules locally.
- Offsend does not upload scanned file contents, prompts, clipboard payloads, findings, or detected values.
- Restore mappings are encrypted on disk; the key is stored in Keychain (macOS).
- Optional local AI models run on your Mac.
- No cloud account is required.

Vulnerability reports: [SECURITY.md](../SECURITY.md).
