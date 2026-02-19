# Jido.Lib

Standard library modules for the Jido ecosystem.

## Canonical GitHub Triage API

`Jido.Lib` provides a signal-first GitHub issue triage bot:

- `Jido.Lib.Github.Agents.IssueTriageBot.triage/2`
- `Jido.Lib.Github.Agents.IssueTriageBot.intake_signal/2`
- `Jido.Lib.Github.Schema.IssueTriage.Result`

```elixir
result =
  Jido.Lib.Github.Agents.IssueTriageBot.triage(
    "https://github.com/owner/repo/issues/42",
    jido: Jido.Default,
    timeout: 600_000
  )
```

## Mix Task

```bash
mix jido_lib.github.triage https://github.com/owner/repo/issues/42
```

## Required Environment

- `SPRITES_TOKEN`
- `ANTHROPIC_BASE_URL`
- one of `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_API_KEY`
- `GH_TOKEN` or `GITHUB_TOKEN`

## Workflow Documentation

Detailed workflow spec:

- `docs/github_issue_triage_workflow.md`

## Notes

- Workflow is sprite-first.
- Runtime validation runs before Claude.
- Teardown is retry + verify, with warnings if verification fails.
- Generic shell backend abstractions are intentionally not part of `jido_lib`.

## Development

```bash
mix setup
mix test
mix quality
```
