# Positioning

Internal framing for product copy, docs, and posts. Not a feature list.

## Job to be done

Commit an AI context boundary next to the code — like `.gitignore`, but for what agents may read. Teammates inherit it on clone; CI can fail when the boundary drifts or secrets appear.

## Who it is for

- Teams that share a repository and already use AI coding tools
- Agencies, contractors, and OSS maintainers (you rarely control which editor someone opens)
- Repos with secrets, customer data, or credentials that must stay out of agent context
- Places where AI hygiene is tribal knowledge (one person’s `.cursorignore`) instead of something in git

## Who it is not for (today)

- High-trust “always allow” environments where each engineer owns tool config and enforcement is undesirable
- Orgs that only want a sandbox / replacement for the agent’s permission model
- People whose main pain is rate-limit hopping between personal AI subscriptions

## Messaging test

If you remove “multiple AI tools” from a sentence and the value disappears, rewrite it.

Lead with: shared `.offsend.yml` in git → ignore files + hooks + CI. Multi-tool support is how that policy is enforced across editors — a side effect, not the product story.

## Non-goals

- Not a sandbox or full agent permission system
- Not org-wide policy across every repository (repo-level baseline first)
- Not “block everything by default” locally — prefer advise/warn for adoption; **block** for credentials/secrets and CI

## Related

- [Team setup](team.md)
- [FAQ](faq.md)
- [Configuration](configuration.md)
- [README](../README.md)
