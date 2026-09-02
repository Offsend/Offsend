# Offsend seal-utility benchmark v0.1

## All-cases performance

| Variant | TSR | Output leakage (PLR) | Placeholder preservation | Char inflation | Prompt-token inflation |
|---|---:|---:|---:|---:|---:|
| Clean | 98.3% | — | — | — | — |
| Delete | 71.7% | 0% | — | 0.87 | 0.94 |
| [REDACTED] | 95% | 0% | — | 1.00 | 1.00 |
| Offsend | 100% | 0% | 10% | 2.21 | 1.73 |

## Primary utility — clean-qualified population

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 29 |
| Delete | 72.4% | 29 |
| [REDACTED] | 96.6% | 29 |
| Offsend | 100% | 29 |

Excluded because clean failed: 1 / 30

Security status:
  Delete PLR = 0%
  [REDACTED] PLR = 0%
  Offsend PLR = 0%

## Breakdown by category

### code

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 4 |
| Delete | 100% | 4 |
| [REDACTED] | 87.5% | 4 |
| Offsend | 100% | 4 |

### config

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 10 |
| Delete | 65% | 10 |
| [REDACTED] | 100% | 10 |
| Offsend | 100% | 10 |

### debugging

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 5 |
| Delete | 60% | 5 |
| [REDACTED] | 100% | 5 |
| Offsend | 100% | 5 |

### editing

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 1 |
| Delete | 100% | 1 |
| [REDACTED] | 100% | 1 |
| Offsend | 100% | 1 |

### mcp

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 5 |
| Delete | 70% | 5 |
| [REDACTED] | 90% | 5 |
| Offsend | 100% | 5 |

### transformation

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 4 |
| Delete | 75% | 4 |
| [REDACTED] | 100% | 4 |
| Offsend | 100% | 4 |

## Breakdown by model

### claude-sonnet-4-5

| Variant | TSR | Output leakage (PLR) | Placeholder preservation | Char inflation | Prompt-token inflation |
|---|---:|---:|---:|---:|---:|
| Clean | 96.7% | — | — | — | — |
| Delete | 73.3% | 0% | — | 0.87 | 0.96 |
| [REDACTED] | 93.3% | 0% | — | 1.00 | 1.00 |
| Offsend | 100% | 0% | 20% | 2.21 | 1.80 |

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 29 |
| Delete | 75.9% | 29 |
| [REDACTED] | 96.6% | 29 |
| Offsend | 100% | 29 |

Excluded because clean failed: 1 / 30

Security status:
  Delete PLR = 0%
  [REDACTED] PLR = 0%
  Offsend PLR = 0%

### gpt-4o-mini

| Variant | TSR | Output leakage (PLR) | Placeholder preservation | Char inflation | Prompt-token inflation |
|---|---:|---:|---:|---:|---:|
| Clean | 100% | — | — | — | — |
| Delete | 70% | 0% | — | 0.87 | 0.93 |
| [REDACTED] | 96.7% | 0% | — | 1.00 | 1.00 |
| Offsend | 100% | 0% | 0% | 2.21 | 1.67 |

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 30 |
| Delete | 70% | 30 |
| [REDACTED] | 96.7% | 30 |
| Offsend | 100% | 30 |

Excluded because clean failed: 0 / 30

Security status:
  Delete PLR = 0%
  [REDACTED] PLR = 0%
  Offsend PLR = 0%

## Failure buckets

- `fabricated_secret`: 1
- `invalid_json`: 3
- `lost_structure`: 1
- `placeholder_removed`: 4
- `wrong_field_interpretation`: 20

## Diagnostics

Overall SUR uses cases that passed clean on every model in the run (intersection). Per-model SUR uses that model's own clean-pass list. Previews are sanitized; full prompts, responses, and secret values stay in `results/raw/`.

### Clean population

#### claude-sonnet-4-5

Qualified (29): `aws-env-001`, `aws-region-parse-001`, `bearer-log-001`, `compose-multi-001`, `connect-fn-001`, `db-timeout-001`, `edit-dotenv-load-001`, `extract-host-001`, `github-clone-001`, `https-git-001`, `jwt-error-001`, `kube-db-001`, `mcp-aws-list-001`, `mcp-gh-clone-001`, `mcp-multi-secrets-001`, `mcp-read-env-001`, `mcp-sql-result-001`, `mongo-config-001`, `multi-client-001`, `multi-log-001`, `mysql-config-001`, `openai-env-001`, `parse-dsn-code-001`, `postgres-config-001`, `redact-logger-001`, `redis-config-001`, `rewrite-dsn-001`, `slack-retry-001`, `split-multi-001`

Excluded (1):
- `env-to-json-001` (transformation) — `wrong_field_interpretation`: field_mismatch: has_password_var (got bool, expected bool)

#### gpt-4o-mini

Qualified (30): `aws-env-001`, `aws-region-parse-001`, `bearer-log-001`, `compose-multi-001`, `connect-fn-001`, `db-timeout-001`, `edit-dotenv-load-001`, `env-to-json-001`, `extract-host-001`, `github-clone-001`, `https-git-001`, `jwt-error-001`, `kube-db-001`, `mcp-aws-list-001`, `mcp-gh-clone-001`, `mcp-multi-secrets-001`, `mcp-read-env-001`, `mcp-sql-result-001`, `mongo-config-001`, `multi-client-001`, `multi-log-001`, `mysql-config-001`, `openai-env-001`, `parse-dsn-code-001`, `postgres-config-001`, `redact-logger-001`, `redis-config-001`, `rewrite-dsn-001`, `slack-retry-001`, `split-multi-001`

Excluded (0): none

#### overall (intersection)

Qualified (29): `aws-env-001`, `aws-region-parse-001`, `bearer-log-001`, `compose-multi-001`, `connect-fn-001`, `db-timeout-001`, `edit-dotenv-load-001`, `extract-host-001`, `github-clone-001`, `https-git-001`, `jwt-error-001`, `kube-db-001`, `mcp-aws-list-001`, `mcp-gh-clone-001`, `mcp-multi-secrets-001`, `mcp-read-env-001`, `mcp-sql-result-001`, `mongo-config-001`, `multi-client-001`, `multi-log-001`, `mysql-config-001`, `openai-env-001`, `parse-dsn-code-001`, `postgres-config-001`, `redact-logger-001`, `redis-config-001`, `rewrite-dsn-001`, `slack-retry-001`, `split-multi-001`

Excluded (1):
- `env-to-json-001` (transformation) — failed clean on: claude-sonnet-4-5

### Utility losses

Clean passed for this model; a transformed variant failed or leaked. These rows are the primary signal for case/grader/seal changes.

| Model | Case | Category | Variant | Bucket | Detail | Preview |
|---|---|---|---|---|---|---|
| claude-sonnet-4-5 | `parse-dsn-code-001` | code | offsend | `fabricated_secret` | detector_finding_not_original_or_token | Looking at the example DSN, I need to parse a database connection string and extract the protocol and host. ```python def parse_dsn(dsn): """ Parse a DSN (Data Source Name) URL and return protocol an… |
| claude-sonnet-4-5 | `redact-logger-001` | code | redacted | `lost_structure` | missing_substring: /health | ```python logger.info(f"{method} {path} {status}") ``` This logs only the HTTP method, path, and status code without including any authorization headers or bearer tokens. |
| claude-sonnet-4-5 | `aws-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: access_key_configured (got bool, expected bool) | ```json { "region": "eu-west-1", "output_format": "json", "access_key_configured": false } ``` |
| claude-sonnet-4-5 | `github-clone-001` | config | delete | `wrong_field_interpretation` | field_mismatch: auth_configured (got bool, expected bool) | ```json { "host": "github.com", "owner": "acme", "repo": "payments", "auth_configured": false } ``` |
| claude-sonnet-4-5 | `openai-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: key_configured (got bool, expected bool) | ```json { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": false } ``` |
| claude-sonnet-4-5 | `jwt-error-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: token_present (got bool, expected bool) | ```json { "error_code": "TOKEN_EXPIRED", "endpoint": "/account/session", "token_present": false } ``` |
| claude-sonnet-4-5 | `slack-retry-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: token_configured (got bool, expected bool) | ```json { "retries": 3, "channel": "#ops-alerts", "token_configured": false } ``` |
| claude-sonnet-4-5 | `mcp-read-env-001` | mcp | delete | `wrong_field_interpretation` | field_mismatch: has_openai_key (got bool, expected bool) | ```json { "tool": "Read", "first_key": "APP_ENV", "second_key": "openai_api_key", "has_openai_key": false } ``` |
| claude-sonnet-4-5 | `aws-region-parse-001` | transformation | delete | `wrong_field_interpretation` | field_mismatch: access_key_set (got bool, expected bool) | ```json { "region": "ap-southeast-2", "output": "text", "access_key_set": false } ``` |
| gpt-4o-mini | `aws-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: access_key_configured (got bool, expected bool) | { "region": "eu-west-1", "output_format": "json", "access_key_configured": false } |
| gpt-4o-mini | `openai-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: key_configured (got bool, expected bool) | { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": false } |
| gpt-4o-mini | `postgres-config-001` | config | delete | `wrong_field_interpretation` | field_mismatch: has_authentication (got bool, expected bool) | { "protocol": "postgres", "username": "admin", "host": "db.internal", "database": "prod", "has_authentication": false } |
| gpt-4o-mini | `redis-config-001` | config | delete | `wrong_field_interpretation` | field_mismatch: username (got str, expected str) | { "protocol": "redis", "username": "", "host": "cache.example.com", "port": 6379, "db": 0 } |
| gpt-4o-mini | `jwt-error-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: token_present (got bool, expected bool) | { "error_code": "TOKEN_EXPIRED", "endpoint": "/account/session", "token_present": false } |
| gpt-4o-mini | `slack-retry-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: token_configured (got bool, expected bool) | { "retries": 3, "channel": "#ops-alerts", "token_configured": false } |
| gpt-4o-mini | `mcp-multi-secrets-001` | mcp | delete | `wrong_field_interpretation` | field_mismatch: secret_key_count (got int, expected int) | { "tool": "env_get", "secret_key_count": 0, "has_github": false, "has_openai": false } |
| gpt-4o-mini | `mcp-read-env-001` | mcp | delete | `wrong_field_interpretation` | field_mismatch: has_openai_key (got bool, expected bool) | {"tool":"Read","first_key":"APP_ENV","second_key":"openai_api_key","has_openai_key":false} |
| gpt-4o-mini | `mcp-read-env-001` | mcp | redacted | `wrong_field_interpretation` | field_mismatch: first_key (got str, expected str) | {"tool":"Read","first_key":"path","second_key":"text","has_openai_key":true} |
| gpt-4o-mini | `aws-region-parse-001` | transformation | delete | `wrong_field_interpretation` | field_mismatch: access_key_set (got bool, expected bool) | { "region": "ap-southeast-2", "output": "text", "access_key_set": false } |

### Failure log

| Model | Case | Category | Variant | Bucket | Detail | Preview |
|---|---|---|---|---|---|---|
| claude-sonnet-4-5 | `parse-dsn-code-001` | code | offsend | `fabricated_secret` | detector_finding_not_original_or_token | Looking at the example DSN, I need to parse a database connection string and extract the protocol and host. ```python def parse_dsn(dsn): """ Parse a DSN (Data Source Name) URL and return protocol an… |
| claude-sonnet-4-5 | `redact-logger-001` | code | redacted | `lost_structure` | missing_substring: /health | ```python logger.info(f"{method} {path} {status}") ``` This logs only the HTTP method, path, and status code without including any authorization headers or bearer tokens. |
| claude-sonnet-4-5 | `aws-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: access_key_configured (got bool, expected bool) | ```json { "region": "eu-west-1", "output_format": "json", "access_key_configured": false } ``` |
| claude-sonnet-4-5 | `github-clone-001` | config | delete | `wrong_field_interpretation` | field_mismatch: auth_configured (got bool, expected bool) | ```json { "host": "github.com", "owner": "acme", "repo": "payments", "auth_configured": false } ``` |
| claude-sonnet-4-5 | `openai-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: key_configured (got bool, expected bool) | ```json { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": false } ``` |
| claude-sonnet-4-5 | `jwt-error-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: token_present (got bool, expected bool) | ```json { "error_code": "TOKEN_EXPIRED", "endpoint": "/account/session", "token_present": false } ``` |
| claude-sonnet-4-5 | `slack-retry-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: token_configured (got bool, expected bool) | ```json { "retries": 3, "channel": "#ops-alerts", "token_configured": false } ``` |
| claude-sonnet-4-5 | `mcp-read-env-001` | mcp | delete | `wrong_field_interpretation` | field_mismatch: has_openai_key (got bool, expected bool) | ```json { "tool": "Read", "first_key": "APP_ENV", "second_key": "openai_api_key", "has_openai_key": false } ``` |
| claude-sonnet-4-5 | `aws-region-parse-001` | transformation | delete | `wrong_field_interpretation` | field_mismatch: access_key_set (got bool, expected bool) | ```json { "region": "ap-southeast-2", "output": "text", "access_key_set": false } ``` |
| claude-sonnet-4-5 | `env-to-json-001` | transformation | clean | `wrong_field_interpretation` | field_mismatch: has_password_var (got bool, expected bool) | ```json { "var_count": 2, "db_host": "core.example.com", "has_password_var": false } ``` |
| claude-sonnet-4-5 | `env-to-json-001` | transformation | delete | `wrong_field_interpretation` | field_mismatch: has_password_var (got bool, expected bool) | ```json { "var_count": 2, "db_host": "core.example.com", "has_password_var": false } ``` |
| claude-sonnet-4-5 | `env-to-json-001` | transformation | redacted | `wrong_field_interpretation` | field_mismatch: has_password_var (got bool, expected bool) | ```json { "var_count": 2, "db_host": "core.example.com", "has_password_var": false } ``` |
| gpt-4o-mini | `aws-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: access_key_configured (got bool, expected bool) | { "region": "eu-west-1", "output_format": "json", "access_key_configured": false } |
| gpt-4o-mini | `openai-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: key_configured (got bool, expected bool) | { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": false } |
| gpt-4o-mini | `postgres-config-001` | config | delete | `wrong_field_interpretation` | field_mismatch: has_authentication (got bool, expected bool) | { "protocol": "postgres", "username": "admin", "host": "db.internal", "database": "prod", "has_authentication": false } |
| gpt-4o-mini | `redis-config-001` | config | delete | `wrong_field_interpretation` | field_mismatch: username (got str, expected str) | { "protocol": "redis", "username": "", "host": "cache.example.com", "port": 6379, "db": 0 } |
| gpt-4o-mini | `jwt-error-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: token_present (got bool, expected bool) | { "error_code": "TOKEN_EXPIRED", "endpoint": "/account/session", "token_present": false } |
| gpt-4o-mini | `slack-retry-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: token_configured (got bool, expected bool) | { "retries": 3, "channel": "#ops-alerts", "token_configured": false } |
| gpt-4o-mini | `mcp-multi-secrets-001` | mcp | delete | `wrong_field_interpretation` | field_mismatch: secret_key_count (got int, expected int) | { "tool": "env_get", "secret_key_count": 0, "has_github": false, "has_openai": false } |
| gpt-4o-mini | `mcp-read-env-001` | mcp | delete | `wrong_field_interpretation` | field_mismatch: has_openai_key (got bool, expected bool) | {"tool":"Read","first_key":"APP_ENV","second_key":"openai_api_key","has_openai_key":false} |
| gpt-4o-mini | `mcp-read-env-001` | mcp | redacted | `wrong_field_interpretation` | field_mismatch: first_key (got str, expected str) | {"tool":"Read","first_key":"path","second_key":"text","has_openai_key":true} |
| gpt-4o-mini | `aws-region-parse-001` | transformation | delete | `wrong_field_interpretation` | field_mismatch: access_key_set (got bool, expected bool) | { "region": "ap-southeast-2", "output": "text", "access_key_set": false } |

### Buckets by model × variant

| Bucket | Model | Variant | Count |
|---|---|---|---:|
| `fabricated_secret` | claude-sonnet-4-5 | offsend | 1 |
| `invalid_json` | claude-sonnet-4-5 | offsend | 3 |
| `lost_structure` | claude-sonnet-4-5 | redacted | 1 |
| `placeholder_removed` | gpt-4o-mini | offsend | 4 |
| `wrong_field_interpretation` | claude-sonnet-4-5 | clean | 1 |
| `wrong_field_interpretation` | claude-sonnet-4-5 | delete | 8 |
| `wrong_field_interpretation` | claude-sonnet-4-5 | redacted | 1 |
| `wrong_field_interpretation` | gpt-4o-mini | delete | 9 |
| `wrong_field_interpretation` | gpt-4o-mini | redacted | 1 |
