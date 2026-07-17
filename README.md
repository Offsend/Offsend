<h1 align="center"><code>*}• Offsend</code></h1>

<p align="center">
  See and fix what AI tools can read.<br>
  One <code>.offsend.yml</code> defines what stays out of AI context — synced to every AI ignore file.<br>
  Local-first checks for terminals, CI, and macOS — before Claude Code, Codex, Cursor, or Windsurf see your context.
</p>

<p align="center">
  <a href="https://offsend.io">Website</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="docs/README.md">Docs</a> ·
  <a href="https://check.offsend.io">Check</a> ·
  <a href="https://offsend.io/extension">Extension</a>
</p>

<p align="center">
  <a href="https://github.com/Offsend/Offsend/actions/workflows/ci.yml"><img src="https://github.com/Offsend/Offsend/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Offsend/Offsend/releases"><img src="https://img.shields.io/github/v/release/Offsend/Offsend?label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/Linux-CLI%20(x86_64%20%7C%20arm64)-FCC624?logo=linux&logoColor=black" alt="Linux CLI">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/platform-macOS%2013%2B-000000?logo=apple&logoColor=white" alt="Platform"></a>
  <img src="https://img.shields.io/badge/local--first-yes-2ea44f" alt="Local-first">
  <a href="https://radar.offsend.io/participants/"><img src="https://radar.offsend.io/badge.svg" alt="AI Context Reviewed" height="20"></a>
</p>

<p align="center">
  <img src="assets/cli.gif" alt="Offsend CLI: see what AI tools can read" width="100%">
</p>

---

`.gitignore` protects Git. It does not define what AI tools should read.

Offsend is that missing layer: audit what AI tools can see, describe what they must not see in one `.offsend.yml`, and let `offsend sync` maintain `.cursorignore`, `.claudeignore`, `.aiexclude`, and the rest for you. Everything runs **locally** — no cloud account, no upload of file contents for analysis. The CLI is free and open source.

No install yet? [Scan a public GitHub repo with Check](https://check.offsend.io).

## What Offsend does

| Layer | Job | Commands |
| --- | --- | --- |
| **Boundary** | Show sensitive paths AI can see; keep them out via `.offsend.yml` synced to all AI ignore files | `show`, `protect`, `ignore`, `sync` |
| **Content** | Scan files, staged diffs, or stdin for secrets and custom terms | `check` |
| **Runtime** | Gate prompts, file reads, shell, MCP calls, and Cursor subagents in the editor; audit local agent history | `hook install`, `history` |

Defense-in-depth: ignore files first, then hooks. Hooks do not replace keeping secrets out of the workspace — see [what hooks cover](docs/cli.md#what-hooks-cover).

## Quick Start

```bash
curl -fsSL https://install.offsend.io/cli | bash
offsend doctor
offsend show
```

When sensitive paths are exposed:

```text
Scanned: /path/to/project
3 files would be sent to AI tools (2 required, 1 recommended):

✗ Environment files [required]
    Ignore .env and .env.* files.
  - .env

✗ PEM keys [required]
    Ignore PEM key files.
  - server.pem
```

Recommended onboarding:

```bash
offsend init --template node   # .offsend.yml + first sync + baseline check
offsend protect                # promote exposed paths to .offsend.yml, sync AI ignore files
offsend show                   # verify boundary (+ MCP / history hints)
offsend hook install           # git pre-commit + AI editor gates
```

Rules live in `.offsend.yml` — commit it and the whole team gets the same boundary. AI ignore files are generated artifacts and stay out of git by default (`ignore.commit: false`).

Other installs: [CLI docs → Install](docs/cli.md#install) · macOS app: `brew install --cask offsend/tap/offsend`

## Pick your tool

| Tool | Best for |
| --- | --- |
| **[CLI](docs/cli.md)** | Repos, git hooks, AI-editor gates, CI (macOS & Linux) |
| **[macOS app](docs/macos-app.md)** | Safe Paste, drag-and-drop prep, watched folders |
| **[Check](https://check.offsend.io)** | One-off scan of a public GitHub repo |
| **[GitHub Action](https://offsend.io/github-action)** | Same checks on every PR / push |
| **[Extension](https://offsend.io/extension)** | Mask secrets in ChatGPT, Claude, Gemini, and similar chats |

## CLI essentials

| Command | Purpose |
| --- | --- |
| `offsend show` | Sensitive paths visible to AI (+ MCP inventory, agent-history hint) |
| `offsend protect` | Promote exposed paths to `.offsend.yml` and sync AI ignore files |
| `offsend sync` | Materialize `.offsend.yml` rules into every AI ignore file |
| `offsend check` | Scan contents (files, `--staged`, stdin, or editor hook JSON) |
| `offsend hook install` | Git pre-commit + prompt / read / shell / MCP / subagent gates |
| `offsend history audit` | Find secrets already written into local Cursor/Claude transcripts |
| `offsend doctor` | Verify install, hooks, MCP policy, next setup steps |

```bash
# CI
- uses: Offsend/ai-hygiene@v1
  with:
    fail-on: block
```

Full reference: **[docs/cli.md](docs/cli.md)** · Config: **[docs/configuration.md](docs/configuration.md)**

## Privacy

- Scanning and audits run on your machine.
- Offsend does not upload scanned file contents, prompts, clipboard payloads, or findings.
- Check only analyzes a GitHub repo you choose to scan online.

Details and vulnerability reporting: [docs/faq.md](docs/faq.md) · [SECURITY.md](SECURITY.md).

## Docs

| Doc | Description |
| --- | --- |
| [docs/README.md](docs/README.md) | Documentation index |
| [docs/cli.md](docs/cli.md) | Commands, flags, exit codes, AI-editor hooks |
| [docs/configuration.md](docs/configuration.md) | `.offsend.yml` reference (`check`, `ignore`, `hooks`, `context`) |
| [docs/macos-app.md](docs/macos-app.md) | Desktop app, Free vs Pro, App vs CLI |
| [docs/faq.md](docs/faq.md) | FAQ |
| [.offsend.yml.example](.offsend.yml.example) | Annotated config starter |

## Contributing

Bug reports, feature requests, docs improvements, and PRs are welcome.

- Open an [issue](https://github.com/Offsend/Offsend/issues)
- Read [SECURITY.md](SECURITY.md) before reporting a vulnerability
- Keep changes focused and explain the user problem they solve

## License

Apache 2.0 — see [LICENSE](LICENSE).
