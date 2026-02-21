# Jido Lib GitHub Telemetry Contract

`Jido.Lib.Github.Observe` is the canonical telemetry boundary for GitHub bot pipelines.

## Canonical Namespaces

| Namespace | Use |
| --- | --- |
| `[:jido, :lib, :github, :pipeline, ...]` | Pipeline start/stop/exception lifecycle |
| `[:jido, :lib, :github, :action, ...]` | Runic action-node execution lifecycle |
| `[:jido, :lib, :github, :coding_agent, ...]` | Provider coding-agent stream summaries |
| `[:jido, :runic, ...]` | Runic-native runtime events (forwarded/consumed) |

## Required Metadata

The observe wrapper guarantees these keys exist on every emitted event:

- `:request_id`
- `:run_id`
- `:provider`
- `:owner`
- `:repo`
- `:issue_number`
- `:session_id`

## Sensitive Data Redaction

Telemetry metadata is sanitized recursively before emission.

Redaction applies to keys such as:

- `token`, `auth_token`, `api_key`, `client_secret`, `password`
- any key containing `secret_`
- any key ending in `_token`, `_key`, `_secret`, `_password`

All sensitive values are replaced with `"[REDACTED]"`.
