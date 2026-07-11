# Configuration

Offsend looks for a project config file named `.offsend.yml` at the repository root. Commit it so the same rules apply locally, in git hooks, and in CI.

Create a starter file:

```bash
offsend init
# or copy the example:
cp .offsend.yml.example .offsend.yml
```

CLI flags override config values when provided explicitly. For example, `offsend check --policy` enables policy checks even if `check.policy` is `false`.

---

## Example

```yaml
version: 1

check:
  fail_on: block
  policy: false
  exclude:
    - "*.lock"
    - "vendor/**"
  detectors:
    disable:
      - phone
  dictionaries:
    - kind: project
      value: "Project Apollo"
    - kind: regex
      value: "ACME-\\d{4,}"

hooks:
  type: pre-commit
  fail_on: block
  policy: false
```

A fuller annotated example lives in [`.offsend.yml.example`](../.offsend.yml.example).

---

## Settings reference

### `version`

Config schema version. Use `1`; other versions are rejected.

### `check.fail_on`

Exit policy for `offsend check`:

| Value | Behavior |
| --- | --- |
| `block` | Fail only on blocking findings (critical secrets, failed policy checks) |
| `warn` | Also fail on warning / mask findings |
| `none` | Report findings but always exit successfully |

### `check.policy`

When `true`, `offsend check` also runs workspace policy checks for ignore files and exposed sensitive paths. When `false`, it scans file contents only.

### `check.exclude`

Repository-relative glob patterns skipped by file scanning:

- Plain file globs such as `*.lock` match file names
- Path globs such as `build/**` match directories recursively
- Slash patterns are matched against repository-relative paths

### `check.detectors.disable`

Detector IDs to turn off for this project. Unknown IDs are ignored.

Supported IDs:

`email`, `phone`, `money`, `url`, `ipAddress`, `internalDomain`, `contractId`, `invoiceId`, `orderId`, `apiKeyGeneric`, `openAIAPIKey`, `awsAccessKeyId`, `githubToken`, `slackToken`, `stripeKey`, `jwt`, `privateKey`, `sshPrivateKey`, `databaseURLWithPassword`, `bearerToken`, `highEntropyString`, `creditCardLike`, `iban`, `customClient`, `customCompany`, `customProject`, `customSensitiveTerm`, `customInternalDomain`, `personName`, `streetAddress`, `governmentId`

### `check.dictionaries`

Extra custom-dictionary entries matched alongside the built-in detectors. Each entry has:

| Field | Description |
| --- | --- |
| `kind` | `client`, `company`, `project`, `sensitiveTerm`, `internalDomain`, or `regex` |
| `value` | Match string. Literal (with word boundaries) for every kind except `regex`; for `regex`, used as a regular-expression pattern |

Invalid patterns and unknown kinds are ignored. Entries merge with dictionaries configured in the macOS app.

### `hooks.type`

Git hook type to install. Currently supported: `pre-commit`.

### `hooks.fail_on`

Exit policy used by installed hooks. If omitted, falls back to `check.fail_on`, then `block`.

### `hooks.policy`

Whether installed hooks include workspace policy checks. If omitted, falls back to `check.policy`, then `false`. For faster commits that check only staged files, keep this `false`.

---

## Where settings live

| Surface | Storage |
| --- | --- |
| Project rules | `.offsend.yml` in the repo |
| macOS app | Keychain + Application Support |
| CLI on macOS | Same as the app (Application Support / Keychain) |
| CLI on Linux | Plain JSON under `$XDG_CONFIG_HOME/offsend` (typically `~/.config/offsend`) |

---

## Related

- [README](../README.md) — quick start and workflows
- [`.offsend.yml.example`](../.offsend.yml.example) — copy-paste starter
