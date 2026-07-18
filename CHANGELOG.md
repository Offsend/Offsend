# Changelog

## Unreleased

### Breaking (CLI)

- Removed `offsend prepare`. Missing AI ignore files are created by `offsend protect`; the `--sync-patterns` legacy path has no replacement (use `.offsend.yml` + `offsend ignore`).
- Removed `offsend sync`. Use `offsend ignore --sync` to re-materialize `ignore.patterns` from `.offsend.yml` into AI ignore files.
- Removed `offsend report`. Use `offsend show --report [--out PATH]` for the anonymized JSON hygiene report.

### Added (CLI)

- `offsend ignore --sync` — materialize `ignore.patterns` without adding new patterns.
- `offsend show --report` / `--out` — anonymized aggregated JSON report (no paths or file names).
- Managed editor privacy rules: `offsend protect` now also creates `.claude/rules/offsend_privacy.md` for Claude Code (the Cursor rule moved from `.cursor/rules/privacy.mdc` to `.cursor/rules/offsend_privacy.mdc`; an existing legacy `privacy.mdc` keeps satisfying the check and is never overwritten). Both files render the same canonical text in the editor's native format and are fully owned by Offsend: manual edits are restored on `protect` (reported by `doctor`), and with `ignore.commit: false` their exact paths join the managed `.gitignore` block — user rule files and directories are never touched.
- `ignore.tools` in `.offsend.yml` — optional list of tool slugs (`cursor`, `claude`, `copilot`, …) narrowing which AI tools get managed ignore/rule files. Absent = all supported tools.

### Changed (CLI)

- `check.exclude` defaults: `common` now includes `.offsend/hooks/**`; `swift` also includes `**/Info.plist` (alongside existing `Package.resolved`).
- `offsend check --help` no longer lists AI-editor hook plumbing flags (`--adapter`, `--hook-policy`, gates, seal-key options). The flags still work and installed hooks are unaffected.
- Top-level help reordered around the main journey: setup → init → edit → protect → show → ignore → check → hook → history → seal → unseal → keygen → doctor.
