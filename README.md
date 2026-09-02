<p align="center">
  <img src="apps/macos/assets/image.png" alt="Offsend — one .offsend.yml defines your AI context boundary" width="100%">
</p>

<p align="center">
  Agent keeps working. Secrets become tokens, not plaintext in the model.
</p>

<p align="center">
  <a href="https://offsend.io">Website</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#seal">Seal</a> ·
  <a href="#offsend-and-gitguardian">vs GitGuardian</a> ·
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

---

After install, **user-level** Cursor and Claude hooks on this machine seal secret-bearing reads and MCP responses (`{{TYPE:v1.…}}` tokens). No git remote and no `.offsend.yml` required. That is defense-in-depth, not a guarantee — cloud sessions and editors without those hooks are outside it. Windsurf and Codex are covered from a repo policy (`offsend sync`), not from `setup`.

Own the repo → `offsend init` writes that policy to git. GitHub → CI fails a PR that would expose secrets. Everything runs **locally**.

No install yet? [Scan a public GitHub repo with Check](https://check.offsend.io).

## What Offsend does

| Layer | When | Job |
| --- | --- | --- |
| **Machine** | Once per laptop (`install` / `setup`) | Seal key + user-level Cursor/Claude hooks. Agent works; plaintext stays out of context |
| **Repo** | When you own it (`init`) | Team policy in `.offsend.yml` — ignore rules, seal, policy checks, git pre-commit + post-merge |
| **CI** | When there is GitHub | `check --policy` fails on secrets / ignore drift — not on missing git or editor hooks on the runner |

## Quick Start

```bash
curl -fsSL https://install.offsend.io/cli | bash   # also runs `offsend setup`
offsend doctor                                     # Machine / Repository / CI — no YAML needed
```

See it in Cursor or Claude. Write `/tmp/offsend-try.env`:

```text
# offsend:ignore-next-line
DATABASE_URL=postgres://admin:sk-offsend-demo-123456789@db.internal/prod
```

Ask the agent: `Read /tmp/offsend-try.env and say which database and user it uses.` The password becomes `{{PASSWORD:v1…}}`; host and user stay. Copy the reply and run `offsend unseal`.

### Your repo (team policy)

```bash
offsend init --template node       # short .offsend.yml: seal + policy + pre-commit/post-merge
git add .offsend.yml && git commit -m "Add AI context policy"
```

### GitHub (third layer)

```yaml
# fail the PR when secrets or managed ignore drift appear
- uses: Offsend/ai-hygiene@v1
  with:
    fail-on: block
    policy: true
```

Teammates run `offsend sync` after clone to materialize ignore files and git hooks. Full walkthrough: [Add Offsend to a team repo](docs/team.md).

### Already leaked into local agent history?

```bash
offsend history audit
offsend history scrub --apply      # close agent sessions first
```

Other installs: [CLI docs → Install](docs/cli.md#install) · macOS app: `brew install --cask offsend/tap/offsend`

## Developing

- **Rust CLI / core** (repo root): `cargo build -p offsend-cli` · `cargo test --workspace` — portable library lives in `crates/` (`offsend-detect`, `offsend-policy`, `offsend-seal`, `offsend-ffi`)
- **macOS app**: `./scripts/app/bootstrap.sh` then open `apps/macos/Offsend.xcworkspace` (Document/AI/UI stay Swift; see [docs/macos-app.md](docs/macos-app.md#rust-vs-swift-ownership))
- **Scripts**: lowercase `scripts/{app,cli,ci,ffi,release,server,site}/` (compat shim: `scripts/install.sh` → `scripts/cli/install.sh`)
- **Scan API**: `server/`

## Seal

MCP tools and file reads can put secrets into model context. **Seal** swaps those values for reversible `{{TYPE:v1.…}}` tokens — the agent keeps working; plaintext stays out. Restore with `offsend unseal`.

```text
# offsend:ignore-next-line
DATABASE_URL=postgres://admin:secret@db.internal/prod
DATABASE_URL=postgres://admin:{{PASSWORD:v1…}}@db.internal/prod
```

Remove the secret, not the useful structure. This is the machine default after `setup` (no YAML). `offsend init` writes the same into `.offsend.yml` for the team. Without a key, secret-bearing MCP output is **withheld**, not passed through.

```bash
offsend setup                 # key + user hooks (install already does this)
offsend unseal                # copy the agent's {{TYPE:v1.…}} tokens, then run this
```

Depth: [MCP-response-gate](docs/cli.md#mcp-response-gate-on-by-default) · [configuration](docs/configuration.md#contextmcp).

## Offsend and GitGuardian

Offsend seals secrets **on your machine** so the agent can keep working. [GitGuardian ggshield](https://docs.gitguardian.com/) AI hooks **block** and scan in their cloud — without their API key they **fail open**.

| | Offsend | ggshield AI hooks |
| --- | --- | --- |
| Where the scan runs | Local. No GitGuardian account | GitGuardian cloud. Needs their API key |
| Missing key / scan down | Secret-bearing MCP output is **withheld**; seal without a key does not pass plaintext | **Fail-open** if you are not logged in |
| Hit on a secret | **Seal** — `{{TYPE:v1.…}}` tokens; the agent keeps working; you restore with `offsend unseal` | **Block** |
| Team boundary in git | `.offsend.yml` (ignore + hooks + CI) | Their ignore / dashboard, not an Offsend policy file |
| Hook files | **Merges** into existing Cursor/Claude configs; does not remove ggshield | `ggshield install -t cursor` (same files for Claude Code, Codex, Copilot) |
| Copilot / Windows | No Copilot runtime; CLI is macOS and Linux | Copilot and Windows |

Offsend is not trying to match detector count. The job is local seal, a committed AI-context boundary, and fail-closed when a secret would otherwise reach the model.

**Both installed?** Keep both. `offsend setup` / `hook install` add Offsend’s managed entries and leave foreign hooks (including ggshield) in place. Offsend is not an uninstaller.

## Pick your tool

| Tool | Best for |
| --- | --- |
| **[CLI](docs/cli.md)** | Repos, git hooks, AI-editor gates, CI (macOS & Linux) |
| **[macOS app](docs/macos-app.md)** | Safe Paste, drag-and-drop prep, watched folders |
| **[Check](https://check.offsend.io)** | One-off scan of a public GitHub repo |
| **[GitHub Action](https://offsend.io/github-action)** | Fail PRs on secrets, exposed paths, or ignore drift |
| **[Extension](https://offsend.io/extension)** | Mask secrets in ChatGPT, Claude, Gemini, and similar chats |

## CLI essentials

| Command | Purpose |
| --- | --- |
| `offsend setup` | Once per machine: seal key + user-level Cursor/Claude hooks |
| `offsend doctor` | CLI, key, user hooks; with a repo YAML also git hooks, ignore drift, config-lint |
| `offsend init` | Write team `.offsend.yml` (seal + policy + pre-commit / post-merge) |
| `offsend show` | Sensitive paths visible to AI |
| `offsend sync` | Apply `.offsend.yml`: ignore files, git hooks, optional project editor hooks |
| `offsend protect` | Promote exposed paths to `.offsend.yml` and sync ignore files |
| `offsend check` | Scan contents (files, `--staged`, stdin, or editor hook JSON) |
| `offsend seal` / `unseal` | Replace secrets with tokens / restore plaintext |
| `offsend history audit` | Find secrets already in local Cursor/Claude transcripts |

## Privacy

- Scanning and audits run on your machine.
- Offsend does not upload scanned file contents, prompts, clipboard payloads, or findings.
- Check only analyzes a GitHub repo you choose to scan online.

## Docs

Essentials above; reference depth in `docs/`:

| Doc | Description |
| --- | --- |
| [docs/README.md](docs/README.md) | Index and suggested reading path |
| [docs/team.md](docs/team.md) | Add Offsend to a team repository |
| [docs/cli.md](docs/cli.md) | Commands, flags, exit codes, AI-editor hooks (incl. MCP seal) |
| [docs/configuration.md](docs/configuration.md) | `.offsend.yml` reference (`check`, `ignore`, `hooks`, `context`, `sandbox`) |
| [docs/faq.md](docs/faq.md) | FAQ, coverage limits, privacy, vs GitGuardian |
| [docs/macos-app.md](docs/macos-app.md) | Desktop app, Free vs Pro, App vs CLI |
| [.offsend.example.yml](.offsend.example.yml) | Annotated config starter |
| [.offsend.full.yml](.offsend.full.yml) | Full `.offsend.yml` key catalog |
| [docs/positioning.md](docs/positioning.md) | ICP and messaging (internal) |
| [SECURITY.md](SECURITY.md) | Vulnerability reporting |

## Contributing

Bug reports, feature requests, docs improvements, and PRs are welcome.

- Open an [issue](https://github.com/Offsend/Offsend/issues)
- Read [SECURITY.md](SECURITY.md) before reporting a vulnerability
- Keep changes focused and explain the user problem they solve

## License

Apache 2.0 — see [LICENSE](LICENSE).
