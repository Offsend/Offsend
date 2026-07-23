# Add Offsend to a team repo

Goal: one shared AI context boundary in git. Teammates inherit it on clone; CI fails when secrets or ignore drift appear.

## 1. Initialize policy

```bash
offsend init --template <stack>   # e.g. node, python, swift
# optional: --strict-credentials  # policy checks + tighter context (MCP/subagents/history)
```

This writes `.offsend.yml`, materializes AI ignore files, and runs a **baseline `check` in advise-only mode** (does not fail `init`). Review `ignore.patterns` and `check.detectors` — teams tune what to disable; credentials stay on by default. See [Strict credentials](configuration.md#strict-credentials-mode).

## 2. Close obvious gaps

```bash
offsend show
offsend protect    # promote required exposures into .offsend.yml + sync ignores
offsend sync       # ignore files + git / AI-editor hooks
```

### Optional: MCP response seal (Cursor / Claude)

If the team uses MCP tools, seal secrets in tool **responses** before the model sees them. Each engineer needs a local key; the mode lives in the shared policy:

```bash
offsend keygen --default   # once per machine → ~/.offsend/seal.key (do not commit)
```

```yaml
# in .offsend.yml (commit this)
context:
  mcp:
    responses: seal
```

```bash
offsend sync && offsend doctor
```

Short recipe: [README → MCP seal](../README.md#mcp-seal). Details: [cli.md → MCP-response-gate](cli.md#mcp-response-gate-on-by-default).

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
offsend sync
offsend doctor
```

`sync` materializes ignore files and installs hooks from the committed policy. No need to copy per-editor ignore rules by hand.

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
- [FAQ](faq.md)
- [Positioning](positioning.md)
