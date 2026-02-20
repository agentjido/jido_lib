# Jido.Lib

Standard library modules for the Jido ecosystem.

## Canonical GitHub PR Bot API

`Jido.Lib` provides a signal-first GitHub PR bot:

- `Jido.Lib.Github.Agents.PrBot.run_issue/2`
- `Jido.Lib.Github.Agents.PrBot.build_intake/2`
- `Jido.Lib.Github.Agents.PrBot.intake_signal/1`

```elixir
result =
  Jido.Lib.Github.Agents.PrBot.run_issue(
    "https://github.com/owner/repo/issues/42",
    jido: Jido.Default,
    timeout: 900_000
  )
```

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
mix jido_lib.github.pr https://github.com/owner/repo/issues/42
mix jido_lib.github.triage https://github.com/owner/repo/issues/42
mix jido_lib.github.pr https://github.com/owner/repo/issues/42 --provider codex
mix jido_lib.github.triage https://github.com/owner/repo/issues/42 --provider gemini
```

## Required Environment

- `SPRITES_TOKEN`
- `GH_TOKEN` or `GITHUB_TOKEN`
- provider-specific API/auth env:
  - Claude: one of `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_API_KEY`
  - Amp: `AMP_API_KEY`
  - Codex: `OPENAI_API_KEY`
  - Gemini: one of `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`

## Workflow Documentation

Detailed workflow spec:

- `docs/github_pr_bot_workflow.md`
- `docs/github_issue_triage_workflow.md`

## Notes

- Workflow is sprite-first.
- Runtime validation runs before provider execution.
- Teardown is retry + verify, with warnings if verification fails.
- Generic shell backend abstractions are intentionally not part of `jido_lib`.

## Development

```bash
mix setup
mix test
mix quality
```
