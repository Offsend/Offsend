# Offsend Vision

North star for product and architecture decisions, and for AI editors working in this repo.
Messaging and ICP detail: [`docs/positioning.md`](docs/positioning.md).

## Vision

Every software repository should carry a reviewable boundary for AI context, just as it carries rules for source control, dependencies, and CI.

Teams should define that boundary once, review it like code, and apply it across supported AI tools without sending repository contents to another cloud service.

## Mission

`.gitignore` protects Git. It does not define what AI tools should read.

Offsend makes AI context policy part of the repository: one committed `.offsend.yml`, reviewed by the team and checked in CI, then materialized into supported ignore files, runtime gates, and local controls — so secrets and sensitive paths stay out of agent context on the surfaces Offsend covers.

Credentials in agent context are **fuel for multi-step tool use** (read / shell / MCP), not only a privacy leak. Offsend reduces that fuel.

## Product thesis

1. Git boundaries and AI context boundaries are different.
2. A boundary that exists only in one developer’s editor settings is not a team policy.
3. Credentials in agent context can become input for subsequent tool actions, not only exposed data.

## North-star outcome

A team defines its AI context policy once, reviews it like code, and applies it across supported local agent surfaces and CI checks without sending repository contents to Offsend.

Roadmap test: does the change help **define**, **review**, **materialize**, **verify**, **enforce**, or **recover** that boundary?

## Operating model

After cloning, a developer restores the intended boundary with an explicit sync step and verifies that the local environment matches the committed policy.

Where runtime gates require trust, the developer makes an explicit human trust decision. Agents may propose policy changes, but must not approve weaker policy for themselves.

## Product principles

1. **Local-first** — Detection, masking, sealing, audits, hooks, and history scrub run on the user’s machine (or CI runner). No cloud account is required for the core CLI workflows: `protect`, `check`, and `seal`. Do not upload scanned file contents, prompts, clipboard payloads, or findings for analysis.
2. **One source of truth** — `.offsend.yml` in git is the policy. AI ignore files (`.cursorignore`, `.claudeignore`, …) are generated artifacts; teammates run `sync`, they do not hand-copy ignores.
3. **Preserve useful structure, remove plaintext** — When a supported surface can be transformed safely and the user has enabled it, seal or redact sensitive values so work continues without plaintext in model context. If safe substitution is unavailable, block detected high-confidence credentials rather than pass them through. Warn or advise on ambiguous findings. Defaults may remain observe or block until seal is explicitly enabled.
4. **Defense in depth, honest limits** — Ignore files → hooks → optional OS sandbox config. Hooks are not a sandbox. Offsend generates and verifies sandbox config; it does not replace the editor’s permission model or claim process containment.
5. **Policy changes remain human-reviewed** — Shared policy must not be silently weakened by the agent it governs. Agents may propose changes; trust decisions stay explicit and reviewable.
6. **Repository-level first** — The baseline is per repository. Supporting multiple tools is necessary so the same reviewed policy follows the repo across editors, but tool count is not the product goal.
7. **Adopt gently, fail closed where confidence is high** — Advise and warn for ambiguous local findings. Block high-confidence credentials and violations of the reviewed policy. CI enforces the repository’s chosen policy consistently.

### Enforcement model

The boundary has three distinct layers:

```text
.offsend.yml defines policy
Offsend materializes and verifies policy
supported tools enforce only the surfaces they expose
```

## Product system

### Core repository boundary

| Surface | Role |
| --- | --- |
| **`.offsend.yml`** | Shared, reviewable source of truth |
| **CLI** (macOS / Linux) | Audit, sync, hooks, sealing, history, local checks |
| **GitHub Action** | Policy and secret checks on pull requests |

### Companion local workflows

| Surface | Role |
| --- | --- |
| **macOS app** | Safe Paste, document preparation, project audits, watched folders |

### Adjacent trust boundaries

| Surface | Role |
| --- | --- |
| **Browser Extension** | Mask secrets in supported web AI chats before submission |

### Discovery

| Surface | Role |
| --- | --- |
| **Check** | Opt-in scan of a public GitHub repository the user chooses |

### Research and category building

| Surface | Role |
| --- | --- |
| **Radar** | Research into repository-level AI context practices and adoption |

Offsend may have several surfaces; the core is repository-level AI context policy.

## Non-goals

- Not a full agent permission system or escape-containment layer
- Not a universal process or network sandbox
- Not general protection against workspace files executed by IDEs or privileged host helpers
- Not an org-wide policy plane across every repository
- Not a block-everything-by-default workflow for casual local use
- Not dependent on a cloud account or source upload for core analysis

An optional `offsend run` may apply user-configured OS controls, but process wrapping is not the product’s primary containment model.

## Decision rules for contributors and AI editors

When proposing features, refactors, copy, or defaults:

- Prefer changes that strengthen the repository boundary lifecycle: define policy → sync and materialize → verify drift → enforce on supported surfaces and CI → recover after exposure.
- On intercepted surfaces, prefer seal, redact, or withhold over passing detected plaintext through. Do not change seal defaults without an explicit product decision. Never silently pass a detected high-confidence plaintext secret through an intercepted surface.
- Never weaken local-first privacy (no new uploads of scanned content, prompts, or findings).
- Do not claim containment Offsend does not provide; document limits honestly.
- Keep CLI free/open-source workflows usable without the macOS app or a cloud account.
- Do not treat multi-tool coverage or companion surfaces as the product story.
- Match existing docs tone: concrete, path-and-policy focused, no hype about “full agent security.”

## Related

- [`README.md`](README.md) — product overview and quick start
- [`docs/positioning.md`](docs/positioning.md) — ICP and messaging tests
- [`SECURITY.md`](SECURITY.md) — trust boundaries and secret handling
- [`docs/team.md`](docs/team.md) — shared-repo setup
- [`docs/faq.md`](docs/faq.md) — coverage limits
