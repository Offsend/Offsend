# Offsend docs

Product overview and quick start live in the [main README](../README.md). Use these pages for reference depth.

| Doc | When to read it |
| --- | --- |
| [CLI reference](cli.md) | Commands, flags, exit codes, AI-editor hooks, install options, workflows |
| [Configuration](configuration.md) | `.offsend.yml` — `check`, `ignore`, `hooks`, `context.mcp` / `subagents` / `history` |
| [macOS app](macos-app.md) | Safe Paste, Prepare, Free vs Pro, App vs CLI |
| [FAQ](faq.md) | Common questions about privacy, scope, and platforms |
| [`.offsend.yml.example`](../.offsend.yml.example) | Annotated starter config |
| [SECURITY.md](../SECURITY.md) | Vulnerability reporting |

## Suggested path

1. Install and run `offsend show` — [README → Quick Start](../README.md#quick-start)
2. Create the config — `offsend init` (template + first sync)
3. Fix the boundary — `offsend protect` (rules land in `.offsend.yml` and sync to every AI ignore file)
4. Install gates — `offsend hook install`
5. Tune rules — [configuration.md](configuration.md)
6. Understand limits — [What hooks cover / do not cover](cli.md#what-hooks-cover)
