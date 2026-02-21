# Jido.Lib

Standard library modules for the Jido ecosystem, including the canonical GitHub Issue Triage bot and PR bot workflows.

## Package Purpose

`jido_lib` owns GitHub-domain workflow orchestration:

- issue triage in Sprite workspaces
- provider-swappable coding agent execution (`:claude | :amp | :codex | :gemini`)
- branch/commit/check/push/PR/comment lifecycle for issue-to-PR automation

Lower-level runtime concerns stay in `jido_harness`, `jido_shell`, and `jido_vfs`.

## Canonical APIs

### GitHub PR Bot

- `Jido.Lib.Github.Agents.PrBot.run_issue/2`
- `Jido.Lib.Github.Agents.PrBot.build_intake/2`
- `Jido.Lib.Github.Agents.PrBot.intake_signal/1`

```elixir
Jido.Lib.Github.Agents.PrBot.run_issue(
  "https://github.com/owner/repo/issues/42",
  jido: Jido.Default,
  timeout: 900_000
)
```

### GitHub Issue Triage Bot

- `Jido.Lib.Github.Agents.IssueTriageBot.triage/2`
- `Jido.Lib.Github.Agents.IssueTriageBot.intake_signal/2`

```elixir
Jido.Lib.Github.Agents.IssueTriageBot.triage(
  "https://github.com/owner/repo/issues/42",
  jido: Jido.Default,
  timeout: 600_000
)
```

## Mix Tasks

```bash
mix jido_lib.github.triage https://github.com/owner/repo/issues/42
mix jido_lib.github.pr https://github.com/owner/repo/issues/42
```

## Testing Paths

### 1) Deterministic local test suite

```bash
mix test
mix quality
```

Bot-focused suite:

```bash
mix test test/jido_lib/github test/mix/tasks/jido_lib.github.triage_test.exs test/mix/tasks/jido_lib.github.pr_test.exs
```

### 2) Live Issue Triage bot smoke test

```bash
mix jido_lib.github.triage \
  https://github.com/owner/repo/issues/42 \
  --provider claude \
  --timeout 600 \
  --setup-cmd "mix deps.get"
```

### 3) Live PR bot smoke test

For orchestration-only validation (skip project checks):

```bash
mix jido_lib.github.pr \
  https://github.com/owner/repo/issues/42 \
  --provider claude \
  --timeout 600 \
  --setup-cmd "mix deps.get" \
  --check-cmd "true"
```

For full gating with project checks:

```bash
mix jido_lib.github.pr \
  https://github.com/owner/repo/issues/42 \
  --provider claude \
  --timeout 600 \
  --setup-cmd "mix deps.get" \
  --check-cmd "mix test --exclude integration"
```

Note: when `--check-cmd` is omitted, PR bot defaults to `mix test --exclude integration`.

## Credentials Required for Successful Live Runs

### Core required

- `SPRITES_TOKEN`
- `GH_TOKEN` or `GITHUB_TOKEN`

### Provider-specific required

- `claude`: one of `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_API_KEY`
- `amp`: `AMP_API_KEY`
- `codex`: `OPENAI_API_KEY`
- `gemini`: one of `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`

### Optional but common

- `ANTHROPIC_BASE_URL` (for Claude-compatible proxy endpoints such as Z.AI)

## Workflow Docs

- `docs/github_issue_triage_workflow.md`
- `docs/github_pr_bot_workflow.md`

## Development

```bash
mix setup
mix test
mix quality
```
