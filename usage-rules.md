# Usage Rules for AI Assistants

## Core Rules

1. Keep GitHub triage code under `Jido.Lib.Github.*`.
2. Do not add generic shell backend layers in this package.
3. Use `Jido.Shell.ShellSession` + `Jido.Shell.Agent` directly for sprite execution.
4. Use Zoi for public request/result structs.
5. Use `Jido.Lib.Error` for package-level error helpers.

## Testing

- Prefer deterministic unit tests with fake shell/session modules.
- Keep live Sprite/GitHub tests as integration-only.
- Verify workflow order and teardown behavior in orchestrator tests.

