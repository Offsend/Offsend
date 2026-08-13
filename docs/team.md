# Add Offsend to a team repo

Goal: one shared AI context boundary in git. Teammates inherit it on clone; CI fails when secrets or ignore drift appear.

## 1. Initialize policy

```bash
offsend init --template <stack>   # e.g. node, python, swift
# optional: --strict-credentials  # policy checks + tighter context (MCP/subagents/history)
```

This writes `.offsend.yml`, materializes AI ignore files, and runs a **baseline `check` in advise-only mode** (does not fail `init`). Review `ignore.patterns` and `check.detectors` — teams tune what to disable; credentials stay on by default. See [Strict credentials](configuration.md#strict-credentials-mode).

Config references (do not commit the full catalog as-is):

| File | Role |
| --- | --- |
| [`.offsend.example.yml`](../.offsend.example.yml) | Annotated starter — copy or use `offsend init` |
| [`.offsend.full.yml`](../.offsend.full.yml) | Every recognized key + comments — pick what you need |
| [configuration.md](configuration.md) | Settings reference |

## 2. Close obvious gaps

```bash
offsend show
offsend protect    # promote required exposures into .offsend.yml + sync ignores
offsend sync       # ignore files + git / AI-editor hooks (hooks.enabled defaults true)
```

With `hooks.enabled: true` (default), `offsend doctor` **fails** until declared git hooks are installed; project AI-editor files are a warning. CI `check --policy` fails on missing git hooks, not on missing `.cursor/hooks.json`.

Recommended git hooks in `.offsend.yml`:

```yaml
hooks:
  enabled: true
  git: [pre-commit, post-merge]   # pre-commit = check --staged; post-merge = sync after pull
  publish: false
```

`post-merge` keeps every clone aligned after someone else changes `.offsend.yml`.

### Optional: MCP response seal + field rules (Cursor / Claude)

If the team uses MCP tools, seal secrets in tool **responses** before the model sees them. Each engineer needs a local key; the mode lives in the shared policy:

```bash
offsend setup              # once per machine: seal key + user-level Cursor/Claude hooks
# or: offsend keygen --default   # key only → ~/.offsend/seal.key (do not commit)
```

```yaml
# in .offsend.yml (commit this)
context:
  mcp:
    mode: ask
    responses: seal          # needs seal key on each machine
    rules:
      # Soften low-risk list tools
      - match: { server: github, tool: list_* }
        responses: observe
      # Field-level minimization (PII / over-return) — only when responses: seal
      - match: { server: crm, tool: get_customer }
        fields:
          passport_number: seal   # bare key = any depth
          ssn: seal
          account_id: pass        # keep; detectors still apply
          meta.filters: drop      # key stays, value → null
```

```bash
offsend sync && offsend doctor
```

`fields` (`seal` / `drop` / `pass`) apply to JSON object/array MCP output when the effective `responses` mode is `seal`. Cursor and Claude can rewrite MCP output; Windsurf cannot (deny via exit code). Codex has no MCP gates. Rename `server` / `tool` to match your MCP config. Full key catalog: [`.offsend.full.yml`](../.offsend.full.yml). Recipe: [configuration.md → MCP rules](configuration.md#mcp-rules-recipe). Short overview: [README → Seal](../README.md#seal).

## 3. Commit the source of truth

```bash
git add .offsend.yml
git commit -m "Add AI context policy"
```

Keep AI ignore files out of git unless you set `ignore.commit: true` (default is `false`). The team policy is `.offsend.yml`, not a hand-maintained `.cursorignore`.

## 4. Fail PRs in CI

```yaml
- uses: actions/checkout@v4
- uses: Offsend/ai-hygiene@v1
  with:
    fail-on: block
```

With policy checks enabled, CI fails on critical secrets, exposed required paths, and **managed ignore drift** (local ignore files missing patterns from `.offsend.yml`). Fix drift with `offsend sync` and commit `.offsend.yml` changes — not one-off editor ignore edits.

Or run the CLI:

```bash
offsend check --staged --policy --fail-on block
```

## 5. Every clone

```bash
offsend setup    # if this machine has not run install/setup yet
offsend sync
offsend doctor
```

`sync` materializes ignore files and installs hooks from the committed policy (`hooks.enabled` / `hooks.git` + AI-editor gates). No need to copy per-editor ignore rules by hand. With `post-merge` in `hooks.git`, later pulls that change `.offsend.yml` re-run `sync` automatically.

### Optional: OS sandbox

When hooks are not enough (enumeration without a named path, egress), enable kernel enforcement in the shared policy:

```yaml
# in .offsend.yml
sandbox:
  enabled: true
  network:
    default: deny
```

```bash
brew install nono    # recommended for Claude Code / Codex; skipped if absent
nono pull nolabs-ai/claude   # registry profile claude-code — https://nono.sh/registry
offsend sync && offsend doctor
```

Offsend writes editor/nono config and verifies it; start the agent with `offsend run claude` (or the printed `nono run …`). Details: [configuration → sandbox](configuration.md#sandbox), [cli → run](cli.md#offsend-run).

After reviewing the committed `.offsend.yml`, explicitly trust it for editor gates:

```bash
offsend policy trust
```

This interactive step stores only a local hash outside the workspace. It is intentionally not part of `sync`: an agent must not be able to approve policy changes it made itself. Later policy changes make gates fail closed until each engineer reviews and trusts the new version.

## Defaults (adoption vs CI)

| Surface | Typical mode |
| --- | --- |
| `offsend init` baseline check | Advise-only |
| Local hooks | Soft-block / warn-friendly defaults; teams can tighten |
| Secrets / credentials in `check` + CI | `fail-on: block` |

Shared baseline in the repo; each team tunes via templates and `detectors.disable`. See [FAQ](faq.md) and [configuration](configuration.md).

After upgrading the Offsend CLI, run `offsend ignore --merge-defaults` (or `show` → `protect` → `sync`) and commit `.offsend.yml` so new built-in credential paths land in the shared policy. See [Upgrading](configuration.md#upgrading-offsend-cli-existing-offsendyml).

## After a leak into agent history

Use when a coding agent may already have seen credentials (suspicious session, `doctor` / `show` history hint, or secret-shaped findings in transcripts):

```bash
offsend history audit                 # find secrets in local Cursor/Claude transcripts
offsend history scrub --apply         # redact findings (close agent sessions first)
offsend protect && offsend sync       # close path gaps + refresh ignores/hooks
offsend doctor                        # confirm next steps / remaining exposures
```

Then rotate any credentials that appeared in transcripts. Hooks and ignore files do not undo history that was already written — see [FAQ → covers / does not cover](faq.md#what-does-offsend-cover-vs-not-cover) and [CLI → Agent history](cli.md#agent-history).

## Related

- [CLI reference](cli.md)
- [Configuration](configuration.md)
- [`.offsend.example.yml`](../.offsend.example.yml) — starter
- [`.offsend.full.yml`](../.offsend.full.yml) — full parameter catalog
- [FAQ](faq.md)
- [Positioning](positioning.md)
