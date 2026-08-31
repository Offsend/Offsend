# Positioning

Internal framing for product copy, docs, and posts. Not a feature list.
Durable product north star: [`../VISION.md`](../VISION.md).

## Job to be done

Commit an AI context boundary next to the code — like `.gitignore`, but for what agents may read. Teammates inherit it on clone; CI can fail when the boundary drifts or secrets appear.

Product emphasis: credentials in agent context are **leverage for multi-step tool use** (read / shell / MCP), not only a privacy leak. Offsend reduces that fuel. Optional [`sandbox.enabled`](configuration.md#sandbox) generates and verifies OS sandbox config; Offsend still does not replace the editor’s permission model or wrap a running agent.

Enforcement posture: **don’t stop the agent — swap the secrets for tokens.** Where the editor allows it, gates prefer substitution over dead-end denies: seal-for-agents gives the agent a sealed copy of a blocked file (`context.read.on_secret: seal`), and the MCP-response gate seals secrets in Cursor/Claude tool output (`context.mcp.responses: seal`). Work continues; plaintext stays out of model context; the user reverses tokens with `offsend unseal`. Blocking remains the default and the fallback when sealing is unavailable.

Trust-handoff posture: the committed policy is reviewable team state, not automatically trusted runtime authority. `offsend policy trust` pins the reviewed policy outside the agent-writable workspace; drift fails editor gates closed. This hardens Offsend's own control plane without claiming containment of arbitrary IDE, Git, daemon, or host automation.

## Who it is for

- Teams that share a repository and already use AI coding tools
- Agencies, contractors, and OSS maintainers (you rarely control which editor someone opens)
- Repos with secrets, customer data, or credentials that must stay out of agent context
- Places where AI hygiene is tribal knowledge (one person’s `.cursorignore`) instead of something in git

## Who it is not for (today)

- High-trust “always allow” environments where each engineer owns tool config and enforcement is undesirable
- Orgs that only want a full agent permission system / escape containment (Offsend can materialize sandbox config; it does not enforce process launch)
- People whose main pain is rate-limit hopping between personal AI subscriptions

## Messaging test

If you remove “multiple AI tools” from a sentence and the value disappears, rewrite it.

Lead with: shared `.offsend.yml` in git → ignore files + hooks + CI. Multi-tool support is how that policy is enforced across editors — a side effect, not the product story.

## Vs GitGuardian ggshield

Eight-second line (no sandbox): **local seal, agent keeps working, fail-closed without a key** — not cloud block + fail-open.

ggshield’s AI hooks occupy the same Cursor/Claude hook files, scan in GitGuardian’s cloud, and fail open without an API key. Offsend does not uninstall them: hook install **merges**. Do not compete on detector count or promise Copilot/Windows to “match the table.” Do not claim containment.

Public copy: [README → Offsend and GitGuardian](../README.md#offsend-and-gitguardian).

## Non-goals

- Not a full agent permission system or escape containment
- Not applying `nono` / process wrappers for you (generate + verify only)
- Not general protection against workspace files executed by IDEs or privileged host helpers
- Not org-wide policy across every repository (repo-level baseline first)
- Not “block everything by default” locally — prefer advise/warn for adoption; **block** for credentials/secrets and CI
- Not a GitGuardian detector-count race or a ggshield uninstaller

## Related

- [Team setup](team.md)
- [FAQ](faq.md)
- [Configuration](configuration.md)
- [README](../README.md)
