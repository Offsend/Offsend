# Offsend docs

Start on the [main README](../README.md) (quick start + [MCP seal](../README.md#mcp-seal)). These pages are reference depth.

## Essentials

| Doc | When to read it |
| --- | --- |
| [VISION](../VISION.md) | Product north star (humans + AI editors) |
| [Team setup](team.md) | Shared repo: init → commit → CI → clone `sync` |
| [CLI → MCP-response-gate](cli.md#mcp-response-gate-on-by-default) | Seal secrets in MCP tool responses (Cursor / Claude) |
| [Configuration → `context.mcp`](configuration.md#contextmcp) | `responses: seal`, allow/deny lists, modes |
| [Configuration → `sandbox`](configuration.md#sandbox) | Optional OS sandbox (`sandbox.enabled`); what each editor reaches |
| [CLI → `offsend run`](cli.md#offsend-run) | Launch cursor/claude/codex; wraps with nono when `sandbox.enabled` |
| [FAQ](faq.md) | Privacy, defaults, what hooks cover / do not |

## Reference

| Doc | When to read it |
| --- | --- |
| [CLI reference](cli.md) | Commands, flags, exit codes, all AI-editor hooks |
| [Configuration](configuration.md) | Full `.offsend.yml` — `check`, `ignore`, `hooks` (`enabled`, `git`), `context`, `sandbox` |
| [macOS app](macos-app.md) | Safe Paste, Prepare, Free vs Pro, App vs CLI |
| [`.offsend.yml.example`](../.offsend.yml.example) | Annotated starter config |
| [`.offsend.yml.full`](../.offsend.yml.full) | Every `.offsend.yml` key + comments |
| [SECURITY.md](../SECURITY.md) | Vulnerability reporting |
| [Positioning](positioning.md) | ICP and messaging (internal) |

## Suggested path

1. Install and run `offsend show` — [README → Quick Start](../README.md#quick-start)
2. Shared repo? Follow [Add Offsend to a team repo](team.md)
3. Cloned a repo with `.offsend.yml`? One command: `offsend sync` (ignore files + `hooks.git` + AI-editor hooks)
4. Using MCP in Cursor/Claude? Enable seal — [README → MCP seal](../README.md#mcp-seal)
5. Need egress denial beyond hooks? Set `sandbox.enabled: true` — [configuration → sandbox](configuration.md#sandbox)
6. New solo project: `offsend init` → `offsend protect` → `offsend sync`
7. Tune rules — [configuration.md](configuration.md) (`detectors.disable`, templates)
8. Understand limits — [What hooks cover / do not cover](cli.md#what-hooks-cover)
