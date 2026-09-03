# Offsend seal-utility benchmark v0

## All-cases performance

| Variant | TSR | Output leakage (PLR) | Placeholder preservation | Char inflation | Prompt-token inflation |
|---|---:|---:|---:|---:|---:|
| Clean | 60% | — | — | — | — |
| Delete | 43.3% | 0% | — | 0.87 | 0.94 |
| [REDACTED] | 51.7% | 0% | — | 1.00 | 1.00 |
| Offsend | 55% | 0% | 10% | 2.21 | 1.73 |

## Primary utility — clean-qualified population

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 7 |
| Delete | 78.6% | 7 |
| [REDACTED] | 71.4% | 7 |
| Offsend | 78.6% | 7 |

Excluded because clean failed: 23 / 30

Security status:
  Delete PLR = 0%
  [REDACTED] PLR = 0%
  Offsend PLR = 0%

## Breakdown by category

### code

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 2 |
| Delete | 100% | 2 |
| [REDACTED] | 75% | 2 |
| Offsend | 100% | 2 |

### config

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 1 |
| Delete | 0% | 1 |
| [REDACTED] | 50% | 1 |
| Offsend | 50% | 1 |

### debugging

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | — | 0 |
| Delete | — | 0 |
| [REDACTED] | — | 0 |
| Offsend | — | 0 |

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
| Clean | — | 0 |
| Delete | — | 0 |
| [REDACTED] | — | 0 |
| Offsend | — | 0 |

### transformation

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 3 |
| Delete | 83.3% | 3 |
| [REDACTED] | 66.7% | 3 |
| Offsend | 66.7% | 3 |

## Breakdown by model

### claude-sonnet-4-5

| Variant | TSR | Output leakage (PLR) | Placeholder preservation | Char inflation | Prompt-token inflation |
|---|---:|---:|---:|---:|---:|
| Clean | 26.7% | — | — | — | — |
| Delete | 23.3% | 0% | — | 0.87 | 0.96 |
| [REDACTED] | 13.3% | 0% | — | 1.00 | 1.00 |
| Offsend | 16.7% | 0% | 20% | 2.21 | 1.80 |

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 8 |
| Delete | 75% | 8 |
| [REDACTED] | 50% | 8 |
| Offsend | 62.5% | 8 |

Excluded because clean failed: 22 / 30

Security status:
  Delete PLR = 0%
  [REDACTED] PLR = 0%
  Offsend PLR = 0%

### gpt-4o-mini

| Variant | TSR | Output leakage (PLR) | Placeholder preservation | Char inflation | Prompt-token inflation |
|---|---:|---:|---:|---:|---:|
| Clean | 93.3% | — | — | — | — |
| Delete | 63.3% | 0% | — | 0.87 | 0.93 |
| [REDACTED] | 90% | 0% | — | 1.00 | 1.00 |
| Offsend | 93.3% | 0% | 0% | 2.21 | 1.67 |

| Variant | SUR | Clean-qualified cases |
|---|---:|---:|
| Clean | 100% | 28 |
| Delete | 67.9% | 28 |
| [REDACTED] | 96.4% | 28 |
| Offsend | 100% | 28 |

Excluded because clean failed: 2 / 30

Security status:
  Delete PLR = 0%
  [REDACTED] PLR = 0%
  Offsend PLR = 0%

## Failure buckets

- `fabricated_secret`: 1
- `invalid_json`: 94
- `lost_structure`: 5
- `placeholder_removed`: 4
- `wrong_field_interpretation`: 15

## Diagnostics

Overall SUR uses cases that passed clean on every model in the run (intersection). Per-model SUR uses that model's own clean-pass list. Previews are sanitized; full prompts, responses, and secret values stay in `results/raw/`.

### Clean population

#### claude-sonnet-4-5

Qualified (8): `connect-fn-001`, `edit-dotenv-load-001`, `extract-host-001`, `openai-env-001`, `parse-dsn-code-001`, `redact-logger-001`, `rewrite-dsn-001`, `split-multi-001`

Excluded (22):
- `aws-env-001` (config) — `invalid_json`: markdown_fence
- `aws-region-parse-001` (transformation) — `invalid_json`: markdown_fence
- `bearer-log-001` (debugging) — `invalid_json`: markdown_fence
- `compose-multi-001` (config) — `invalid_json`: markdown_fence
- `db-timeout-001` (debugging) — `invalid_json`: markdown_fence
- `env-to-json-001` (transformation) — `invalid_json`: markdown_fence
- `github-clone-001` (config) — `invalid_json`: markdown_fence
- `https-git-001` (config) — `invalid_json`: markdown_fence
- `jwt-error-001` (debugging) — `invalid_json`: markdown_fence
- `kube-db-001` (config) — `invalid_json`: markdown_fence
- `mcp-aws-list-001` (mcp) — `invalid_json`: markdown_fence
- `mcp-gh-clone-001` (mcp) — `invalid_json`: markdown_fence
- `mcp-multi-secrets-001` (mcp) — `invalid_json`: markdown_fence
- `mcp-read-env-001` (mcp) — `invalid_json`: markdown_fence
- `mcp-sql-result-001` (mcp) — `invalid_json`: markdown_fence
- `mongo-config-001` (config) — `invalid_json`: markdown_fence
- `multi-client-001` (code) — `invalid_json`: markdown_fence
- `multi-log-001` (debugging) — `invalid_json`: markdown_fence
- `mysql-config-001` (config) — `invalid_json`: markdown_fence
- `postgres-config-001` (config) — `invalid_json`: markdown_fence
- `redis-config-001` (config) — `invalid_json`: markdown_fence
- `slack-retry-001` (debugging) — `invalid_json`: markdown_fence

#### gpt-4o-mini

Qualified (28): `aws-env-001`, `aws-region-parse-001`, `bearer-log-001`, `compose-multi-001`, `edit-dotenv-load-001`, `env-to-json-001`, `extract-host-001`, `github-clone-001`, `https-git-001`, `jwt-error-001`, `kube-db-001`, `mcp-aws-list-001`, `mcp-gh-clone-001`, `mcp-multi-secrets-001`, `mcp-read-env-001`, `mcp-sql-result-001`, `mongo-config-001`, `multi-client-001`, `multi-log-001`, `mysql-config-001`, `openai-env-001`, `parse-dsn-code-001`, `postgres-config-001`, `redact-logger-001`, `redis-config-001`, `rewrite-dsn-001`, `slack-retry-001`, `split-multi-001`

Excluded (2):
- `connect-fn-001` (code) — `lost_structure`: missing_substring: os.environ
- `db-timeout-001` (debugging) — `wrong_field_interpretation`: field_mismatch: exception (got str, expected str)

#### overall (intersection)

Qualified (7): `edit-dotenv-load-001`, `extract-host-001`, `openai-env-001`, `parse-dsn-code-001`, `redact-logger-001`, `rewrite-dsn-001`, `split-multi-001`

Excluded (23):
- `aws-env-001` (config) — failed clean on: claude-sonnet-4-5
- `aws-region-parse-001` (transformation) — failed clean on: claude-sonnet-4-5
- `bearer-log-001` (debugging) — failed clean on: claude-sonnet-4-5
- `compose-multi-001` (config) — failed clean on: claude-sonnet-4-5
- `connect-fn-001` (code) — failed clean on: gpt-4o-mini
- `db-timeout-001` (debugging) — failed clean on: claude-sonnet-4-5, gpt-4o-mini
- `env-to-json-001` (transformation) — failed clean on: claude-sonnet-4-5
- `github-clone-001` (config) — failed clean on: claude-sonnet-4-5
- `https-git-001` (config) — failed clean on: claude-sonnet-4-5
- `jwt-error-001` (debugging) — failed clean on: claude-sonnet-4-5
- `kube-db-001` (config) — failed clean on: claude-sonnet-4-5
- `mcp-aws-list-001` (mcp) — failed clean on: claude-sonnet-4-5
- `mcp-gh-clone-001` (mcp) — failed clean on: claude-sonnet-4-5
- `mcp-multi-secrets-001` (mcp) — failed clean on: claude-sonnet-4-5
- `mcp-read-env-001` (mcp) — failed clean on: claude-sonnet-4-5
- `mcp-sql-result-001` (mcp) — failed clean on: claude-sonnet-4-5
- `mongo-config-001` (config) — failed clean on: claude-sonnet-4-5
- `multi-client-001` (code) — failed clean on: claude-sonnet-4-5
- `multi-log-001` (debugging) — failed clean on: claude-sonnet-4-5
- `mysql-config-001` (config) — failed clean on: claude-sonnet-4-5
- `postgres-config-001` (config) — failed clean on: claude-sonnet-4-5
- `redis-config-001` (config) — failed clean on: claude-sonnet-4-5
- `slack-retry-001` (debugging) — failed clean on: claude-sonnet-4-5

### Utility losses

Clean passed for this model; a transformed variant failed or leaked. These rows are the primary signal for case/grader/seal changes.

| Model | Case | Category | Variant | Bucket | Detail | Preview |
|---|---|---|---|---|---|---|
| claude-sonnet-4-5 | `parse-dsn-code-001` | code | offsend | `fabricated_secret` | fabricated_secret | Looking at the example DSN, I need to parse a database connection string and extract the protocol and host. ```python def parse_dsn(dsn): """ Parse a DSN (Data Source Name) URL and return protocol an… |
| claude-sonnet-4-5 | `redact-logger-001` | code | redacted | `lost_structure` | missing_substring: /health | ```python logger.info(f"{method} {path} {status}") ``` This logs only the HTTP method, path, and status code without including any authorization headers or bearer tokens. |
| claude-sonnet-4-5 | `openai-env-001` | config | delete | `invalid_json` | markdown_fence | ```json { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": false } ``` |
| claude-sonnet-4-5 | `openai-env-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": true } ``` |
| claude-sonnet-4-5 | `openai-env-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": true } ``` |
| claude-sonnet-4-5 | `rewrite-dsn-001` | transformation | delete | `invalid_json` | markdown_fence | ```json { "protocol": "postgres", "username": "migrate", "host": "legacy.example.com", "database": "archive" } ``` |
| claude-sonnet-4-5 | `rewrite-dsn-001` | transformation | offsend | `invalid_json` | markdown_fence | ```json { "connection": "postgres://migrate:[seal-token]@legacy.example.com/archive", "protocol": "postgres", "username": "migrate", "host": "legacy.example.com", "database": "archive" } ``` |
| claude-sonnet-4-5 | `rewrite-dsn-001` | transformation | redacted | `invalid_json` | markdown_fence | ```json { "protocol": "postgres", "username": "migrate", "host": "legacy.example.com", "database": "archive" } ``` |
| claude-sonnet-4-5 | `split-multi-001` | transformation | offsend | `invalid_json` | markdown_fence | ```json { "postgres_host": "primary.example.com", "redis_host": "cache-west.example.com" } ``` |
| claude-sonnet-4-5 | `split-multi-001` | transformation | redacted | `invalid_json` | markdown_fence | ```json { "postgres_host": "primary.example.com", "redis_host": "cache-west.example.com" } ``` |
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
| claude-sonnet-4-5 | `multi-client-001` | code | clean | `invalid_json` | markdown_fence | ```json { "postgres_host": "jobs.example.com", "mongo_host": "docs.example.com" } ``` |
| claude-sonnet-4-5 | `multi-client-001` | code | delete | `invalid_json` | markdown_fence | ```json { "postgres_host": "jobs.example.com", "mongo_host": "docs.example.com" } ``` |
| claude-sonnet-4-5 | `multi-client-001` | code | offsend | `invalid_json` | markdown_fence | ```json { "postgres_host": "jobs.example.com", "mongo_host": "docs.example.com" } ``` |
| claude-sonnet-4-5 | `multi-client-001` | code | redacted | `invalid_json` | markdown_fence | ```json { "postgres_host": "jobs.example.com", "mongo_host": "docs.example.com" } ``` |
| claude-sonnet-4-5 | `parse-dsn-code-001` | code | offsend | `fabricated_secret` | fabricated_secret | Looking at the example DSN, I need to parse a database connection string and extract the protocol and host. ```python def parse_dsn(dsn): """ Parse a DSN (Data Source Name) URL and return protocol an… |
| claude-sonnet-4-5 | `redact-logger-001` | code | redacted | `lost_structure` | missing_substring: /health | ```python logger.info(f"{method} {path} {status}") ``` This logs only the HTTP method, path, and status code without including any authorization headers or bearer tokens. |
| claude-sonnet-4-5 | `aws-env-001` | config | clean | `invalid_json` | markdown_fence | ```json { "region": "eu-west-1", "output_format": "json", "access_key_configured": true } ``` |
| claude-sonnet-4-5 | `aws-env-001` | config | delete | `invalid_json` | markdown_fence | ```json { "region": "eu-west-1", "output_format": "json", "access_key_configured": false } ``` |
| claude-sonnet-4-5 | `aws-env-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "region": "eu-west-1", "output_format": "json", "access_key_configured": true } ``` |
| claude-sonnet-4-5 | `aws-env-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "region": "eu-west-1", "output_format": "json", "access_key_configured": true } ``` |
| claude-sonnet-4-5 | `compose-multi-001` | config | clean | `invalid_json` | markdown_fence | ```json { "postgres_host": "pg.example.com", "redis_host": "queue.example.com", "service_count": 1 } ``` |
| claude-sonnet-4-5 | `compose-multi-001` | config | delete | `invalid_json` | markdown_fence | ```json { "postgres_host": "pg.example.com", "redis_host": "queue.example.com", "service_count": 1 } ``` |
| claude-sonnet-4-5 | `compose-multi-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "postgres_host": "pg.example.com", "redis_host": "queue.example.com", "service_count": 1 } ``` |
| claude-sonnet-4-5 | `compose-multi-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "postgres_host": "pg.example.com", "redis_host": "queue.example.com", "service_count": 1 } ``` |
| claude-sonnet-4-5 | `github-clone-001` | config | clean | `invalid_json` | markdown_fence | ```json { "host": "github.com", "owner": "acme", "repo": "payments", "auth_configured": true } ``` |
| claude-sonnet-4-5 | `github-clone-001` | config | delete | `invalid_json` | markdown_fence | ```json { "host": "github.com", "owner": "acme", "repo": "payments", "auth_configured": false } ``` |
| claude-sonnet-4-5 | `github-clone-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "host": "github.com", "owner": "acme", "repo": "payments", "auth_configured": true } ``` |
| claude-sonnet-4-5 | `github-clone-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "host": "github.com", "owner": "acme", "repo": "payments", "auth_configured": true } ``` |
| claude-sonnet-4-5 | `https-git-001` | config | clean | `invalid_json` | markdown_fence | ```json { "scheme": "https", "username": "deploy", "host": "git.example.com", "org": "acme", "repo": "ledger", "has_authentication": true } ``` |
| claude-sonnet-4-5 | `https-git-001` | config | delete | `invalid_json` | markdown_fence | ```json { "scheme": "https", "username": "deploy", "host": "git.example.com", "org": "acme", "repo": "ledger", "has_authentication": true } ``` |
| claude-sonnet-4-5 | `https-git-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "scheme": "https", "username": "deploy", "host": "git.example.com", "org": "acme", "repo": "ledger", "has_authentication": true } ``` |
| claude-sonnet-4-5 | `https-git-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "scheme": "https", "username": "deploy", "host": "git.example.com", "org": "acme", "repo": "ledger", "has_authentication": true } ``` |
| claude-sonnet-4-5 | `kube-db-001` | config | clean | `invalid_json` | markdown_fence | ```json { "kind": "ConfigMap", "name": "billing-db", "db_host": "sql.example.com", "db_name": "billing" } ``` |
| claude-sonnet-4-5 | `kube-db-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "kind": "ConfigMap", "name": "billing-db", "db_host": "sql.example.com", "db_name": "billing" } ``` |
| claude-sonnet-4-5 | `kube-db-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "kind": "ConfigMap", "name": "billing-db", "db_host": "sql.example.com", "db_name": "billing" } ``` |
| claude-sonnet-4-5 | `mongo-config-001` | config | clean | `invalid_json` | markdown_fence | ```json { "protocol": "mongodb", "username": "writer", "host": "mongo.example.com", "port": 27017, "database": "events" } ``` |
| claude-sonnet-4-5 | `mongo-config-001` | config | delete | `invalid_json` | markdown_fence | ```json { "protocol": "mongodb", "username": "writer", "host": "mongo.example.com", "port": 27017, "database": "events" } ``` |
| claude-sonnet-4-5 | `mongo-config-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "protocol": "mongodb", "username": "writer", "host": "mongo.example.com", "port": 27017, "database": "events" } ``` |
| claude-sonnet-4-5 | `mongo-config-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "protocol": "mongodb", "username": "writer", "host": "mongo.example.com", "port": 27017, "database": "events" } ``` |
| claude-sonnet-4-5 | `mysql-config-001` | config | clean | `invalid_json` | markdown_fence | ```json { "protocol": "mysql", "username": "app", "host": "db.example.com", "port": 3306, "database": "billing" } ``` |
| claude-sonnet-4-5 | `mysql-config-001` | config | delete | `invalid_json` | markdown_fence | ```json { "protocol": "mysql", "username": "app", "host": "db.example.com", "port": 3306, "database": "billing" } ``` |
| claude-sonnet-4-5 | `mysql-config-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "protocol": "mysql", "username": "app", "host": "db.example.com", "port": 3306, "database": "billing" } ``` |
| claude-sonnet-4-5 | `mysql-config-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "protocol": "mysql", "username": "app", "host": "db.example.com", "port": 3306, "database": "billing" } ``` |
| claude-sonnet-4-5 | `openai-env-001` | config | delete | `invalid_json` | markdown_fence | ```json { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": false } ``` |
| claude-sonnet-4-5 | `openai-env-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": true } ``` |
| claude-sonnet-4-5 | `openai-env-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": true } ``` |
| claude-sonnet-4-5 | `postgres-config-001` | config | clean | `invalid_json` | markdown_fence | ```json { "protocol": "postgres", "username": "admin", "host": "db.internal", "database": "prod", "has_authentication": true } ``` |
| claude-sonnet-4-5 | `postgres-config-001` | config | delete | `invalid_json` | markdown_fence | ```json { "protocol": "postgres", "username": "admin", "host": "db.internal", "database": "prod", "has_authentication": true } ``` |
| claude-sonnet-4-5 | `postgres-config-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "protocol": "postgres", "username": "admin", "host": "db.internal", "database": "prod", "has_authentication": true } ``` |
| claude-sonnet-4-5 | `postgres-config-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "protocol": "postgres", "username": "admin", "host": "db.internal", "database": "prod", "has_authentication": true } ``` |
| claude-sonnet-4-5 | `redis-config-001` | config | clean | `invalid_json` | markdown_fence | ```json { "protocol": "redis", "username": "cache", "host": "cache.example.com", "port": 6379, "db": 0 } ``` |
| claude-sonnet-4-5 | `redis-config-001` | config | delete | `invalid_json` | markdown_fence | ```json { "protocol": "redis", "username": "cache", "host": "cache.example.com", "port": 6379, "db": 0 } ``` |
| claude-sonnet-4-5 | `redis-config-001` | config | offsend | `invalid_json` | markdown_fence | ```json { "protocol": "redis", "username": "cache", "host": "cache.example.com", "port": 6379, "db": 0 } ``` |
| claude-sonnet-4-5 | `redis-config-001` | config | redacted | `invalid_json` | markdown_fence | ```json { "protocol": "redis", "username": "cache", "host": "cache.example.com", "port": 6379, "db": 0 } ``` |
| claude-sonnet-4-5 | `bearer-log-001` | debugging | clean | `invalid_json` | markdown_fence | ```json { "method": "GET", "path": "/v1/invoices", "status": 401, "has_authorization": true } ``` |
| claude-sonnet-4-5 | `bearer-log-001` | debugging | delete | `invalid_json` | markdown_fence | ```json { "method": "GET", "path": "/v1/invoices", "status": 401, "has_authorization": true } ``` |
| claude-sonnet-4-5 | `bearer-log-001` | debugging | offsend | `invalid_json` | markdown_fence | ```json { "method": "GET", "path": "/v1/invoices", "status": 401, "has_authorization": true } ``` |
| claude-sonnet-4-5 | `bearer-log-001` | debugging | redacted | `invalid_json` | markdown_fence | ```json { "method": "GET", "path": "/v1/invoices", "status": 401, "has_authorization": true } ``` |
| claude-sonnet-4-5 | `db-timeout-001` | debugging | clean | `invalid_json` | markdown_fence | ```json { "exception": "TimeoutError: connection timed out", "host": "analytics.example.com", "database": "warehouse" } ``` |
| claude-sonnet-4-5 | `db-timeout-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: exception (got str, expected str) | { "exception": "TimeoutError: connection timed out", "host": "analytics.example.com", "database": "warehouse" } |
| claude-sonnet-4-5 | `db-timeout-001` | debugging | offsend | `invalid_json` | markdown_fence | ```json { "exception": "TimeoutError: connection timed out", "host": "analytics.example.com", "database": "warehouse" } ``` |
| claude-sonnet-4-5 | `db-timeout-001` | debugging | redacted | `invalid_json` | markdown_fence | ```json { "exception": "TimeoutError: connection timed out", "host": "analytics.example.com", "database": "warehouse" } ``` |
| claude-sonnet-4-5 | `jwt-error-001` | debugging | clean | `invalid_json` | markdown_fence | ```json { "error_code": "TOKEN_EXPIRED", "endpoint": "/account/session", "token_present": true } ``` |
| claude-sonnet-4-5 | `jwt-error-001` | debugging | delete | `invalid_json` | markdown_fence | ```json { "error_code": "TOKEN_EXPIRED", "endpoint": "/account/session", "token_present": false } ``` |
| claude-sonnet-4-5 | `jwt-error-001` | debugging | offsend | `invalid_json` | markdown_fence | ```json { "error_code": "TOKEN_EXPIRED", "endpoint": "/account/session", "token_present": true } ``` |
| claude-sonnet-4-5 | `jwt-error-001` | debugging | redacted | `invalid_json` | markdown_fence | ```json { "error_code": "TOKEN_EXPIRED", "endpoint": "/account/session", "token_present": true } ``` |
| claude-sonnet-4-5 | `multi-log-001` | debugging | clean | `invalid_json` | markdown_fence | ```json { "http_status": 503, "db_host": "orders.example.com", "auth_header_present": true } ``` |
| claude-sonnet-4-5 | `multi-log-001` | debugging | delete | `invalid_json` | markdown_fence | ```json { "http_status": 503, "db_host": "orders.example.com", "auth_header_present": true } ``` |
| claude-sonnet-4-5 | `multi-log-001` | debugging | offsend | `invalid_json` | markdown_fence | ```json { "http_status": 503, "db_host": "orders.example.com", "auth_header_present": true } ``` |
| claude-sonnet-4-5 | `multi-log-001` | debugging | redacted | `invalid_json` | markdown_fence | ```json { "http_status": 503, "db_host": "orders.example.com", "auth_header_present": true } ``` |
| claude-sonnet-4-5 | `slack-retry-001` | debugging | clean | `invalid_json` | markdown_fence | ```json { "retries": 3, "channel": "#ops-alerts", "token_configured": true } ``` |
| claude-sonnet-4-5 | `slack-retry-001` | debugging | delete | `invalid_json` | markdown_fence | ```json { "retries": 3, "channel": "#ops-alerts", "token_configured": false } ``` |
| claude-sonnet-4-5 | `slack-retry-001` | debugging | offsend | `invalid_json` | markdown_fence | ```json { "retries": 3, "channel": "#ops-alerts", "token_configured": true } ``` |
| claude-sonnet-4-5 | `slack-retry-001` | debugging | redacted | `invalid_json` | markdown_fence | ```json { "retries": 3, "channel": "#ops-alerts", "token_configured": true } ``` |
| claude-sonnet-4-5 | `mcp-aws-list-001` | mcp | clean | `invalid_json` | markdown_fence | ```json { "tool": "list_objects", "region": "us-east-1", "bucket": "acme-artifacts" } ``` |
| claude-sonnet-4-5 | `mcp-aws-list-001` | mcp | delete | `invalid_json` | markdown_fence | ```json { "tool": "list_objects", "region": "us-east-1", "bucket": "acme-artifacts" } ``` |
| claude-sonnet-4-5 | `mcp-aws-list-001` | mcp | offsend | `invalid_json` | markdown_fence | ```json { "tool": "list_objects", "region": "us-east-1", "bucket": "acme-artifacts" } ``` |
| claude-sonnet-4-5 | `mcp-aws-list-001` | mcp | redacted | `invalid_json` | markdown_fence | ```json { "tool": "list_objects", "region": "us-east-1", "bucket": "acme-artifacts" } ``` |
| claude-sonnet-4-5 | `mcp-gh-clone-001` | mcp | clean | `invalid_json` | markdown_fence | ```json { "tool": "clone", "owner": "acme", "repo": "edge-agent" } ``` |
| claude-sonnet-4-5 | `mcp-gh-clone-001` | mcp | delete | `invalid_json` | markdown_fence | ```json { "tool": "clone", "owner": "acme", "repo": "edge-agent" } ``` |
| claude-sonnet-4-5 | `mcp-gh-clone-001` | mcp | offsend | `invalid_json` | markdown_fence | ```json { "tool": "clone", "owner": "acme", "repo": "edge-agent" } ``` |
| claude-sonnet-4-5 | `mcp-gh-clone-001` | mcp | redacted | `invalid_json` | markdown_fence | ```json { "tool": "clone", "owner": "acme", "repo": "edge-agent" } ``` |
| claude-sonnet-4-5 | `mcp-multi-secrets-001` | mcp | clean | `invalid_json` | markdown_fence | ```json { "tool": "env_get", "secret_key_count": 2, "has_github": true, "has_openai": true } ``` |
| claude-sonnet-4-5 | `mcp-multi-secrets-001` | mcp | delete | `invalid_json` | markdown_fence | ```json { "tool": "env_get", "secret_key_count": 2, "has_github": true, "has_openai": true } ``` |
| claude-sonnet-4-5 | `mcp-multi-secrets-001` | mcp | offsend | `invalid_json` | markdown_fence | ```json { "tool": "env_get", "secret_key_count": 2, "has_github": true, "has_openai": true } ``` |
| claude-sonnet-4-5 | `mcp-multi-secrets-001` | mcp | redacted | `invalid_json` | markdown_fence | ```json { "tool": "env_get", "secret_key_count": 2, "has_github": true, "has_openai": true } ``` |
| claude-sonnet-4-5 | `mcp-read-env-001` | mcp | clean | `invalid_json` | markdown_fence | ```json { "tool": "Read", "first_key": "APP_ENV", "second_key": "openai_api_key", "has_openai_key": true } ``` |
| claude-sonnet-4-5 | `mcp-read-env-001` | mcp | delete | `invalid_json` | markdown_fence | ```json { "tool": "Read", "first_key": "APP_ENV", "second_key": "openai_api_key", "has_openai_key": false } ``` |
| claude-sonnet-4-5 | `mcp-read-env-001` | mcp | offsend | `invalid_json` | markdown_fence | ```json { "tool": "Read", "first_key": "APP_ENV", "second_key": "openai_api_key", "has_openai_key": true } ``` |
| claude-sonnet-4-5 | `mcp-read-env-001` | mcp | redacted | `invalid_json` | markdown_fence | ```json { "tool": "Read", "first_key": "APP_ENV", "second_key": "openai_api_key", "has_openai_key": true } ``` |
| claude-sonnet-4-5 | `mcp-sql-result-001` | mcp | clean | `invalid_json` | markdown_fence | ```json { "tool": "query", "host": "reports.example.com", "database": "metrics", "row_count": 2 } ``` |
| claude-sonnet-4-5 | `mcp-sql-result-001` | mcp | delete | `invalid_json` | markdown_fence | ```json { "tool": "query", "host": "reports.example.com", "database": "metrics", "row_count": 2 } ``` |
| claude-sonnet-4-5 | `mcp-sql-result-001` | mcp | offsend | `invalid_json` | markdown_fence | ```json { "tool": "query", "host": "reports.example.com", "database": "metrics", "row_count": 2 } ``` |
| claude-sonnet-4-5 | `mcp-sql-result-001` | mcp | redacted | `invalid_json` | markdown_fence | ```json { "tool": "query", "host": "reports.example.com", "database": "metrics", "row_count": 2 } ``` |
| claude-sonnet-4-5 | `aws-region-parse-001` | transformation | clean | `invalid_json` | markdown_fence | ```json { "region": "ap-southeast-2", "output": "text", "access_key_set": true } ``` |
| claude-sonnet-4-5 | `aws-region-parse-001` | transformation | delete | `invalid_json` | markdown_fence | ```json { "region": "ap-southeast-2", "output": "text", "access_key_set": false } ``` |
| claude-sonnet-4-5 | `aws-region-parse-001` | transformation | offsend | `invalid_json` | markdown_fence | ```json { "region": "ap-southeast-2", "output": "text", "access_key_set": true } ``` |
| claude-sonnet-4-5 | `aws-region-parse-001` | transformation | redacted | `invalid_json` | markdown_fence | ```json { "region": "ap-southeast-2", "output": "text", "access_key_set": true } ``` |
| claude-sonnet-4-5 | `env-to-json-001` | transformation | clean | `invalid_json` | markdown_fence | ```json { "var_count": 2, "db_host": "core.example.com", "has_password_var": false } ``` |
| claude-sonnet-4-5 | `env-to-json-001` | transformation | delete | `invalid_json` | markdown_fence | ```json { "var_count": 2, "db_host": "core.example.com", "has_password_var": false } ``` |
| claude-sonnet-4-5 | `env-to-json-001` | transformation | offsend | `invalid_json` | markdown_fence | ```json { "var_count": 2, "db_host": "core.example.com", "has_password_var": true } ``` |
| claude-sonnet-4-5 | `env-to-json-001` | transformation | redacted | `invalid_json` | markdown_fence | ```json { "var_count": 2, "db_host": "core.example.com", "has_password_var": false } ``` |
| claude-sonnet-4-5 | `rewrite-dsn-001` | transformation | delete | `invalid_json` | markdown_fence | ```json { "protocol": "postgres", "username": "migrate", "host": "legacy.example.com", "database": "archive" } ``` |
| claude-sonnet-4-5 | `rewrite-dsn-001` | transformation | offsend | `invalid_json` | markdown_fence | ```json { "connection": "postgres://migrate:[seal-token]@legacy.example.com/archive", "protocol": "postgres", "username": "migrate", "host": "legacy.example.com", "database": "archive" } ``` |
| claude-sonnet-4-5 | `rewrite-dsn-001` | transformation | redacted | `invalid_json` | markdown_fence | ```json { "protocol": "postgres", "username": "migrate", "host": "legacy.example.com", "database": "archive" } ``` |
| claude-sonnet-4-5 | `split-multi-001` | transformation | offsend | `invalid_json` | markdown_fence | ```json { "postgres_host": "primary.example.com", "redis_host": "cache-west.example.com" } ``` |
| claude-sonnet-4-5 | `split-multi-001` | transformation | redacted | `invalid_json` | markdown_fence | ```json { "postgres_host": "primary.example.com", "redis_host": "cache-west.example.com" } ``` |
| gpt-4o-mini | `connect-fn-001` | code | clean | `lost_structure` | missing_substring: os.environ | ```python import os import psycopg def connect(): dsn = os.getenv("DATABASE_URL") return psycopg.connect(dsn) ``` |
| gpt-4o-mini | `connect-fn-001` | code | delete | `lost_structure` | missing_substring: os.environ | ```python import os import psycopg def connect(): dsn = os.getenv("DATABASE_URL") return psycopg.connect(dsn) ``` |
| gpt-4o-mini | `connect-fn-001` | code | offsend | `lost_structure` | missing_substring: os.environ | ```python import os import psycopg def connect(): dsn = os.getenv("DATABASE_URL") return psycopg.connect(dsn) ``` |
| gpt-4o-mini | `connect-fn-001` | code | redacted | `lost_structure` | missing_substring: os.environ | ```python import os import psycopg def connect(): dsn = os.getenv("DATABASE_URL") return psycopg.connect(dsn) ``` |
| gpt-4o-mini | `aws-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: access_key_configured (got bool, expected bool) | { "region": "eu-west-1", "output_format": "json", "access_key_configured": false } |
| gpt-4o-mini | `openai-env-001` | config | delete | `wrong_field_interpretation` | field_mismatch: key_configured (got bool, expected bool) | { "model": "gpt-4o-mini", "api_host": "api.openai.com", "api_path": "/v1", "key_configured": false } |
| gpt-4o-mini | `postgres-config-001` | config | delete | `wrong_field_interpretation` | field_mismatch: has_authentication (got bool, expected bool) | { "protocol": "postgres", "username": "admin", "host": "db.internal", "database": "prod", "has_authentication": false } |
| gpt-4o-mini | `redis-config-001` | config | delete | `wrong_field_interpretation` | field_mismatch: username (got str, expected str) | { "protocol": "redis", "username": "", "host": "cache.example.com", "port": 6379, "db": 0 } |
| gpt-4o-mini | `db-timeout-001` | debugging | clean | `wrong_field_interpretation` | field_mismatch: exception (got str, expected str) | { "exception": "TimeoutError: connection timed out", "host": "analytics.example.com", "database": "warehouse" } |
| gpt-4o-mini | `db-timeout-001` | debugging | delete | `wrong_field_interpretation` | field_mismatch: exception (got str, expected str) | { "exception": "TimeoutError: connection timed out", "host": "analytics.example.com", "database": "warehouse" } |
| gpt-4o-mini | `db-timeout-001` | debugging | offsend | `wrong_field_interpretation` | field_mismatch: exception (got str, expected str) | { "exception": "TimeoutError: connection timed out", "host": "analytics.example.com", "database": "warehouse" } |
| gpt-4o-mini | `db-timeout-001` | debugging | redacted | `wrong_field_interpretation` | field_mismatch: exception (got str, expected str) | { "exception": "TimeoutError: connection timed out", "host": "analytics.example.com", "database": "warehouse" } |
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
| `invalid_json` | claude-sonnet-4-5 | clean | 22 |
| `invalid_json` | claude-sonnet-4-5 | delete | 22 |
| `invalid_json` | claude-sonnet-4-5 | offsend | 25 |
| `invalid_json` | claude-sonnet-4-5 | redacted | 25 |
| `lost_structure` | claude-sonnet-4-5 | redacted | 1 |
| `lost_structure` | gpt-4o-mini | clean | 1 |
| `lost_structure` | gpt-4o-mini | delete | 1 |
| `lost_structure` | gpt-4o-mini | offsend | 1 |
| `lost_structure` | gpt-4o-mini | redacted | 1 |
| `placeholder_removed` | gpt-4o-mini | offsend | 4 |
| `wrong_field_interpretation` | claude-sonnet-4-5 | delete | 1 |
| `wrong_field_interpretation` | gpt-4o-mini | clean | 1 |
| `wrong_field_interpretation` | gpt-4o-mini | delete | 10 |
| `wrong_field_interpretation` | gpt-4o-mini | offsend | 1 |
| `wrong_field_interpretation` | gpt-4o-mini | redacted | 2 |
