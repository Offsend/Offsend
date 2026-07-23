# Offsend docs

Product overview and quick start live in the [main README](../README.md). Use these pages for reference depth.

| Doc | When to read it |
| --- | --- |
| [Team setup](team.md) | Add Offsend to a shared repo: init → commit → CI → clone `sync` |
| [CLI reference](cli.md) | Commands, flags, exit codes, AI-editor hooks, install options, workflows |
| [Configuration](configuration.md) | `.offsend.yml` — `check`, `ignore`, `hooks`, `context.mcp` / `subagents` / `history` |
| [macOS app](macos-app.md) | Safe Paste, Prepare, Free vs Pro, App vs CLI |
| [FAQ](faq.md) | Privacy, defaults, scope, and platforms |
| [Positioning](positioning.md) | ICP and messaging test (internal) |
| [`.offsend.yml.example`](../.offsend.yml.example) | Annotated starter config |
| [SECURITY.md](../SECURITY.md) | Vulnerability reporting |

## Suggested path

1. Install and run `offsend show` — [README → Quick Start](../README.md#quick-start)
2. Shared repo? Follow [Add Offsend to a team repo](team.md)
3. Cloned a repo with `.offsend.yml`? One command: `offsend sync` (ignore files + hooks)
4. New solo project: `offsend init` → `offsend protect` → `offsend sync`
5. Tune rules — [configuration.md](configuration.md) (`detectors.disable`, templates)
6. Understand limits — [What hooks cover / do not cover](cli.md#what-hooks-cover)
